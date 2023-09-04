local util = require('mug.module.util')
local job = require('mug.module.job')
local map = require('mug.module.map')
local tbl = require('mug.module.table')
local syntax_stats = require('mug.module.syntax').stats

local M = {}
local HEADER = 'mug/patch'
local PATCH_URI = 'Mug://patch'

---@type table {bufnr: integer, winid: integer}
local preview_window = {}

---@class Mug
---@field patch_window_height number
_G.Mug._def('patch_window_height', 20, true)

---Post-processing when deleting the pleview window
---@param bufnr integer ID of the preview window
local function post_process(bufnr)
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = 'mug',
    buffer = bufnr,
    callback = function()
      preview_window = {}
    end,
    desc = 'Processing when the preview-window is deleted',
  })
end

---Add keymaps to the MugCommit buffer
local function maps_commit()
  map.buf_set(true, 'n', 'q', function()
    vim.api.nvim_set_option_value('buflisted', false, { buf = 0 })
    vim.cmd.bwipeout()
    -- vim.cmd('silent bwipeout')
  end, 'Close patch buffer')

  vim.api.nvim_command('wincmd p')
end

---Set keymaps to the preview window
local function maps_cached()
  map.buf_set(true, 'n', 'q', function()
    vim.api.nvim_set_option_value('buflisted', false, { buf = 0 })
    vim.cmd.bwipeout()
    -- vim.cmd('silent bwipeout')
  end, 'Close patch buffer')
  map.buf_set(true, 'n', { 'gd', 'gD' }, function()
    M.open()
  end, 'Toggle patch buffer')
end

---Get the width of the current column
local function column_width()
  local width = vim.api.nvim_get_option_value('signcolumn', { win = 0 }) == 'yes' and 2 or 0
  local numwidth = 0
  width = width + tonumber(vim.api.nvim_get_option_value('foldcolumn', { win = 0 }))

  if
    vim.api.nvim_get_option_value('number', { win = 0 })
    or vim.api.nvim_get_option_value('relativenumber', { win = 0 })
  then
    numwidth = math.max(3, tonumber(vim.api.nvim_get_option_value('numberwidth', { win = 0 })))
    width = width + numwidth
  end

  return width, numwidth
end

---@alias Preview_arguments {excmd: string, direction: string, width: integer, height?: integer, method: string }

---Get contents of the preview window
---@param commitish string
---@param args Preview_arguments
---@param numwidth integer
---@param hash string
---@return table stdout, integer loglevel
local function get_patch(commitish, args, numwidth, hash)
  local opts = {
    '--cached',
    '--patch',
    '--no-color',
    '--no-ext-diff',
    '--compact-summary',
    string.format('--stat=%s', args.width - numwidth),
    hash,
  }
  local cmd

  if commitish == 'commit' then
    cmd = 'show'
    table.remove(opts, 1)
  else
    cmd = 'diff'
  end

  return job.await(util.gitcmd({ noquotepath = true, cmd = cmd, opts = opts }))
end

---Get startup arguments of the preview window
---@param commitish string Command mode
---@param position string Buffer position
---@param infowidth integer Left column width
---@return Preview_arguments
local function buffer_info(commitish, position, infowidth)
  local width = vim.api.nvim_win_get_width(0)
  local margin = commitish == 'commit' and 60 or 73

  return position:find('vertical', 1, true)
      and {
        direction = position,
        excmd = 'vnew',
        width = math.max(1, width - margin - infowidth),
        method = 'nvim_win_set_width',
      }
    or {
      direction = position,
      excmd = 'new',
      width = width - infowidth,
      height = _G.Mug.patch_window_height,
      method = 'nvim_win_set_height',
    }
end

---Expand commit contents to the preview window
---@param treeish string Specified the commit
---@return boolean # Whether the buffer is loaded
local function expand_preview_contents(treeish)
  if preview_window[treeish] then
    local v = preview_window[treeish]

    if pcall(vim.api.nvim_win_get_option, v[2], 'previewwindow') then
      vim.api.nvim_buf_set_lines(v[1], 0, -1, false, v[3])
    end

    return true
  else
    for _, v in pairs(preview_window) do
      if pcall(vim.api.nvim_win_get_option, v[2], 'previewwindow') then
        vim.api.nvim_buf_set_lines(v[1], 0, -1, false, v[3])
      end
    end
  end

  return false
