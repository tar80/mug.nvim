local util = require('mug.module.util')
local tbl = require('mug.module.table')

---@class config
local M = {}
local HEADER = 'mug/config'

---Set the default settings for the Mug
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
  method('result_position', 'belowright', true)
  method(
    'result_log_format',
    {
      '--graph --date=short --format=%C(cyan)%h\\ %C(magenta)[%ad]\\ %C(reset)%s%C(auto)%d',
      '--graph --name-status --oneline --date=short --format=%C(yellow\\ reverse)%h%C(reset)\\ %C(magenta)[%ad]%C(cyan)%an\\ %C(green)%s%C(auto)%d -10',
    },
    true
  )

  if overwrite then
    if _G.Mug.show_command then
      method('show_command', 'MugShow', true)
    end

    if _G.Mug.term_command then
      method('term_command', 'MugTerm', true)
    end

    if _G.Mug.show_command then
      method('sub_command', 'Mug', true)
    end
  end
end

---Update settings
---@alias userspec table Optional user settings
---@param opts userspec
local function change_settings(opts)
  local option_name = tbl.options
  local unknown = {}

  for k, _ in pairs(opts) do
    if k == 'root_patterns' then
      _G.Mug._ow(k, util.tbl_merges({}, opts[k]))
    elseif k == 'ignore_filetypes' then
      _G.Mug._ow(k, util.tbl_merges(_G.Mug[k], opts[k]))
    elseif vim.tbl_contains(option_name, k) then
      opts[k] = (opts[k] ~= '') and opts[k] or nil
      _G.Mug._ow(k, opts[k])
    else
      table.insert(unknown, k)
    end
  end

  if #unknown > 0 then
    local msg = string.format('Invalid variable detected. %s', table.concat(unknown, ','))
    util.notify(msg, HEADER, 3)
  end

  vim.list_extend(tbl.log_options, _G.Mug.result_log_format)
end

---User customized settings
---@param opts userspec
function M.set_options(opts)
  if not opts then
    util.notify('Requires arguments', HEADER, 3)
    return
  end

  change_settings(opts)
end

---Initial settings
M.init = function()
  set_default(true)
end

---New instance
local function new()
  if _G.Mug.loglevel then
    return
  end

  set_default()
end

new()

return M
