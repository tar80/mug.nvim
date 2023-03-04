local util = require('mug.module.util')

---@class config
---@field set_options function User changes settings
---@field init function Initial settings
local M = {}
local HEADER = 'mug/config'

---Mug default settings
---@param overwrite? boolean
local function set_default(overwrite)
  local method = overwrite and '_ow' or '_def'

  _G.Mug[method]('root_patterns', { '.git/', '.gitignore' })
  _G.Mug[method]('ignore_filetypes', { 'git', 'gitcommit', 'gitrebase' })
  _G.Mug[method]('loglevel', 0)
  _G.Mug[method]('edit_command', 'Edit', true)
  _G.Mug[method]('file_command', 'File', true)
  _G.Mug[method]('write_command', 'Write', true)
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
    'conflict_begin',
    'conflict_anc',
    'conflict_sep',
    'conflict_end',
    'diff_position',
    'loclist_position',
    'loclist_disable_column',
    'filewin_indicates_position',
    'index_add_key',
    'index_force_key',
    'index_reset_key',
    'index_clear_key',
    'index_inputbar',
    'index_commit'
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

M.init = function ()
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
