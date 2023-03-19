local util = require('mug.module.util')

---@class shell
---@field set_env fun(name: string, value: any) Set environment variable in the shell
---@field nvim_client fun(env: string) Set environment variable <client_editor> in the shell
local M = {}

---@param name string Name of environment
local function unset_env(name)
  vim.api.nvim_create_autocmd('TermOpen', {
    group = 'mug',
    once = true,
    callback = function()
      vim.fn.setenv(name, nil)
    end,
    desc = 'Remove temporary environment variables',
  })
end

local function opt_shellesc(option, value)
  return option .. ' ' .. vim.fn.shellescape(value)
end

---@param name string Name of environment
---@param value any Value of environment
M.set_env = function(name, value)
  local v = type(value) == 'table' and table.concat(value, ' ') or value
  vim.fn.setenv(name, v)
  unset_env(name)
end

---@param env string Specify environment variables to set
M.nvim_client = function(env)
  local nvim_path = util.conv_slash(vim.v.progpath)
  local mug_path = util.conv_slash(_G.Mug.root)
  local script_path = mug_path .. '/lua/mug/rpc/_bootstrap.lua'
  local cmdline = {
    vim.fn.shellescape(nvim_path),
    '--headless',
    '--clean',
    '--noplugin',
    '-n',
    '-R',
    opt_shellesc('-c', 'set runtimepath^=' .. mug_path),
    opt_shellesc('-S', script_path),
  }

  M.set_env(env, table.concat(cmdline, ' '))
end

return M
