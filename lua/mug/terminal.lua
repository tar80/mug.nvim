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
local stored_columns = vim.deepcopy(columns)
local discolumns = { foldcolumn = '0', signcolumn = 'no', number = false, relativenumber = false }

---@class Mug
---@field term_shell string Specifies the shell to use with MugTerm
---@field term_position string Specifies the position of the buffer
---@field term_disable_columns boolean All columns are disabled
---@field term_nvim_pseudo boolean Do not display new nvim instance on MugTerm
---@field term_nvim_opener string Specifies the position when opening a buffer from MugTerm
---@field term_height number
---@field term_width number
-- _G.Mug._def('term_shell', vim.api.nvim_get_option('shell'), true)
_G.Mug._def('term_position', 'top', true)
_G.Mug._def('term_disable_columns', false, true)
_G.Mug._def('term_nvim_pseudo', false, true)
_G.Mug._def('term_nvim_opener', 'tabnew', true)
_G.Mug._def('term_height', 1, true)
_G.Mug._def('term_width', 0.9, true)

---Update display columns
---@param display boolean Display columns
---@param overwrite? boolean Overwrite "stored_columns"
local function display_columns(display, overwrite)
  if not _G.Mug.term_disable_columns then
    return
  end

  local t = display and stored_columns or discolumns

  for k, v in pairs(t) do
    if overwrite then
      stored_columns[k] = vim.wo[k]
    elseif v ~= vim.wo[k] then
      vim.wo[k] = v
    end
  end
end

---Apply the MugTerm specification
---@param bufnr integer Terminal-bufffer number
local function on_attach(bufnr)
  local term_id_bufenter = vim.api.nvim_create_autocmd({ 'BufEnter' }, {
    group = 'mug',
    buffer = bufnr,
    callback = function()
      vim.cmd.startinsert()
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
      stored_columns = vim.deepcopy(columns)
    end,
    desc = 'Remove autocmd set in MugTerm',
  })
end

---Create new buffer
local function create_window(count, pos)
  if count == 0 then
    count = ''
  else
    count = pos:find('vertical', 1, true) and math.max(20, count) or math.max(3, count)
  end

  vim.cmd(string.format('silent %s%snew', pos, count))
end

---Create buffer of the MugTerm
---@param pos 'float'|'top'|'bottom'|'left'|'right' Position of the terminal buffer
---@param count integer Size of the terminal buffer
---@param cmd string[] Oneshot command to run in the terminal buffer
local function term_buffer(pos, count, cmd)
  local bufnr, handle
  local cmd_str = table.concat(cmd, ' ')

  if pos == 'float' then
    handle = float.term({
      cmd = cmd_str,
      title = NAMESPACE,
      height = _G.Mug.term_height,
      width = _G.Mug.term_width,
      border = 'rounded',
    }).handle
  else
    create_window(count, pos)
    util.termopen(cmd_str)
    util.nofile(true, 'wipe', 'terminal')
    display_columns(false)

    bufnr = vim.api.nvim_get_current_buf()
    handle = vim.api.nvim_get_current_win()

    on_attach(bufnr)
  end

  vim.api.nvim_set_option_value('filetype', 'terminal', { buf = 0 })
  vim.cmd('clearjumps|startinsert')

  return handle
end


---Expand command arguments
---@generic T table Table of the MugTerm args
---@param fargs T
---@return string # Location of the MugTerm
---@return T
local function get_args(fargs)
  ---@type string|nil
  local pos = positions[fargs[1]]

  if not pos then
    pos = positions[_G.Mug.term_position] or ''
  else
    table.remove(fargs, 1)
  end

  return pos, fargs
end

---Get the servername of the current instance
---@return string # servername
local function get_server()
  local s = vim.api.nvim_get_vvar('servername')

  if not s then
    s = vim.fn.serverstart()
  end

  return s
end

---Open MugTerm
---@param count integer Size of the terminal buffer
---@param bang boolean Has bang
---@param fargs table Table of the arguments
M.open = function(count, bang, fargs)
  if float.focus(term_handle) then
    return
  end

  local pos, cmd = get_args(fargs)
  local server = get_server()

  if bang or _G.Mug.term_nvim_pseudo then
    shell.set_env('NVIM_MUG_SERVER', server)
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

    if input > 1 and input == 2 then
      return comp.filter(a, l, { 'top', 'bottom', 'left', 'right', 'float' })
    end

    return {}
  end,
})

return M
