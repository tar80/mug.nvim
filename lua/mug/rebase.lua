local util = require('mug.module.util')
local float = require('mug.module.float')
local extmark = require('mug.module.extmark')
local hl = require('mug.module.highlight')
local map = require('mug.module.map')
local comp = require('mug.module.comp')
local shell = require('mug.module.shell')
local branch = require('mug.branch')
local patch = require('mug.patch')
local job = require('mug.module.job')
local syntax = require('mug.module.syntax')
local tbl = require('mug.module.table')

---@module "rebase"
local M = {}
local HEADER, NAMESPACE = 'mug/rebase', 'MugRebase'
local float_handle = 0
local item_count = 1
local select_item = {}
---@type integer
local ns_select = vim.api.nvim_create_namespace(NAMESPACE)

---@type function|nil User additional keymaps for rebase buffer
local addinional_maps
local comp_on_process = { '--abort', '--continue', '--edit-todo', '--quit', '--skip', '--show-current-patch' }

---@class Mug
---@field rebase_log_format string
---@field rebase_fixup_key string
---@field rebase_squash_key string
---@field rebase_clear_key string
---@field rebase_preview_pos string
---@field rebase_preview_subpos string
_G.Mug._def('rebase_log_format', '%as <%cn> %d%s', true)
_G.Mug._def('rebase_fixup_key', 'f', true)
_G.Mug._def('rebase_squash_key', 's', true)
_G.Mug._def('rebase_clear_key', 'c', true)
_G.Mug._def('rebase_preview_pos', 'bottom', true)
_G.Mug._def('rebase_preview_subpos', 'right', true)

hl.late_record(function()
  local hlname = vim.fn.hlexists('NormalFloat') == 1 and 'NormalFloat' or 'Normal'
  hl.set_hl('MugRebaseFixup', { ns = 0, hl = { bg = hl.shade(0, hlname, 0, 10, 5) } })
  hl.set_hl('MugRebaseSquash', { ns = 0, hl = { bg = hl.shade(0, hlname, 0, 5, 30) } })
end)

hl.record('MugLogHash', { ns = 0, hl = { link = 'Special' } })
hl.record('MugLogDate', { ns = 0, hl = { link = 'Statement' } })
hl.record('MugLogOwner', { ns = 0, hl = { link = 'Conditional' } })
hl.record('MugLogHead', { ns = 0, hl = { link = 'Keyword' } })

local select_hl = { squash = 'MugRebaseSquash', fixup = 'MugRebaseFixup' }

---Make a confirm and get the result
---@param msg string
---@return boolean # Whether to continue
local function ask_continue(msg)
  local answer = util.confirm(msg, 'Yes\nNo', 1, HEADER)
  return answer == 1
end

---Get ID of the preview window
---@return integer # Preview window id
local function preview_winid()
  local winlist = vim.api.nvim_list_wins()

  for _, v in ipairs(winlist) do
    if vim.api.nvim_get_option_value('previewwindow', { win = v }) then
      return v
    end
  end

  return 0
end

---Open preview window
---@param direction? string Direction to open the preview-window
local function open_preview(direction)
  direction = direction or _G.Mug.rebase_preview_pos

  local hash, ok = vim.api.nvim_get_current_line():gsub('^%a+%s(%w+)%s.*', '%1')

  if ok == 1 then
    patch.open(direction, hash)
  end
end

---Send keystrokes to the preview window
---@param key string Send key
---@param winid integer ID of the preview window
local function sendkey_preview(key, winid)
  if not winid then
    winid = preview_winid()
  end

  if winid == 0 then
    return
  end

  vim.api.nvim_win_call(winid, function()
    vim.cmd.normal(key)
    -- vim.api.nvim_command(string.format('exe "normal %s"', key))
  end)
end

---Remove MugRebase specification
---@param bufnr integer Buffer number to detach
local function on_detach(bufnr)
  vim.api.nvim_create_autocmd({ 'BufWipeout' }, {
    group = 'mug',
    buffer = bufnr,
    once = true,
    callback = function()
      patch.close()
    end,
    desc = 'Detach rebase client buffer',
  })
