local branch = require('mug.branch')
local extmark = require('mug.module.extmark')
local float = require('mug.module.float')
local hl = require('mug.module.highlight')
local map = require('mug.module.map')
local syntax = require('mug.module.syntax')
local util = require('mug.module.util')

local HEADER, NAMESPACE = 'mug/index', 'MugIndex'
local INPUT_TITLE = 'Commit'
local INPUT_WIDTH = 54
local stat_lines, add_lines, reset_lines, force_lines = {}, {}, {}, {}
local item_count = 0
local enable_ignored = false
local index_buffer = {
  handle = 0,
  input_handle = 0,
  alt_bufnr = 0,
}

---@type integer
local ns_add = vim.api.nvim_create_namespace(NAMESPACE .. '_Add')
---@type integer
local ns_force = vim.api.nvim_create_namespace(NAMESPACE .. '_Force')
---@type integer
local ns_reset = vim.api.nvim_create_namespace(NAMESPACE .. '_Reset')

---@class Mug
---@field index_add_key string Key to git add selection
---@field index_force_key string Key to git add --force selection
---@field index_reset_key string Key to git reset selection
---@field index_clear_key string Key to clear selection
---@field index_inputbar string Key to launch commit input-bar
_G.Mug._def('index_add_key', 'a', true)
_G.Mug._def('index_force_key', 'f', true)
_G.Mug._def('index_reset_key', 'r', true)
_G.Mug._def('index_clear_key', 'c', true)
_G.Mug._def('index_inputbar', '@', true)
_G.Mug._def('index_commit', '`', true)
_G.Mug._def('index_auto_update', false, true)

---Record highlight settings after invoking autocmd ColorScheme
hl.late_record(function()
  local hlname = vim.fn.hlexists('NormalFloat') == 1 and 'NormalFloat' or 'Normal'
  local items = {
    MugIndexAdd = hl.shade(0, hlname, 5, 20, 10),
    MugIndexForce = hl.shade(0, hlname, 10, 5, 20),
    MugIndexReset = hl.shade(0, hlname, 20, 10, 5),
  }
  for name, value in pairs(items) do
    hl.set_hl(name, { ns = 0, hl = { bg = value } })
  end
end)

hl.record('MugIndexHeader', { ns = 0, hl = { link = 'String' } })
hl.record('MugIndexStage', { ns = 0, hl = { link = 'Statement' } })
hl.record('MugIndexUnstage', { ns = 0, hl = { link = 'ErrorMsg' } })

---Run "git status" to get results
---@return boolean # Error occurred
---@return table # Git status result
local function get_stats()
  local ignore = enable_ignored
  local lines = branch.branch_stats(nil, false, ignore)
  local err = lines[1] == 'Not a git repository' or (lines[1] == 'fatal:')
  item_count = #lines

  if item_count == 2 and lines[2] == '' then
    err = true
    lines[1] = 'No changes'
  end

  return err, lines
end

---@alias Error boolean # Error occurred

---Create index summary
---@return Error
---@return string[] # Index summaries
local function initial_idx()
  local err, lines = get_stats()
  local summary = vim.fn.systemlist(util.gitcmd({ cmd = 'diff', opts = { '--no-color', '--compact-summary', 'HEAD' } }))

  if not err then
    local len

    for i, v in ipairs(lines) do
      for _, s in ipairs(summary) do
        if v ~= '' and s:find(v:sub(3), 1, true) then
          len = #v:sub(3) + 1
          stat_lines[v:sub(3)] = s:sub(len)
          lines[i] = string.format(' %s%s', v:sub(1, 2), s)
          goto continue
        end
      end

      lines[i] = string.format(' %s', v)

      ::continue::
    end
  end

  return err, lines
end

---Update indexes
---@return Error
---@return string[] # Lines of the buffer
local function update_idx()
  local err, lines = get_stats()

  if not err then
    for i, v in ipairs(lines) do
      lines[i] = string.format(' %s%s', v, stat_lines[v:sub(3)] or '')
    end
  end

  return err, lines
end

