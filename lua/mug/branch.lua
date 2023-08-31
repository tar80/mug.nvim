--[[
-- This code based on vim-g(https://github.com/kana/vim-g/autoload/g/branch.vim)
-- Under the MIT license
--]]

local util = require('mug.module.util')

---@class branch
---@field branch_name fun(path: string) : string
---@field branch_stats fun(root: string?, responce?: boolean, ignore?:boolean) : table
local M = {}
local HEADER = 'mug/branch'
local branch_cache = {}
local event_spec = {
  { detail = 'Rebase', att = 'file', parent = '/rabase-apply/rebasing', filename = '/HEAD' },
  { detail = 'Am', att = 'file', parent = '/rabase-apply/applying', filename = '/HEAD' },
  { detail = 'Am/Rebase', att = 'dir', parent = '/rebase-apply', filename = '/HEAD' },
  { detail = 'Rebase-i', att = 'file', parent = '/rebase-merge/interactive', filename = '/rebase-merge/head-name' },
  { detail = 'Rebase-m', att = 'dir', parent = '/rebase-merge', filename = '/rebase-merge/head-name' },
  { detail = 'Merging', att = 'file', parent = '/MERGE_HEAD', filename = '/HEAD' },
}

---@param root string project-root path
---@return integer # cached hash of target branch
local function branch_cache_key(root)
  return vim.fn.getftime(root .. '/.git/HEAD') + vim.fn.getftime(root .. '/.git/MERGE_HEAD')
end

---@param filepath string
---@return table # A line-by-line table of file contents
local function file_read(filepath)
  local handle = io.open(filepath, 'r')
  local contents = {}

  if handle ~= nil then
    for l in handle:lines() do
      table.insert(contents, l)
    end

    io.close(handle)
  end

  return contents
end

---The branch name that the head points to
---@param root string Project root path
---@param filepath string Filepath used to get branch name
---@param state string Branch state
---@return string # Branch name
---@return string # Branch state
local function branch_head(root, filepath, state)
  local branch_name = '(unknown)'
  local lines = file_read(filepath)

  if #lines > 0 then
    branch_name = lines[1]:match('refs/heads/(.+)')

    if branch_name == nil then
      branch_name = '(unknown)'
      local logs_head = string.format('%s/logs/HEAD', root)

      if util.file_exist(logs_head) then
        lines = file_read(logs_head)

        for i = #lines, 1, -1 do
          if lines[i]:find('checkout: moving from', 1, true) ~= nil then
            branch_name = lines[i]:match('to%s([^%s]+)')
            state = 'Detached'
          end
        end
      end
    end
  end

  return branch_name, state
end

---@param root string Project root path
---@return string # Branch name
---@return string # Branch state
local function get_branch_info(root)
  local git_dir = root .. '/.git'
  local add_info = ''
  local head_info;

  (function()
    local head_spec, head_file

    for _, v in ipairs(event_spec) do
      head_spec = git_dir .. v.parent

      if v.att == 'file' and util.file_exist(head_spec) then
        head_file = git_dir .. v.filename

        if util.file_exist(head_file) then
          head_info, add_info = branch_head(root, head_file, v.detail)

          return
        end
      elseif v.att == 'dir' and vim.fn.isdirectory(head_spec) == 1 then
        head_file = git_dir .. v.filename

        if util.file_exist(head_file) then
          head_info, add_info = branch_head(root, head_file, v.detail)

          return
        end
      end
    end

    head_info, add_info = branch_head(git_dir, git_dir .. '/HEAD', add_info)
  end)()

  return head_info, add_info
end

---@param root string Project root path
---@param chain boolean Child process of a branch_name()
---@param ignore? boolean Add option "--ignored"
---@return table|nil # { s = staged count, u = unstaged count, c = conflicted count }
---@return table # Git status stdout
local function get_branch_stats(root, chain, ignore)
  if not chain and vim.fn.isdirectory(root) == 0 then
    return nil, {}
  end

  local ignored = ignore and '--ignored' or ''
  local cmdline =
    util.gitcmd({ wd = root, noquotepath = true, cmd = 'status', opts = { '-b', ignored, '--porcelain' } })
  local stdout = util.get_stdout(table.concat(cmdline, ' '))
  local list = vim.split(stdout, '\n')
  stdout = nil

  if list[1]:find('^fatal:') then
    return nil, {}
  end

  local staged, unstaged, conflicted = 0, 0, 0

  for i = 2, #list do
    if list[i]:find('UU') then
      conflicted = conflicted + 1
    end

    if list[i]:sub(1, 1):find('[MADRC]') then
      staged = staged + 1
    end

    if list[i]:sub(2, 2):find('[^%s!]') then
      unstaged = unstaged + 1
    end
  end

  return { s = staged, u = unstaged, c = conflicted }, list
end

---@param cwd string Current working directory
---@return string? # Git branch name
M.branch_name = function(cwd)
  local git_root = vim.fs.find('.git', {
    type = 'directory',
    upward = true,
  })

  if #git_root ~= 0 then
    git_root = git_root[1]:sub(1, -6)
  else
    git_root = cwd
  end

  local key = branch_cache_key(git_root)
  local result = 'cached'

  if branch_cache[cwd] == nil or branch_cache[cwd].key ~= key then
    if vim.fn.isdirectory(git_root .. '/.git') == 0 then
      branch_cache[cwd] = { root = nil, name = nil, info = nil, key = key, stats = nil }
      result = ''
    else
      if vim.tbl_count(branch_cache) >= 20 then
        ---Initialize when the cache reaches the upper limit
        branch_cache = {}
      end

      local name, info = get_branch_info(git_root)
      branch_cache[cwd] =
        { root = git_root, name = name, info = info, key = key, stats = get_branch_stats(git_root, true) }
      result = 'saved'
    end
  end

  vim.b.mug_branch_name = branch_cache[cwd].name or _G.Mug.symbol_not_repository
  vim.b.mug_branch_info = branch_cache[cwd].info
  vim.b.mug_branch_stats = branch_cache[cwd].stats

  return result
end

---@param root string? Project root path
---@param response? boolean Show response message
---@param ignore? boolean Add option "--ignored"
---@return table # Debug message or util.notify()
M.branch_stats = function(root, response, ignore)
  if not root then
    root = util.pwd()
  end

  local cached = branch_cache[root]

  if cached == nil then
    local msg = 'Not a git repository'

    if response then
      util.notify(msg, HEADER, 3)
    end

    return { msg }
  end

  local stats, stdout = get_branch_stats(cached.root, false, ignore)
  vim.b.mug_branch_stats = stats
  cached.stats = stats

  if response then
    util.notify('Update index information', HEADER, 2)
  end

  return stdout
end

return M
