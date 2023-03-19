--[[
-- This code based on the edita.vim(https://github.com/lambdalisue/edita.vim)
-- Under the MIT license
--]]

local M = {}
local api = vim.api
local fn = vim.fn

M.post_setup_buffer = function(callback)
  M.post_load = function()
    callback()
  end
end

M.open_buffer = function(filepath, client)
  local opener = _G.Mug.term_nvim_opener or 'tabnew'
  filepath = fn.fnameescape(filepath)
  local cmdline = string.format('%s %s', opener, filepath)

  api.nvim_command(cmdline)
  api.nvim_command('clearjumps')
  api.nvim_buf_set_option(0, 'bufhidden', 'wipe')

  M.post_load()
  M.post_load = nil

  local bufnr = api.nvim_get_current_buf()
  local mode = client:find(':%d+$') and 'tcp' or 'pipe'
  local client_ch = fn.sockconnect(mode, client, { rpc = true })

  api.nvim_create_autocmd({ 'BufDelete' }, {
    group = 'mug',
    buffer = bufnr,
    once = true,
    callback = function()
      if client_ch == vim.NIL or client_ch == nil then
        print('[mug/debug] client channel: ' .. client_ch)
        return
      end

      vim.env.NVIM_LISSTEN_ADRESS = nil
      pcall(vim.rpcrequest, client_ch, 'nvim_command', 'qall')
    end,
    desc = 'Close rpc-client',
  })
end

return M
