local util = require('mug.module.util')
local job = require('mug.module.job')
local comp = require('mug.module.comp')
local hl = require('mug.module.highlight')
local tbl = require('mug.module.table')

---@class Mug
---@field root string Mug.nvim own installation directory path
---@field root_patterns table Findroot project root patterns
---@field ignore_filetypes table Findroot skipped filetypes
---@field loglevel number Log-level of last notify
---@field edit_command string Name the Edit command
---@field file_command string Name the File command
---@field write_command string Name the Write command
require('mug.module.protect')

local M = {}
local HEADER = 'mug'
local FINDROOT_DISABLED = 'mug_findroot_disable'

---Set the Mug install direcotry path to _G.Mug.root
do
  local rtp = vim.api.nvim_list_runtime_paths()

  for _, v in pairs(rtp) do
    if v:match('.*[/|\\]mug.nvim') then
      _G.Mug._def('root', v, true)
    end
  end
end

---Run "git add" on current file
---@param force boolean Force staging
local function git_add(force)
  local path = util.filepath('/', true)

  if not path then
    return
  end

  vim.api.nvim_command('silent update')

  if not vim.b.mug_branch_name then
    util.notify('Cannot get branch', HEADER, 3, false)
    return
  end

  if force then
    local ok = util.interactive('Force stage to current file?', HEADER, 'y')

    if not ok then
      return
    end
  end

  job.async(function()
    local option = force and '-fv' or '-v'
    local cmd = util.gitcmd({ cmd = 'add', opts = { option, path } })
    local result, err = job.await(cmd)

    if vim.tbl_isempty(result) then
      result = { 'No changes' }
    end

    require('mug.branch').branch_stats(util.pwd(), false)
    util.notify(result, HEADER, err, false)
  end)
end

local function mug_variables(options)
  if options.show then
    _G.Mug._def('show_command', 'MugShow', true)
  end

  if options.terminal then
    _G.Mug._def('term_command', 'MugTerm', true)
  end

  require('mug.config').set_options(options.variables)

  for _, v in ipairs(tbl.plugins) do
    if options[v] then
      require('mug.' .. v)
    end
  end
end

local function mug_commands()
  ---":Write"
  ---Update and "git add" the file being edited
  util.user_command('write_command', function(opts)
    git_add(opts.bang)
  end, { bang = true })

  ---":Edit [<filename>]"
  ---Edit a file based on the parent directory
  util.user_command('edit_command', function(opts)
    local bang = opts.bang and '! ' or ' '
    local slash = util.slash()
    local parent = util.dirpath()
    local path = opts.args ~= '' and util.normalize(parent .. slash .. opts.args, slash) or ''

    vim.api.nvim_command('edit' .. bang .. path)
  end, {
    nargs = '?',
    bang = 1,
    complete = function(a, l, _)
      local parent = util.dirpath('/')
      return comp.filter(a, l, comp.files(parent))
    end,
  })

  ---":File <filename>"
  ---Rename edited file based on the parent directory
  util.user_command('file_command', function(opts)
    local bang = opts.bang and '! ' or ' '
    local slash = util.slash()
    local parent = util.dirpath()
    local path = util.normalize(parent .. slash .. opts.args, slash)

    vim.api.nvim_command('file' .. bang .. path)
  end, {
    nargs = 1,
    bang = 1,
  })
end

local function mug_highlights(options)
  local items = options.highlights or nil

  hl.customize(items)
  hl.lazy_load(hl.init)
end

---Autogroup "mug"
vim.api.nvim_create_augroup('mug', {})
local set_ws_root = require('mug.workspace').set_workspace_root

---Setup highlights
vim.api.nvim_create_autocmd('ColorScheme', {
  group = 'mug',
  pattern = '*',
  callback = function()
    hl.init()
  end,
  desc = 'Setup mug highlights',
})

---Run "findroot"
vim.api.nvim_create_autocmd({ 'BufEnter' }, {
  group = 'mug',
  callback = function()
    if vim.b[FINDROOT_DISABLED] or vim.g[FINDROOT_DISABLED] then
      return
    end

    if vim.api.nvim_get_option('autochdir') then
      vim.api.nvim_set_option('autochdir', false)
    end

    ---Delay to accommodate user set buftype
    local timer = vim.uv.new_timer()
    timer:start(
      100,
      0,
      vim.schedule_wrap(function()
        set_ws_root(false)
      end)
    )
  end,
  desc = 'Detect project-root and set current-directory',
})

---":MugFindroot"
---Detect project-root of current buffer
vim.api.nvim_create_user_command('MugFindroot', function(opts)
  if opts.args == 'stopbuffer' then
    vim.api.nvim_buf_set_var(0, FINDROOT_DISABLED, true)
  elseif opts.args == 'stopglobal' then
    vim.api.nvim_set_var(FINDROOT_DISABLED, true)
  else
    set_ws_root(true)
  end
end, {
  nargs = '?',
  complete = function(a, l, _)
    return comp.filter(a, l, { 'stopbuffer', 'stopglobal' })
  end,
})

---@param options table Overwrite plugin general settings
function M.setup(options)
  mug_variables(options)
  mug_commands()
  mug_highlights(options)

  if not (vim.b.mug_branch_name or vim.g[FINDROOT_DISABLED] or vim.b[FINDROOT_DISABLED]) then
    vim.api.nvim_command('doautocmd mug BufEnter')
  end

  -- vim.g.loaded_mug = true
end

function M.reload()
  for _, v in ipairs(tbl.modules) do
    if package.loaded[v] then
      package.loaded[v] = nil
      require(v)
    end
  end

  util.notify('Reload modules.', HEADER, 3)
end

return M
