---@class tbl
---@field positions table
---@filed plugins table
---@filed modules table
local M = {}

M.positions = {
  top = 'aboveleft ',
  bottom = 'belowright ',
  left = 'vertical aboveleft ',
  right = 'vertical belowright ',
}

M.plugins = {
  'commit',
  'conflict',
  'diff',
  'files',
  'index',
  'merge',
  'mkrepo',
  'rebase',
  'show',
  'terminal',
}

M.modules = {
  'mug',
  'mug.module.comp',
  'mug.module.extmark',
  'mug.module.float',
  'mug.module.highlight',
  'mug.module.job',
  'mug.module.map',
  'mug.module.shell',
  'mug.module.table',
  'mug.module.timer',
  'mug.module.util',
  'mug.branch',
  'mug.commit',
  'mug.config',
  'mug.conflict',
  'mug.diff',
  'mug.files',
  'mug.index',
  'mug.merge',
  'mug.mkrepo',
  'mug.rebase',
  'mug.terminal',
  'mug.show',
  'mug.workspace',
}

return M
