M = {}

local map = require('mug.module.map')
local patch = require('mug.patch')

M.additional_settings = function()
  ---Toggle spellcheck
  map.buf_set(true, 'n', '^', '<Cmd>setlocal spell!<CR>', 'Toggle spellcheck')

  ---Open diffchaced-window horizontally
  map.buf_set(true, 'n', 'gd', function()
    patch.open()
  end, 'Open diff-buffer horizontally')

  ---Open diffchaced-window vertically
  map.buf_set(true, 'n', 'gD', function()
    patch.open('right')
  end, 'Open diff-buffer horizontally')

  --Git Log
  map.buf_set(true, { 'n'}, 'gl', function ()
    vim.cmd('MugShow! git log -10 --oneline')
  end, 'Open MugShow! git log', true)

  ---Wipeout diffchaced-window
  map.buf_set(true, 'n', 'q', function()
    patch.close()
  end, 'Close patch buffer')

  ---Insert datetime
  map.buf_set(true, { 'n', 'i' }, '<F5>', function()
    local time = os.date(_G.Mug.strftime)
    vim.api.nvim_put({ time }, 'c', false, true)
  end, 'Insert DateTime')

  ---Append
  map.buf_set(true, 'n', '<F6>', function()
    local msg = vim.fn.systemlist({ 'git', 'log', '-1', '--oneline', '--format=%B' })
    vim.api.nvim_buf_set_text(0, 0, 0, 0, 0, msg)
  end, 'Expand head commit message')
end

return M