end
---Set keymaps to the client server
local function map_to_server()
  require('mug.rpc.client').post_setup_buffer(function()
    local bufnr = vim.api.nvim_win_get_buf(0)
    local syncview = false
    ---@type integer
    local winid

    on_detach(bufnr)

    map.buf_set(true, 'n', '<C-d>', function()
      sendkey_preview('\\<C-d>', winid)
    end, 'Page half down on preview-window')
    map.buf_set(true, 'n', '<C-u>', function()
      sendkey_preview('\\<C-u>', winid)
    end, 'Page half up on preview-window')
    map.buf_set(true, 'n', '<C-j>', function()
      sendkey_preview('j', winid)
    end, 'Cursor down on filewin')
    map.buf_set(true, 'n', '<C-k>', function()
      sendkey_preview('k', winid)
    end, 'Cursor up on filewin')
    map.buf_set(true, 'n', '^', function()
      syncview = not syncview
      util.notify('Syncview ' .. tostring(syncview), HEADER, 2)
    end, 'Toggle syncview')
    map.buf_set(true, 'n', 'j', function()
      vim.cmd.normal({ 'j', bang = true })

      if syncview then
        open_preview()
      end
    end, 'Sync preview down')
    map.buf_set(true, 'n', 'k', function()
      vim.cmd.normal({ 'k', bang = true })

      if syncview then
        open_preview()
      end
    end, 'Sync preview up')
    map.buf_set(true, 'n', 'gd', function()
      open_preview()
      syncview = true
    end, 'Open preview-window')
    map.buf_set(true, 'n', 'gD', function()
      open_preview(_G.Mug.rebase_preview_subpos)
      syncview = true
    end, 'Open preview-window')
    map.buf_set(true, 'n', 'q', function()
      patch.close()
      syncview = false
    end, 'Close preview-window')

    if addinional_maps then
      addinional_maps(winid, syncview)
    end
  end)
end

---Open rebase buffer
local function rebase_buffer(selected, options, hash_rb)
  local server = shell.get_server()

  shell.set_env('NVIM_MUG_SERVER', server)
  shell.nvim_client('GIT_SEQUENCE_EDITOR')
  map_to_server()
  job.async(function()
    local squash = selected and '--autosquash' or ''
    local cmdline = util.gitcmd({ noquotepath = true, cmd = 'rebase', opts = { squash, options, hash_rb } })
    local ok, stdout = job.await(cmdline)

    if not ok then
      util.notify(stdout, HEADER, 3, true)
      return
    end
  end)
end

---Set extmark to current line
---@param target string Autosquash type. `"squash"` or `"fixup"`
local function select_this(target)
  local row = vim.api.nvim_win_get_cursor(0)[1]

  if row == item_count then
    return
  end

  for _, v in ipairs(select_item) do
    if v.line_num ~= row or v.hl_group ~= select_hl[target] then
      select_item = {}
      vim.api.nvim_buf_clear_namespace(0, ns_select, 0, -1)
      break
    end
  end

  extmark.select_line(row, 0, ns_select, select_item, select_hl[target])
end

