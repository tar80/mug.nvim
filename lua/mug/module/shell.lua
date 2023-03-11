local util = require('mug.module.util')

---@class shell
local M = {}
local fn = vim.fn

local function unset_env(name)
  vim.api.nvim_create_autocmd('TermOpen', {
    group = 'mug',
    once = true,
    callback = function()
      fn.setenv(name, nil)
    end,
  })
end

local function opt_shellesc(option, value)
  return option .. ' ' .. fn.shellescape(value)
end

M.set_env = function(name, value)
  local v = type(value) == 'table' and table.concat(value, ' ') or value
  fn.setenv(name, v)
  unset_env(name)
end

M.nvim_client = function()
  local nvim_path = util.conv_slash(vim.v.progpath)
  local mug_path = util.conv_slash(_G.Mug.root)
  local script_path = mug_path .. '/lua/mug/rpc/_bootstrap.lua'
  local cmdline = {
    fn.shellescape(nvim_path),
    '--headless',
    '--clean',
    '--noplugin',
    '-n',
    '-R',
    opt_shellesc('-c', 'set runtimepath^=' .. mug_path),
    opt_shellesc('-S', script_path),
  }

  M.set_env('GIT_EDITOR', table.concat(cmdline, ' '))
end

return M
