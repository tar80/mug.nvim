---@class tbl
---@field positions table
---@field plugins table
---@field modules table
---@field options table
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
  'mug.patch',
  'mug.rebase',
  'mug.terminal',
  'mug.show',
  'mug.workspace',
}

M.options = {
  'float_winblend',
  'symbol_not_repository',
  'edit_command',
  'file_command',
  'write_command',
  'strftime',
  'commit_notation',
  'commit_gpg_sign',
  'conflict_begin',
  'conflict_anc',
  'conflict_sep',
  'conflict_end',
  'filewin_beacon',
  'filewin_indicates_position',
  'loclist_position',
  'loclist_disable_column',
  'diff_position',
  'index_add_key',
  'index_force_key',
  'index_reset_key',
  'index_clear_key',
  'index_inputbar',
  'index_commit',
  'index_auto_update',
  'remote_url',
  'commit_initial_msg',
  'show_command',
  'term_command',
  'term_height',
  'term_width',
  'term_shell',
  'term_position',
  'term_disable_columns',
  'term_nvim_pseudo',
  'term_nvim_opener',
  'patch_window_height',
}
return M
