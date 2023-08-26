--[[
-- This code based on the edita.vim(https://github.com/lambdalisue/edita.vim)
-- Under the MIT license
--]]

local server = vim.uv.os_getenv('NVIM_MUG_SERVER')

if _G.Mug and not server then
  return
end

local fn = vim.fn

if fn.exists('+shellslash') == 1 then
  vim.go.shellslash = true
end

local mode = server:find(':%d+$') and 'tcp' or 'pipe'
local server_ch = fn.sockconnect(mode, server, { rpc = true })
local args = fn.argv()
local filepath = #args ~= 0 and fn.fnamemodify(args[1], ':p') or ''
local client = fn.serverstart()
local cmdline = string.format('lua require("mug.rpc.client").open_buffer("%s", "%s")', filepath, client:gsub('\\', '/'))

vim.rpcrequest(server_ch, 'nvim_command', cmdline)

-- vim.api.nvim_create_augroup('mug_rpc', {})
-- vim.api.nvim_create_autocmd({ 'VimLeave' }, {
--   group = 'mug_rpc',
--   buffer = 0,
--   once = true,
--   callback = function()
--     if server_ch == vim.NIL or server_ch == nil then
--       print('[mug/debug] client channel: ' .. server_ch)
--       return
--     end

--     vim.rpcnotify(server_ch, 'nvim_command', 'qall')
--   end,
--   desc = 'Close rpc-buffer',
-- })

