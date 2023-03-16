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
    'strftime',
    'remote_url',
    'float_winblend',
    'edit_command',
    'file_command',
    'write_command',
    'commit_diffcached_height',
    'commit_initial_msg',
    'commit_notation',
    'commit_gpg_sign',
    'conflict_begin',
    'conflict_anc',
    'conflict_sep',
    'conflict_end',
    'diff_position',
    'loclist_position',
    'loclist_disable_column',
    'filewin_beacon',
    'filewin_indicates_position',
    'index_add_key',
    'index_force_key',
    'index_reset_key',
    'index_clear_key',
    'index_inputbar',
    'index_commit',
    'show_command',
    'term_command',
    'term_shell',
    'term_disable_columns',
    'term_position',
    'term_nvim_opener',
    'term_nvim_pseudo',
    'term_height',
    'term_width',
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