---Staging selected files
---@return boolean # Whether the index has changed
local function do_stage()
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
        if select.contents:find('^[^|]* -> ') then
          select.contents = select.contents:gsub('^.+->%s', '')
        end

        select = select.contents:gsub('^(%S+).*', '%1')
        table.insert(items, select)
      end

      local cmdline = util.gitcmd({ noquotepath = true, cmd = v.subcmd, opts = { v.force, unpack(items) } })
      local output = vim.fn.systemlist(cmdline)

      ---NOTE: Table is only referenced, joint assignment not allowed
      repeat
        table.remove(v.selections)
      until v.selections[1] == nil

      vim.api.nvim_buf_clear_namespace(0, v.ns, 0, -1)

      if vim.api.nvim_get_vvar('shell_error') ~= 0 then
        table.insert(error_msg, string.format('[%s] %s', v.subcmd, output[1]))
      end
    end

    items = {}
  end

  if not vim.tbl_isempty(error_msg) then
    extmark.warning(error_msg, 4, vim.api.nvim_win_get_height(0))
  end

  return skip ~= 3
end

---Change the content of the line
---@param line integer Number of lines held by current buffer
---@param contents string[] Changes
local function modify_buffer(line, contents)
  vim.api.nvim_set_option_value('modifiable', true, { buf = 0 })
  vim.api.nvim_buf_set_text(0, 0, 0, line - 1, 0, contents)
  vim.api.nvim_set_option_value('modifiable', false, { buf = 0 })
end

---Update the buffer of the MugIndex
---@param result? table Stdout of the "git status"
local function update_buffer(result)
  local buf_lines = vim.api.nvim_buf_line_count(0)
  local err, lines = update_idx()

  if err then
    if vim.bo.buftype == 'nofile' then
      modify_buffer(buf_lines, lines)
    else
      util.notify(lines, HEADER, 3, true)
    end
    return
  end

  if item_count ~= buf_lines then
    vim.api.nvim_win_set_height(0, item_count)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
  end

  modify_buffer(buf_lines, lines)

  if result and vim.api.nvim_get_vvar('shell_error') ~= 0 then
    local height = vim.api.nvim_win_get_height(0)
    extmark.warning(result, 4, height)
  end

  branch.branch_stats(vim.uv.cwd(), false)

  local name = vim.b.mug_branch_name
  local stats = vim.b.mug_branch_stats
  vim.api.nvim_buf_call(index_buffer.alt_bufnr, function()
    vim.b.mug_branch_name = name
    vim.b.mug_branch_stats = stats
  end)
end

---Auto update on buffer focus
local function auto_update()
  vim.api.nvim_create_autocmd({ 'BufEnter', 'FocusGained' }, {
    group = 'mug',
    buffer = 0,
    callback = function()
      update_buffer()
      vim.api.nvim_exec_autocmds('User', {
        group = 'mug',
        pattern = 'MugRefreshBar',
      })
    end,
    desc = 'MugIndex upload',
  })
end

---@alias namespace string Specifies namespace
---@alias ln integer Specifies line number

---Update an extmark for the specified line
---@param ns namespace
---@param row ln
local function set_extmark(ns, row)
  local details = {
    add = { ns_add, add_lines, 'MugIndexAdd' },
    force = { ns_force, force_lines, 'MugIndexForce' },
    reset = { ns_reset, reset_lines, 'MugIndexReset' },
  }

  extmark.select_line(row, 4, unpack(details[ns]))

  for _, v in ipairs(vim.tbl_keys(details)) do
    if v ~= ns then
      extmark.release_line(row, unpack(details[v]))
    end
  end
end

---Update an extmark to current line
---@param ns namespace
---@return integer? # Number of lines held by current buffer
local function select_this(ns)
  local row = vim.api.nvim_win_get_cursor(0)[1]

  if row == item_count then
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

---Set an extmark and move the cursor by one
---@param direction? integer Direction of cursor movement
local function add_this(direction)
  local ln = select_this('add')

  if not ln then
    return
  end

  if direction then
    local row = direction == 1 and math.min(ln + 1, item_count) or math.max(ln - 1, 2)
    local col = vim.api.nvim_win_get_cursor(0)[2]

    vim.api.nvim_win_set_cursor(0, { row, col })
  end
end

---Update the title of the commit-input-bar
---@param title string Changed title
---@param keyid string ID of the gpg-sign
---@param sign string[] `--gpg-sign` or `empty`
---@param amend string[] `--amend` or `empty`
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

