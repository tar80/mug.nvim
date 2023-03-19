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

---The branch name that the head points to
---@param root string Project root path
---@param filepath string Filepath used to get branch name
---@param state string Branch state
---@return string # Branch name
---@return string # Branch state
local function branch_head(root, filepath, state)
  local branch_name = '(unknown)'
  local line = io.lines(filepath)()

  if line ~= nil then
    branch_name = line:match('refs/heads/(.+)')

    if branch_name == nil then
      branch_name = '(unknown)'

      for l in io.lines(root .. '/logs/HEAD') do
        if l:find('checkout: moving from', 1, true) ~= nil then
          branch_name = l:match('to%s([^%s]+)')
          state = 'Detached'
          break
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

---@param path string Git reopsitory root path
---@return string? # Git branch name
M.branch_name = function(path)
  local key = branch_cache_key(path)
  local result = 'cached'

  if branch_cache[path] == nil or branch_cache[path].key ~= key then
    if vim.fn.isdirectory(path .. '/.git') == 0 then
      branch_cache[path] = { name = nil, info = nil, key = key, stats = nil }
      result = ''
    else
      if vim.tbl_count(branch_cache) >= 20 then
        ---Initialize when the cache reaches the upper limit
        branch_cache = {}
      end

      local name, info = get_branch_info(path)
      branch_cache[path] = { name = name, info = info, key = key, stats = get_branch_stats(path, true) }
      result = 'saved'
    end
  end

  vim.b.mug_branch_name = branch_cache[path].name or _G.Mug.symbol_not_repository
  vim.b.mug_branch_info = branch_cache[path].info
  vim.b.mug_branch_stats = branch_cache[path].stats

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

  if branch_cache[root] == nil then
    local msg = 'Not a git repository'

    if response then
      util.notify(msg, HEADER, 3)
    end

    return { msg }
  end

  local stats, stdout = get_branch_stats(root, false, ignore)
  vim.b.mug_branch_stats = stats
  branch_cache[root].stats = stats

  if response then
    util.notify('Update index information', HEADER, 2)
  end

  return stdout
end

return M
