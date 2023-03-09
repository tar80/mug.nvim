local util = require('mug.module.util')
local tbl = require('mug.module.table')
local float = require('mug.module.float')
local comp = require('mug.module.comp')

---@class term
local M = {}
local HEADER, NAMESPACE = 'mug/term', 'MugTerm'
local float_handle = 0

---@class Mug
---@filed term_shell string
---@field term_height number
---@field term_width number
_G.Mug._def('term_height', 1, true)
_G.Mug._def('term_width', 0.9, true)

local function launch_shell(callback)
  if not _G.Mug.term_shell then
    return callback()
  end

  local shell = vim.api.nvim_get_option('shell')
  vim.api.nvim_set_option('shell', _G.Mug.term_shell)
  local handle = callback()
  vim.api.nvim_set_option('shell', shell)

  return handle
end

local function create_term(pos, range, cmd)
  local bufnr
  range = range == 0 and '' or range
  cmd = table.concat(cmd, ' ')

  if pos == 'float' then
    local floatnr = launch_shell(function()
      return float.term({
        cmd = cmd,
        title = NAMESPACE,
        height = _G.Mug.term_height,
        width = _G.Mug.term_width,
        border = 'rounded',
      })
    end)
    bufnr, float_handle = floatnr.bufnr, floatnr.handle
  else
    bufnr = launch_shell(function()
      vim.api.nvim_command('silent ' .. pos .. range .. 'new')

      if cmd ~= '' then
        vim.fn.termopen(cmd, {
          on_exit = function()
            vim.api.nvim_command('quit')
          end,
        })
      else
        vim.api.nvim_command('terminal')
      end

      util.nofile(true, 'wipe', 'terminal')
      vim.api.nvim_command('set foldcolumn=0 signcolumn=no nonumber norelativenumber')

      return vim.api.nvim_get_current_buf()
    end)
  end

  vim.api.nvim_buf_set_option(0, 'filetype', 'terminal')
  vim.api.nvim_command('startinsert')

  return bufnr
end

local function get_args(...)
  local args = ...
  local pos = tbl.positions[args[1]]

  if not pos then
    pos = args[1] == 'float' and 'float' or ''
  end

  table.remove(args, 1)

  return pos, args
end

M.open = function(range, ...)
  local pos, cmd = get_args(...)
  local servername = vim.api.nvim_get_vvar('servername')
  local bufnr = create_term(pos, range, cmd)

  vim.api.nvim_buf_set_var(bufnr, 'mug_main_server', servername)
end

vim.api.nvim_create_user_command(NAMESPACE, function(opts)
  if float.focus(float_handle) then
    return
  end

  M.open(opts.range, opts.fargs)
  -- if opts.bang then end
end, {
  nargs = '*',
  -- bang = true,
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