---Open rebase buffer with the commit pointed to by the current line as the starting point
---@param options table Git rebase options
local function rebase_this(options)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local selected = not vim.tbl_isempty(select_item)
  local hash_rb = vim.api.nvim_get_current_line():sub(1, 7)

  if not selected then
    if not ask_continue('Is it okay to rebase on ' .. hash_rb) then
      return
    end
  else
    local select = select_item[1].line_num
    local hash_as = select_item[1].contents:sub(1, 7)
    local mode = select_item[1].hl_group:sub(#NAMESPACE + 1)

    if row <= select then
      return
    end

    if not ask_continue(string.format('Create commit "%s! %s" and run rebase -i?', mode, hash_as)) then
      select_item = {}
      vim.api.nvim_buf_clear_namespace(0, ns_select, 0, -1)
      return
    end

    mode = string.format('--%s=%s', mode:lower(), hash_as)
    local log = vim.fn.systemlist({ 'git', 'commit', '--no-edit', mode })

    if vim.v.shell_error == 1 then
      util.notify(log, HEADER, 3)
      return
    end
  end

  rebase_buffer(selected, options, hash_rb)
  vim.api.nvim_win_close(0, {})
end

local function float_win_map(staged, options)
  map.buf_set(true, 'n', _G.Mug.rebase_squash_key, function()
    if staged > 0 then
      select_this('squash')
    end
  end, 'Squash on cursor line')

  map.buf_set(true, 'n', _G.Mug.rebase_fixup_key, function()
    if staged > 0 then
      select_this('fixup')
    end
  end, 'Fixup on cursor line')

  map.buf_set(true, 'n', '<CR>', function()
    rebase_this(options)
  end, 'Rebase on cursor line')

  map.buf_set(true, 'n', _G.Mug.rebase_clear_key, function()
    select_item = {}
    vim.api.nvim_buf_clear_namespace(0, ns_select, 0, -1)
  end, 'Clear select line')
end

---Set keymaps to the floating window
---@param stdout string[] git log stdout
---@param stats table worktree state
---@param options table command arguments
local function float_win(stdout, stats, options)
  local name = vim.b.mug_branch_name
  local staged = stats.s

  float_handle = float.open({
    title = string.format('%s interactive', NAMESPACE),
    height = 3,
    width = 0.4,
    border = 'rounded',
    contents = function()
      return stdout
    end,
    post = function()
      vim.api.nvim_set_option_value('modifiable', false, { buf = 0 })
      syntax.log()
      syntax.rebase()
      float_win_map(staged, options)
    end,
    leave = function()
      select_item = {}
      item_count = 1
    end,
  }).handle

  pcall(vim.api.nvim_win_set_cursor, 0, { 2, 0 })

  vim.b.mug_branch_name = name
  vim.b.mug_branch_stats = stats
end

--Detect upstream branch name
---@return string # Branchspec `"<upstream>..HEAD"` or `"HEAD"`
local function detect_upstream()
  local branches = comp.branches()
  local spec

  for _, v in ipairs(branches) do
    if v == 'master' or v == 'main' then
      spec = string.format('%s..HEAD', v)
      break
    end
  end

  return spec and spec or 'HEAD'
end

---Get git log
---@param treeish string Specify upstream branch name
---@return table # Git log stdout
local function get_git_log(treeish)
  local max_log = string.format('-n%s', 50)
  local format = string.format('--format=%%h %s', _G.Mug.rebase_log_format)
  local branchspec = treeish or detect_upstream()
  local cmdline = util.gitcmd({
    noquotepath = true,
    cmd = 'log',
    opts = { max_log, '--no-color', format, branchspec },
  })

  return vim.fn.systemlist(cmdline)
end

--Adjust git sub-command options
---@param sign string Specifies gpg-sign
---@param stash boolean Enable autostash
---@param fargs table Rabese options
---@return string # Adjusted git log options
---@return table # Adjusted git rebase options
local function adjust_options(sign, stash, fargs)
  local treeish
  local opts = { '--interactive' }
  local gpg = _G.Mug.commit_gpg_sign and '--gpg-sign=' .. _G.Mug.commit_gpg_sign or '--gpg-sign'
  local gpgsign = sign == 'Sign' and gpg or nil
  local autostash = stash and '--autostash' or nil

  if not vim.tbl_isempty(fargs) and not fargs[1]:find('^-') then
    treeish = fargs[1]
    table.remove(fargs, 1)
  end

  if fargs[1] == nil then
    if gpgsign then
      table.insert(opts, gpgsign)
    end

    if autostash then
      table.insert(opts, autostash)
    end
  else
    for _, v in ipairs(fargs) do
      if gpgsign and not v:find('--gpg-sign', 1, true) then
        table.insert(opts, gpgsign)
      elseif autostash and not v:find(autostash, 1, true) then
        table.insert(opts, autostash)
      end
    end
  end

  return treeish, vim.list_extend(opts, fargs)
end

---Set user-defined keymaps
---@param callback function User defined keymaps
M.rebase_map = function(callback)
  addinional_maps = callback
end

---Open the MugRebase floating window
---@param name string Suffix of the MugRebase. `""`|`"sign"`
---@param stats table|nil Wroktree state
---@param bang boolean Has bang
---@param fargs table command arguments
M.rebase_i = function(name, stats, bang, fargs)
  if float.focus(float_handle) then
    return
  end

  if not stats then
    util.notify('Cannot get index', HEADER, 3)
    return
  end

  if (stats.s + stats.u) > 0 then
    if not bang and (stats.u > 0) then
      util.notify('Cannot rebase. Your index has changed', HEADER, 3)
      return
    end
  end

  local treeish, options = adjust_options(name, bang, fargs)
  local stdout = get_git_log(treeish)
  item_count = #stdout

  float_win(stdout, stats, options)
end

---Run MugRebase
local function middle_of_rebase(pwd, opts)
  local rebase_head = string.format('%s/.git/rebase_marge', pwd)

  for _, v in ipairs(comp_on_process) do
    if opts.args:find(v, 1, true) then
      if not vim.fn.isdirectory(rebase_head) then
        util.notify('There is no rebase in progress', HEADER, 3)
      elseif v == '--show-current-patch' then
        if package.loaded['mug.show'] then
          vim.cmd.MugShow({ 'git rebase', bang = true })
        else
          vim.cmd(string.format('!git rebase %s', v))
        end
      elseif v == '--edit-todo' then
        rebase_buffer(false, { v }, '')
      else
        local log = vim.fn.systemlist({ 'git', 'rebase', v })

        if vim.v.shell_error == 0 then
          util.notify('Success', HEADER, 2)
        else
          util.notify(log, HEADER, 3)
        end
      end

      return true
    end
  end
end

local function complist(_, l)
  if vim.b.mug_branch_info ~= '' and vim.b.mug_branch_info ~= 'Detached' then
    return comp_on_process
  end

  local input = vim.split(l, ' ', { plain = true })

  if #input <= 2 then
    return comp.branches()
  end

  return tbl.rebase_options
end

---MugRebase
---@param name string Suffix of the MugRebase. `""`|`"sign"`
local function mug_rebase(name)
  vim.api.nvim_create_user_command(NAMESPACE .. name, function(opts)
    local ok, pwd = util.has_repo(HEADER)

    if not ok then
      return
    end

    if middle_of_rebase(pwd, opts) then
      branch.branch_name(pwd, true)
      return
    end

    local stats = vim.b.mug_branch_stats
    M.rebase_i(name, stats, opts.bang, opts.fargs)
  end, {
    nargs = '*',
    bang = true,
    complete = function(a, l, _)
      return comp.filter(a, l, complist(a, l))
    end,
  })
end

mug_rebase('')
mug_rebase('Sign')

return M
