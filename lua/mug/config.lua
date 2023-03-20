local util = require('mug.module.util')

---@class config
---@field set_options function User changes settings
---@field init function Initial settings
local M = {}
local HEADER = 'mug/config'

---Mug default settings
---@param overwrite? boolean
local function set_default(overwrite)
  local method = overwrite and _G.Mug._ow or _G.Mug._def

  method('root_patterns', { '.git/', '.gitignore' })
  method('ignore_filetypes', { 'git', 'gitcommit', 'gitrebase' })
  method('symbol_not_repository', '---')
  method('loglevel', 0)
  method('edit_command', 'Edit', true)
  method('file_command', 'File', true)
  method('write_command', 'Write', true)

  if _G.Mug.show_command then
    method('show_command', 'MugShow', true)
  end

  if _G.Mug.term_command then
    method('term_command', 'MugTerm', true)
  end
end

---@alias userspec table Optional user settings

---@param opts userspec
local function change_settings(opts)
  local strings = {
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
  local unknown = {}

  for k, _ in pairs(opts) do
    if k == 'root_patterns' then
      _G.Mug._ow(k, util.tbl_merges({}, opts[k]))
    elseif k == 'ignore_filetypes' then
      _G.Mug._ow(k, util.tbl_merges(_G.Mug[k], opts[k]))
    elseif vim.tbl_contains(strings, k) then
      opts[k] = opts[k] ~= '' and opts[k] or nil
      _G.Mug._ow(k, opts[k])
    else
      table.insert(unknown, k)
    end
  end

  if #unknown > 0 then
    util.notify('Invalid variable detected. ' .. table.concat(unknown, ','), HEADER, 3)
  end
end

---@param opts userspec
function M.set_options(opts)
  if not opts then
    util.notify('Requires arguments', HEADER, 3)
    return
  end

  change_settings(opts)
end

M.init = function()
  set_default(true)
end

local function new()
  if _G.Mug.loglevel then
    return
  end

  set_default()
end

new()

return M