end

---Toggle preview window
---@param treeish string Specified commit
---@param args Preview_arguments
---@return boolean # Whether the buffer is loaded
local function cached_loaded(treeish, args)
  local bufnr, winid

  if preview_window[treeish] then
    bufnr, winid = unpack(preview_window[treeish])

    if pcall(vim.api.nvim_win_get_option, winid, 'previewwindow') then
      vim.cmd.pclose()
    else
      vim.cmd(string.format('silent %s sbuffer %s', args.direction, bufnr))
      winid = vim.api.nvim_get_current_win()
      preview_window[treeish][2] = winid

      vim.api.nvim_set_option_value('previewwindow', true, { win = winid })

      if args.method then
        local range = args.height or args.width
        vim.api[args.method](0, range)
      end
    end
    return true
  end

  return false
end

---Expand patch contents in preview window
---@param commitish string
---@param treeish string
---@param bufinfo table
---@param filename string
---@param stdout table
local function patch_buffer(commitish, treeish, bufinfo, filename, stdout)
  local bufnr, winid

  if vim.tbl_isempty(preview_window) then
    bufnr = vim.api.nvim_create_buf(true, true)
    local range = bufinfo.height or bufinfo.width
    local maps = commitish == 'commit' and maps_commit or maps_cached

    vim.api.nvim_buf_set_name(bufnr, filename)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, stdout)
    vim.cmd(string.format('silent %s %s %s %s', bufinfo.direction, range, bufinfo.excmd, filename))
    vim.cmd('clearjumps|setfiletype git')

    winid = vim.api.nvim_get_current_win()

    vim.api.nvim_set_option_value('previewwindow', true, { win = winid })
    vim.api.nvim_set_option_value('foldcolumn', '0', { win = winid })
    vim.api.nvim_set_option_value('signcolumn', 'no', { win = winid })
    vim.api.nvim_set_option_value('number', false, { win = winid })
    util.nofile(true, 'hide', 'nofile')
    syntax_stats()
    maps()
    post_process(bufnr)
  else
    for _, v in pairs(preview_window) do
      if pcall(vim.api.nvim_win_get_option, v[2], 'previewwindow') then
        bufnr, winid = v[1], v[2]
      end
    end

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, stdout)
  end

  preview_window[treeish] = commitish == 'commit' and { bufnr, winid, stdout } or { bufnr, winid }

  if vim.tbl_count(preview_window) > 5 then
    table.remove(preview_window, 1)
  end
end

---Show git diff with staged-files
---@param position? string|nil Specify how to open the buffer. `top` `bottom` `left` `right`
---@param hash? string Specify tree-ish
M.open = function(position, hash)
  local commitish = hash and 'commit' or 'cached'
  local treeish = hash or util.pwd()
  local filename = string.format('%s/%s', PATCH_URI, commitish)
  hash = hash or ''
  position = tbl.positions[string.lower(position or 'bottom')]
  local colwidth, numwidth = column_width()
  local bufinfo = buffer_info(commitish, position, colwidth)
  local loaded_buffer = commitish == 'commit' and expand_preview_contents or cached_loaded
  local loaded = loaded_buffer(treeish, bufinfo)

  if loaded then
    return
  end

  job.async(function()
    local stdout, err = get_patch(commitish, bufinfo, numwidth, hash)

    if err > 3 then
      util.notify(stdout, HEADER, err)
      return
    end

    if commitish == 'cached' and #stdout == 0 then
      util.notify('No difference', HEADER, err)
      return
    end

    patch_buffer(commitish, treeish, bufinfo, filename, stdout)
  end)
end

---Close the preview window
M.close = function()
  for _, v in pairs(preview_window) do
    if pcall(vim.api.nvim_win_get_option, v[2], 'previewwindow') then
      vim.cmd.bwipeout(v[1])
    end
  end
end

return M
