--[[
-- This code based on the vim-findroot(https://github.com/mattn/vim-findroot)
-- Under the MIT license
--]]

local util = require('mug.module.util')
local branch = require('mug.branch')

---@class ws
local M = {}
local HEADER = 'mug/findroot'
local FINDROOT_DISABLED = 'mug_findroot_disable'
---@type boolean
local skip_event

---Compare the specified path with pwd
---@param path string Path to be compared
---@return string # Comparing results
local function compare_wd(path)
  if path == '' then
    return 'empty'
  elseif path == util.pwd() then
    return 'same'
  end

  return 'differ'
end

---Get parent directory other than specific path
---@return string? # Result of comparing parent directories
---@return string? # Parent directory path
local get_parent_directory = function()
  local path = util.dirpath('/')
  local status = compare_wd(path)
  local buftype = vim.api.nvim_get_option_value('buftype', { buf = 0 })

  if path == '.' then
    return nil, nil
  end

  if buftype ~= '' or path:match('^%w+://') ~= nil then
    return 'special', path
  end

  local buf_ft = vim.api.nvim_get_option_value('filetype', { buf = 0 })
  local ignore_ft = _G.Mug.ignore_filetypes

  if vim.tbl_contains(ignore_ft, buf_ft) then
    return 'ignore', path
  end

  return status, path
end

---Set branch name
---@param marker string Git repository root marker
---@param path string Detected path
local function query_branch_is(marker, path)
  if marker == '' then
    vim.b.mug_branch_name = _G.Mug.symbol_not_repository
  elseif marker:find('.git', 1, true) then
    branch.branch_name(path)
  end
end

---Detect the project root path
---@async
---@param path string Path to be detected
---@return string? # The project root path
local function detect_project_root(path)
  if vim.fn.isdirectory(path) == 1 then
    path = path:gsub('([^/])$', '%1/')
  end

  local co = coroutine.create(function(patterns, upward)
    local match_path

    for dir in vim.fs.parents(upward) do
      if #patterns == 0 then
        assert(false)
      end

      for i, v in ipairs(patterns) do
        match_path = string.format('%s/%s', dir, v)

        if v:find('*', 1, true) and vim.fn.glob(match_path, 1) ~= '' then
          patterns, upward = coroutine.yield(i, dir, '')
          break
        end

        if v:match('/$') and vim.fn.isdirectory(match_path) ~= 0 then
          patterns, upward = coroutine.yield(i, dir, v)
          break
        end

        if util.file_exist(match_path) then
          patterns, upward = coroutine.yield(i, dir, v)
          break
        end
      end
    end

    assert(false)
  end)

  local root_patterns = vim.deepcopy(_G.Mug.root_patterns)
  local marker = ''

  repeat
    local stat, ret, root, pattern = coroutine.resume(co, root_patterns, path)

    if stat then
      root_patterns = { unpack(root_patterns, 1, ret - 1) }
      path = root
      marker = pattern
    end
  until coroutine.status(co) == 'dead'

  query_branch_is(marker, path)

  return path
end

---Set local working directory
---@param response? boolean show result message
---@return 'startup'|'change'|'same'|'differ'
M.set_workspace_root = function(response)
  local disable_global = vim.g[FINDROOT_DISABLED]
  local disable_local = vim.b[FINDROOT_DISABLED]

  ---NOTE: Need "nil", not "vim.NIL"
  vim.g[FINDROOT_DISABLED] = nil
  vim.b[FINDROOT_DISABLED] = nil

  local status, parent_dir = get_parent_directory()

  if not parent_dir then
    if response then
      util.notify('Skipped while getting buffer', HEADER, 3, false)
    end

    return 'startup'
  end

  if (status ~= 'differ') and (status ~= 'same') then
    if response then
      local msg = string.format('Skipped %s path', status)
      util.notify(msg, HEADER, 3, false)
    end

    return status
  end

  local workspace = detect_project_root(parent_dir):gsub('/$', '')
  local pwd = util.pwd()

  if workspace ~= nil then
    if workspace == pwd then
      if response then
        util.notify('Skipped pointing to same path', HEADER, 3, false)
      end

      vim.api.nvim_exec_autocmds('User', {
        group = 'mug',
        pattern = 'MugRefreshBar',
      })

      return 'same'
    end

    parent_dir = workspace
  end

  --[[
  -- NOTE: When using ":[t|l]cd" to change the current directory,
  -- autocmd/DirChangedPre will execute "detect_project_root()", but it has
  -- already been executed once, so we need to prevent double execution
  ]]
  skip_event = true
  vim.cmd('silent! lcd ' .. parent_dir)
  -- vim.cmd.lcd(parent_dir)
  vim.api.nvim_exec_autocmds('User', {
    group = 'mug',
    pattern = 'MugRefreshBar',
  })

  if response then
    local msg = string.format('Changed root %s', parent_dir)
    util.notify(msg, HEADER, 2, false)
  end

  vim.g[FINDROOT_DISABLED] = disable_global
  vim.b[FINDROOT_DISABLED] = disable_local

  return 'change'
end

---Correspondence when "cd" manually changed
vim.api.nvim_create_autocmd({ 'DirChangedPre' }, {
  group = 'mug',
  pattern = { 'global', 'tabpage', 'window' },
  callback = function()
    if skip_event then
      skip_event = false
      return
    end

    local path = util.conv_slash(vim.api.nvim_get_vvar('event').directory)
    detect_project_root(path)
    vim.api.nvim_exec_autocmds('User', {
      group = 'mug',
      pattern = 'MugRefreshBar',
    })
  end,
  desc = 'Detect project-root and set git-status',
})

return M