---Set keymaps to the commit-input-bar
local function input_commit_map()
  local sign, amend = {}, {}
  local title = vim.api.nvim_win_get_config(0).title[1][1]
  title = title:sub(2, #title - 1)
  local keyid = _G.Mug.commit_gpg_sign and string.format('--gpg-sign=%s', _G.Mug.commit_gpg_sign) or '--gpg-sign'

  map.buf_set(true, 'i', '<C-o><C-s>', function()
    sign = #sign == 0 and { keyid } or {}
    update_imputbar_title(title, keyid, sign, amend)
  end, 'Add commit options "--gpg-sign"')

  map.buf_set(true, 'i', '<C-o><C-a>', function()
    amend = #amend == 0 and { '--amend' } or {}
    update_imputbar_title(title, keyid, sign, amend)
  end, 'Add commit options "--amend"')

  map.buf_set(true, 'i', '<CR>', function()
    local msg = vim.api.nvim_get_current_line()

    if msg == '' and #amend ~= 0 then
      msg = '--no-edit'
    else
      msg = string.format('-m %s', msg)
    end

    local cmdline = util.gitcmd({ cmd = 'commit', opts = { sign, amend, '--cleanup=default', msg } })
    vim.fn.systemlist(cmdline)
    vim.cmd('stopinsert!|quit')
  end, 'Update index')
end

---Get the file-path from the line contents
---@return string|nil # File-path or nil
local function linewise_path()
  local root = vim.fs.find('.git', { type = 'directory', upward = true })[1]
  local relative = vim.api.nvim_get_current_line():sub(5):gsub('^(%S+).+', '%1')
  local path = string.format('%s%s', root:gsub('.git', ''), relative)
  if not util.file_exist(path) then
    return nil
  end

  return path
end

---Close buffer and diff off
local function diff_close()
  if not vim.api.nvim_get_option_value('diff', { win = 0 }) then
    return
  end

  if vim.fn.winbufnr(2) ~= -1 then
    vim.cmd('close|diffoff')
  end
end

---Set keymaps to the floating window
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

    vim.cmd.wincmd('p')
    diff_close()
    vim.cmd.edit(path)
    vim.cmd.MugDiff()
  end, 'Open the path at the cursor line')

  map.buf_set(true, 'n', 'gf', function()
    local path = linewise_path()

    if not path then
      return
    end

    vim.cmd('wincmd p|edit ' .. path)
  end, 'Open file diff')

  map.buf_set(true, 'n', '<F5>', function()
    update_buffer()
    extmark.warning({ 'Update index' }, 3, vim.api.nvim_win_get_height(0))
  end, 'Update index')

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
    if float.focus(index_buffer.input_handle) then
      return
    end

    if vim.api.nvim_buf_get_var(0, 'mug_branch_stats').s == 0 then
      extmark.warning({ 'No stages' }, 4, vim.api.nvim_win_get_height(0))
      return
    end

    index_buffer.input_handle = float.input_nc({
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
    vim.cmd.MugCommit()
  end, 'Open commit-editmsg')

  ---staging
  map.buf_set(true, 'n', '<CR>', function()
    local update = do_stage()

    if update then
      update_buffer()
    end
  end, 'Update the index of selected files')
end

---Processing after floating window startup
local function float_win_post()
  vim.api.nvim_buf_set_option(0, 'modifiable', false)
  syntax.index()
  syntax.stats()
  float_win_map()

  if _G.Mug.index_auto_update then
    auto_update()
  end
end

---Set floating window
---@param stdout string[] MugIndex contents per line
local function float_win(stdout)
  local name = vim.b.mug_branch_name
  local stats = vim.b.mug_branch_stats

  index_buffer.handle = float.open({
    title = NAMESPACE,
    height = 1,
    width = 0.4,
    border = 'rounded',
    contents = function()
      return stdout
    end,
    post = float_win_post,
    leave = function()
      stat_lines, add_lines, force_lines, reset_lines = {}, {}, {}, {}
      item_count, enable_ignored = 2, false
    end,
  }).handle

  vim.b.mug_branch_name = name
  vim.b.mug_branch_stats = stats
end

vim.api.nvim_create_user_command(NAMESPACE, function(opts)
  if float.focus(index_buffer.handle) then
    return
  end

  index_buffer.alt_bufnr = vim.api.nvim_win_get_buf(0)
  local has_repo, git_root = util.has_repo(HEADER)

  if not has_repo then
    return
  end

  enable_ignored = opts.bang
  local err, stdout = initial_idx()

  if err then
    util.notify(stdout[1], HEADER, 3)
    return
  end

  float_win(stdout)
  vim.cmd.lcd(git_root)
end, {
  nargs = 0,
  bang = true,
})
