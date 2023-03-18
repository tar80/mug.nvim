M = {}

M.abbrev = {
  bu = 'Build',
  bue = ':package:Build',
  cie = ':construction_worker:CI',
  ds = 'Docs',
  dse = ':book:Docs',
  fi = 'Fix',
  fie = ':bug:Fix',
  ic = 'Initial commit',
  ice = ':tada:Initial commit',
  pe = 'Perf',
  pee = ':rocket:Perf',
  rf = 'Refactor',
  rfe = ':hammer:Refactor',
  sy = 'Style',
  sye = ':art:Style',
  te = 'Test',
  tee = ':rotating_light:Test',
  ud = 'Update',
  ude = ':sparkles:Update',
  ad = ' Add',
  ade = ':truck:Add',
  mo = ' Move',
  moe = ':truck:Move',
  rn = ' Rename',
  rne = ':truck:Rename',
  de = 'Delete',
  dee = ':fire:Delete',
  bg = 'BREAKING CHANGE:',
  rr = 'Refs:',
}

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
