--[[
-- This code based on the vim-findroot(https://github.com/mattn/vim-findroot)
-- Under the MIT license
--]]

local util = require('mug.module.util')
local branch_name = require('mug.branch').branch_name

---@class ws
---@field set_workspace_root function
local M = {}
local HEADER = 'mug/findroot'
local FINDROOT_DISABLED = 'mug_findroot_disable'
local skip_event

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
  local path = util.pwd('parent')
  local status = compare_wd(path)
  local buftype = vim.api.nvim_buf_get_option(0, 'buftype')

  if path == '.' then
    return nil, nil
  end

  if buftype ~= '' or path:match('^%w+://') ~= nil then
    return 'special', path
  end

  local buf_ft = vim.api.nvim_buf_get_option(0, 'filetype')
  local ignore_ft = _G.Mug.ignore_filetypes

  if vim.tbl_contains(ignore_ft, buf_ft) then
    return 'ignore', path
  end

  return status, path
end

---@param marker string Git repository root marker
---@param path string Detected path
local function query_branch_is(marker, path)
  if marker:find('.git', 1, true) then
    branch_name(path)
  end
end

---@param path string Path to be detected
---@return string? # Project root path
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
        match_path = dir .. '/' .. v

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
  local ref = ''

  repeat
    local stat, ret, root, pattern = coroutine.resume(co, root_patterns, path)

    if stat then
      root_patterns = { unpack(root_patterns, 1, ret - 1) }
      path = root
      ref = pattern
    end
  until coroutine.status(co) == 'dead'

  query_branch_is(ref, path)

  return path
end

---@param response? boolean show result message
---@return string # Result of comparing parent directories
M.set_workspace_root = function(response)
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

  if status ~= 'differ' and status ~= 'same' then
    if response then
      util.notify('Skipped the ' .. status .. ' path', HEADER, 3, false)
    end

    return status
  end

  local workspace = detect_project_root(parent_dir)

  if workspace ~= nil then
    if workspace == util.pwd() then
      if response then
        util.notify('Skipped pointing to the same path', HEADER, 3, false)
      end

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
  vim.api.nvim_command('silent lcd ' .. parent_dir)

  if response then
    util.notify('Changed root ' .. parent_dir, HEADER, 2, false)
  end

  return 'change'
end

---Correspondence when "cd" manually changed
vim.api.nvim_create_autocmd({ 'DirChangedPre' }, {
  group = 'mug',
  pattern = { 'global', 'tabpage', 'window' },
  callback = function()
    if skip_event then
      skip_event = nil
      return
    end

    local path = util.normalize(vim.api.nvim_get_vvar('event').directory, '/')
    detect_project_root(path)
  end,
  desc = 'Detect project-root and set git-status',
})

return M
