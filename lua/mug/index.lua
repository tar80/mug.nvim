local util = require('mug.module.util')
local float = require('mug.module.float')
local extmark = require('mug.module.extmark')
local hl = require('mug.module.highlight')
local map = require('mug.module.map')
local timer = require('mug.module.timer')
local branch_stats = require('mug.branch').branch_stats

local HEADER, NAMESPACE = 'mug/index', 'MugIndex'
local INPUT_TITLE, INPUT_WIDTH = 'Commit', 54
local add_lines, reset_lines, force_lines = {}, {}, {}
local float_handle, input_handle = 0, 0
local float_height = 2
local enable_ignored = false

local ns_add = vim.api.nvim_create_namespace('mugIndex_add')
local ns_force = vim.api.nvim_create_namespace('mugIndex_force')
local ns_reset = vim.api.nvim_create_namespace('mugIndex_reset')
local ns_error = vim.api.nvim_create_namespace('mugIndex_error')

---@class Mug
---@field index_add_key string key to git add selection
---@field index_force_key string key to git add --force selection
---@field index_reset_key string key to git reset selection
---@field index_clear_key string key to clear selection
---@field index_inputbar string key to launch commit input-bar
_G.Mug._def('index_add_key', 'a', true)
_G.Mug._def('index_force_key', 'f', true)
_G.Mug._def('index_reset_key', 'r', true)
_G.Mug._def('index_clear_key', 'c', true)
_G.Mug._def('index_inputbar', '@', true)
_G.Mug._def('index_commit', '`', true)

hl.link(0, 'MugIndexHeader', 'String')
hl.link(0, 'MugIndexStage', 'Statement')
hl.link(0, 'MugIndexUnstage', 'ErrorMsg')
hl.link(0, 'MugIndexWarning', 'ErrorMsg')

local function float_win_hl()
  local hlname = vim.fn.hlexists('NormalFloat') == 1 and 'NormalFloat' or 'Normal'

  if vim.fn.hlexists('MugIndexAdd') == 0 then
    vim.api.nvim_set_hl(0, 'MugIndexAdd', { bg = hl.shade(hlname, 0, 10, 5) })
    vim.api.nvim_set_hl(0, 'MugIndexForce', { bg = hl.shade(hlname, 0, 5, 30) })
    vim.api.nvim_set_hl(0, 'MugIndexReset', { bg = hl.shade(hlname, 20, 0, 5) })
  end

  vim.api.nvim_command([[syn match MugIndexHeader "^##\s.\+$" display oneline]])
  vim.api.nvim_command([[syn match MugIndexUnstage "^\s.[MADRC]\s" display]])
  vim.api.nvim_command([[syn match MugIndexStage "^\s[MADRC]" display]])
  vim.api.nvim_command([[syn match MugIndexUnstage "^[?!U]\{2}" display]])
end

---@param messages table Error messages
---@param row number Line to put virtual text
local function virtual_warning(messages, row)
  local winid = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_get_current_buf()
  local msg
  local msg_count = #messages
  local wait, delay = 4000, 400
  local hlname = 'MugIndexWarning'

  timer.discard(winid, function()
    extmark.clear_ns(bufnr, ns_error, 0, -1)
  end)
  timer.set(winid, wait, delay, function(i, timeout)
    if i > msg_count then
      return true
    end

    msg = '(' .. i .. '/' .. msg_count .. ')' .. messages[i]
    extmark.virtual_txt(bufnr, row, 0, ns_error, msg, hlname)
    vim.defer_fn(function()
      extmark.clear_ns(bufnr, ns_error, 0, -1)
    end, timeout)
  end)
end

---Get git index and status
---@param bang? boolean Add "--ignored" option
---@return boolean # Error occurred
---@return table # Git status result
local function get_stats(bang)
  local ignore = bang or enable_ignored
  local list = branch_stats(nil, false, ignore)
  local err = list[1] == 'Not a git repository' or list[1] == 'fatal:'
  float_height = #list

  for i, v in ipairs(list) do
    list[i] = ' ' .. v
  end

  return err, list
end

