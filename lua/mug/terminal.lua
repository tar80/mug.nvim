local util = require('mug.module.util')
local tbl = require('mug.module.table')
local float = require('mug.module.float')
local comp = require('mug.module.comp')
local shell = require('mug.module.shell')

---@class term
---@field open function
local M = {}
local HEADER, NAMESPACE = 'mug/term', 'MugTerm'
local positions = util.tbl_merges(tbl.positions, { float = 'float' })
local term_handle = 0
local columns = { foldcolumn = vim.NIL, signcolumn = vim.NIL, number = vim.NIL, relativenumber = vim.NIL }
local store_columns = vim.deepcopy(columns)
local discolumns = {
  foldcolumn = '0',
  signcolumn = 'no',
  number = false,
  relativenumber = false,
}

---@class Mug
---@filed term_shell string Specifies the shell to use with MugTerm
---@field term_position string Specifies the position of the buffer
---@filed term_disable_columns All columns are disabled
---@filed term_nvim_pseudo boolean Do not display new nvim instance on MugTerm
---@filed term_nvim_opener string Specifies the position when opening a buffer from MugTerm
---@field term_height number
---@field term_width number
_G.Mug._def('term_shell', vim.api.nvim_get_option('shell'), true)
_G.Mug._def('term_position', 'top', true)
_G.Mug._def('term_disable_columns', false, true)
_G.Mug._def('term_nvim_pseudo', false, true)
_G.Mug._def('term_nvim_opener', 'tabnew', true)
_G.Mug._def('term_height', 1, true)
_G.Mug._def('term_width', 0.9, true)

---@param display boolean Has columns
---@param set? boolean Overwrite store_columns
local function display_columns(display, set)
  if not _G.Mug.term_disable_columns then
    return
  end

  local t = display and store_columns or discolumns
  local wo = vim.wo

  for k, v in pairs(t) do
    if set then
      store_columns[k] = wo[k]
    elseif v ~= wo[k] then
      wo[k] = v
    end
  end
end

---@param bufnr number Terminal-bufffer number
local function on_attach(bufnr)
  local term_id_bufenter = vim.api.nvim_create_autocmd({ 'BufEnter' }, {
    group = 'mug',
    buffer = bufnr,
    callback = function()
      vim.api.nvim_command('startinsert')
    end,
    desc = 'Each time you enter the buffer, you start in insert-mode',
  })
  local term_id_bufreadpre = vim.api.nvim_create_autocmd({ 'BufWinEnter' }, {
    group = 'mug',
    callback = function()
      display_columns(true)
    end,
    desc = 'Adjust information columns',
  })
  vim.api.nvim_create_autocmd({ 'BufWipeout' }, {
    group = 'mug',
    once = true,
    buffer = bufnr,
    callback = function()
      display_columns(true)
      vim.api.nvim_del_autocmd(term_id_bufenter)
      vim.api.nvim_del_autocmd(term_id_bufreadpre)
      term_handle = 0
      store_columns = vim.deepcopy(columns)
    end,
    desc = 'Remove autocmd set in MugTerm',
  })
end

local function create_window(count, pos)
  if count == 0 then
    count = ''
  else
    count = (pos == 'top' or pos == 'bottom') and math.max(3, count) or math.max(20, count)
  end

  vim.api.nvim_command('silent ' .. pos .. count .. 'new')
end

local function term_buffer(pos, count, cmd)
  local bufnr, handle
  cmd = table.concat(cmd, ' ')

  if pos == 'float' then
    handle = float.term({
      cmd = cmd,
      title = NAMESPACE,
      height = _G.Mug.term_height,
      width = _G.Mug.term_width,
      border = 'rounded',
    }).handle
  else
    create_window(count, pos)
    util.termopen(cmd)
    util.nofile(true, 'wipe', 'terminal')
    display_columns(false)

    bufnr = vim.api.nvim_get_current_buf()
    handle = vim.api.nvim_get_current_win()

    on_attach(bufnr)
  end

  vim.api.nvim_buf_set_option(0, 'filetype', 'terminal')
  vim.api.nvim_command('clearjumps|startinsert')

  return handle
end

local function get_args(fargs)
  local pos = positions[fargs[1]]

  if not pos then
    pos = positions[_G.Mug.term_position] or ''
  else
    table.remove(fargs, 1)
  end

  return pos, fargs
end

local function get_server()
  local s = vim.api.nvim_get_vvar('servername')

  if not s then
    s = vim.fn.serverstart()
  end

  return s
end

M.open = function(count, bang, fargs)
  if float.focus(term_handle) then
    return
  end

  local pos, cmd = get_args(fargs)
  local server = get_server()

  if bang or _G.Mug.term_nvim_pseudo then
    shell.set_env('NVIM_LISSTEN_ADRESS', server)
    shell.nvim_client('GIT_EDITOR')
  end

  display_columns(true, true)
  term_handle = term_buffer(pos, count, cmd)
end

util.user_command('term_command', function(opts)
  M.open(opts.count, opts.bang, opts.fargs)
end, {
  nargs = '*',
  bang = true,
  count = true,
  complete = function(a, l, _)
    local input = #vim.split(l, ' ', { plain = true })

    if input > 1 then
      return input == 2 and comp.filter(a, l, { 'top', 'bottom', 'left', 'right', 'float' }) or {}
    else
      return {}
    end
  end,
})

return M