---@param height number Floating-window height
---@return boolean # Whether the index has changed
local function do_stage(height)
  local linewise = {
    { subcmd = 'add', ns = ns_add, selections = add_lines },
    { subcmd = 'add', force = '--force', ns = ns_force, selections = force_lines },
    { subcmd = 'reset', ns = ns_reset, selections = reset_lines },
  }

  local items, error_msg = {}, {}
  local skip = 0

  for _, v in ipairs(linewise) do
    if vim.tbl_isempty(v.selections) then
      skip = skip + 1
    else
      for _, select in ipairs(v.selections) do
        ---Renamed item
        if select.contents:find(' -> ', 1, true) then
          select.contents = select.contents:gsub('^.+->%s', '')
        end

        table.insert(items, select.contents)
      end

      local cmdline = util.gitcmd({ noquotepath = true, cmd = v.subcmd, opts = { v.force, unpack(items) } })
      local output = vim.fn.systemlist(cmdline)

      ---NOTE: Table is only referenced, joint assignment not allowed
      repeat
        table.remove(v.selections)
      until v.selections[1] == nil

      vim.api.nvim_buf_clear_namespace(0, v.ns, 0, -1)

      if vim.api.nvim_get_vvar('shell_error') ~= 0 then
        table.insert(error_msg, '[' .. v.subcmd .. '] ' .. output[1])
      end
    end

    items = {}
  end

  if not vim.tbl_isempty(error_msg) then
    virtual_warning(error_msg, vim.api.nvim_win_get_height(0))
  end

  return skip ~= 3 and true
end

---@param result? table Stdout of git status
local function update_buffer(result)
  local buf_lines = vim.api.nvim_buf_line_count(0)
  local err, lines = get_stats()

  if err then
    util.notify(lines, HEADER, 3, true)
    return
  end

  if float_height ~= buf_lines then
    vim.api.nvim_win_set_height(0, float_height)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
  end

  vim.api.nvim_buf_set_option(0, 'modifiable', true)
  vim.api.nvim_buf_set_text(0, 0, 0, buf_lines - 1, 0, lines)
  vim.api.nvim_buf_set_option(0, 'modifiable', false)

  if result and vim.api.nvim_get_vvar('shell_error') ~= 0 then
    local height = vim.api.nvim_win_get_height(0)
    virtual_warning(result, height)
  end
end

---@alias namespace string Specified namespace
---@alias ln number Specified line number

---@param ns namespace
---@param ln ln
local function set_extmark(ns, ln)
  local details = {
    add = { ns_add, add_lines, 'MugIndexAdd' },
    force = { ns_force, force_lines, 'MugIndexForce' },
    reset = { ns_reset, reset_lines, 'MugIndexReset' },
  }

  -- local set = details[type]
  extmark.select_line(ln, 4, unpack(details[ns]))
  -- set[2] = extmark.select_line(ln, 3, unpack(set))
  -- set = nil

  for _, v in ipairs(vim.tbl_keys(details)) do
    if v ~= ns then
      -- local release = details[v]
      -- release[2] = extmark.release_line(ln, unpack(release))
      extmark.release_line(ln, unpack(details[v]))
    end
  end
end

---@param ns namespace
---@return number? # Number of lines held by current buffer
local function select_this(ns)
  local row = vim.api.nvim_win_get_cursor(0)[1]

  if row == float_height then
    return nil
  end

  if row ~= 1 then
    set_extmark(ns, row)
  else
    for i = 2, vim.api.nvim_buf_line_count(0) - 1 do
      set_extmark(ns, i)
    end
  end

  return row
end

---@param direction? number Direction of cursor movement
local function add_this(direction)
  local ln = select_this('add')

  if not ln then
    return
  end

  if direction then
    local row = direction == 1 and math.min(ln + 1, float_height) or math.max(ln - 1, 2)
    local col = vim.api.nvim_win_get_cursor(0)[2]

    vim.api.nvim_win_set_cursor(0, { row, col })
  end
end

local function update_imputbar_title(title, keyid, sign, amend)
  local new_title = { title }

  if #sign > 0 then
    table.insert(new_title, keyid)
  end

  if #amend > 0 then
    table.insert(new_title, '--amend')
  end

  title = float.title(table.concat(new_title, ' '), INPUT_WIDTH)
  vim.api.nvim_win_set_config(0, { title_pos = 'center', title = title })
end

local function input_commit_map()
  local sign, amend = {}, {}
  local title = vim.api.nvim_win_get_config(0).title[1][1]
  title = title:sub(2, #title - 1)
  local keyid = _G.Mug.commit_gpg_sign and '--gpg-sign=' .. _G.Mug.commit_gpg_sign or '--gpg-sign'

  vim.keymap.set('i', '<C-o><C-s>', function()
    sign = #sign == 0 and { keyid } or {}
    update_imputbar_title(title, keyid, sign, amend)
  end, { buffer = true })
  vim.keymap.set('i', '<C-o><C-a>', function()
    amend = #amend == 0 and { '--amend' } or {}
    update_imputbar_title(title, keyid, sign, amend)
  end, { buffer = true })
  vim.keymap.set('i', '<CR>', function()
    local input = vim.api.nvim_get_current_line()
    local cmdline = util.gitcmd({ cmd = 'commit', opts = { sign, amend, '--cleanup=default', '-m' .. input } })

    vim.api.nvim_command('stopinsert!|quit')
    local stdout = vim.fn.systemlist(cmdline)

    update_buffer(stdout)
  end, { buffer = true })
end

local function linewise_path()
  local path = vim.api.nvim_get_current_line():sub(5)
  if not util.file_exist(path) then
    path = nil
  end

  return path
end

local function diff_close()
  if not vim.api.nvim_win_get_option(0, 'diff') then
    return
  end

  if vim.fn.winbufnr(2) ~= -1 then
    vim.api.nvim_command('close|diffoff')
  end
end

local function float_win_map()
  map.buf_set(true, 'n', 'gd', function()
    if not package.loaded['mug.diff'] then
      util.notify('MugDiff not available', HEADER, 3)
      return
    end

    local path = linewise_path()

    if not path then
      return
    end

    vim.api.nvim_command('wincmd p')
    diff_close()
    vim.api.nvim_command('edit ' .. path .. '|MugDiff')
  end, 'Open the path at the cursor line')

  map.buf_set(true, 'n', 'gf', function()
    local path = linewise_path()

    if not path then
      return
    end

    vim.api.nvim_command('wincmd p|edit ' .. path)
  end, 'Open file diff')

  map.buf_set(true, 'n', _G.Mug.index_add_key, function()
    add_this()
  end, 'Add selection')

  map.buf_set(true, 'n', _G.Mug.index_force_key, function()
    select_this('force')
  end, 'Force add selection')

  map.buf_set(true, 'n', _G.Mug.index_reset_key, function()
    select_this('reset')
  end, 'Reset selection')

  map.buf_set(true, 'n', _G.Mug.index_clear_key, function()
    add_lines, force_lines, reset_lines = {}, {}, {}
    vim.api.nvim_buf_clear_namespace(0, -1, 0, -1)
  end, 'Clear selection')

  map.buf_set(true, 'n', 'J', function()
    add_this(1)
  end, 'Add selection and cursor down')

  map.buf_set(true, 'n', 'K', function()
    add_this(-1)
  end, 'Add selection and cursor up')

  map.buf_set(true, 'n', _G.Mug.index_inputbar, function()
    if float.focus(input_handle) then
      return
    end

    if vim.api.nvim_buf_get_var(0, 'mug_branch_stats').s == 0 then
      virtual_warning({ 'No stages' }, vim.api.nvim_win_get_height(0))
      return
    end

    input_handle = float.input_nc({
      title = INPUT_TITLE,
      width = INPUT_WIDTH,
      border = 'single',
      relative = 'editor',
      anchor = 'NW',
      post = input_commit_map,
    }).handle
  end, 'Launch commit-inputbar')

  map.buf_set(true, 'n', _G.Mug.index_commit, function()
    vim.api.nvim_win_close(0, {})
    vim.api.nvim_command('MugCommit')
  end, 'Open commit-editmsg')

  ---staging
  map.buf_set(true, 'n', '<CR>', function()
    local update = do_stage(float_height)

    if update then
      update_buffer()
    end
  end, 'Update the index of selected files')
end

local function float_win_post()
  vim.api.nvim_buf_set_option(0, 'modifiable', false)
  float_win_hl()
  float_win_map()
end

local function float_win(list)
  local name = vim.b.mug_branch_name
  local stats = vim.b.mug_branch_stats

  float_handle = float.open({
    title = NAMESPACE,
    height = 1,
    width = 0.4,
    border = 'rounded',
    contents = function()
      return list
    end,
    post = float_win_post,
    leave = function()
      add_lines, force_lines, reset_lines = {}, {}, {}
      float_height, enable_ignored = 2, false
    end,
  }).handle

  vim.b.mug_branch_name = name
  vim.b.mug_branch_stats = stats
end

vim.api.nvim_create_user_command(NAMESPACE, function(opts)
  if float.focus(float_handle) then
    return
  end

  enable_ignored = opts.bang
  local err, list = get_stats(enable_ignored)

  if err then
    util.notify(list[1], HEADER, 3)
    return
  end

  if #stdout == 2 and stdout[2]:match('^%s+$') then
    util.notify('Index is clean', HEADER, 2)
    return
  end

  float_win(stdout)
end, {
  nargs = 0,
  bang = true,
})
