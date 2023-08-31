local tbl = require('mug.module.table')
local hl = require('mug.module.highlight')
local util = require('mug.module.util')
local map = require('mug.module.map')
local job = require('mug.module.job')
local comp = require('mug.module.comp')

local M = {}
local buffers, loclist = {}, {}
local HEADER, NAMESPACE = 'mug/conflict', 'MugConflict'
local ns = vim.api.nvim_create_namespace(NAMESPACE)
local winpos = 'zz'

---@class Mug
---@field loclist_position string Specified position of location-list
---@filed loclist_disable_number boolean Hide line-number in location-list
---@field filewin_beacon string Characters to be specified for beacon
---@field filewin_indicate_position string `upper` or `center` or `lower`
---@field conflict_begin string String identified as the start of the conflict
---@field conflict_anc string String identified as the ancestor of the conflict
---@field conflict_sep string String identified as the separator of the conflict
---@field conflict_end string String identified as the end of the conflict
_G.Mug._def('loclist_position', 'left', true)
_G.Mug._def('loclist_disable_number', false, true)
_G.Mug._def('filewin_beacon', '@@', true)
_G.Mug._def('filewin_indicate_position', 'center', true)
_G.Mug._def('conflict_begin', '^<<<<<<< ', true)
_G.Mug._def('conflict_anc', '^||||||| ', true)
_G.Mug._def('conflict_sep', '^=======$', true)
_G.Mug._def('conflict_end', '^>>>>>>> ', true)

hl.late_record(function()
  local name = 'MugConflictBoth'
  local bgcolor = hl.shade(0, 'Normal', 20, 15, 0)
  vim.api.nvim_set_hl(0, name, { bg = bgcolor })
  hl.record(name, { ns = 0, hl = { bg = bgcolor } })

  if vim.g.loaded_conflict_marker == 1 then
    hl.record('ConflictMarkerBegin', { ns = 0, hl = { link = 'MugConflictHeader' } })
    hl.record('ConflictMarkerCommonAncestors', { ns = 0, hl = { link = 'MugConflictHeader' } })
    hl.record('ConflictMarkerCommonAncestorsHunk', { ns = 0, hl = { link = 'MugConflictHeader' } })
    hl.record('ConflictMarkerSeparator', { ns = 0, hl = { link = 'MugConflictHeader' } })
    hl.record('ConflictMarkerEnd', { ns = 0, hl = { link = 'MugConflictHeader' } })
  end
end)

hl.record('MugConflictBoth', { ns = 0, hl = { bg = hl.shade(0, 'Normal', 20, 15, 0) } })
hl.record('MugConflictHeader', { ns = 0, hl = { fg = '#777777', bg = '#000000' } })
hl.record('MugConflictBase', { ns = 0, hl = { link = 'DiffDelete' } })
hl.record('MugConflictOurs', { ns = 0, hl = { link = 'DiffChange' } })
hl.record('MugConflictTheirs', { ns = 0, hl = { link = 'DiffAdd' } })
hl.record('MugConflictBeacon', { ns = 0, hl = { link = 'Search' } })

local function get_conflict_files()
  return vim.fn.systemlist(
    util.gitcmd({ noquotepath = true, cmd = 'diff', opts = { '--diff-filter=U', '--name-only' } })
  )
end

---@param winid number Window-id
---@return number # Cursor position in the specified window
local function current_line(winid)
  return vim.api.nvim_win_get_cursor(winid)[1]
end

---@param winid number window-id
---@param row number specified line number to move the cursor to
local function set_cursor(winid, row)
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local lastline = vim.api.nvim_buf_line_count(bufnr)
  row = row == -1 and lastline or math.min(row, lastline)
  vim.api.nvim_win_set_cursor(winid, { row, 0 })
end

---@param text string
---@return table # {name, start, end, ext_id}
local function split_text(text)
  local t = {}
  text = text:gsub('^([^|]+)|(%d+)-(%d+)|%s(%d+)', '%1,%2,%3,%4')

  for v in text:gmatch('[^,]+') do
    table.insert(t, v)
  end

  return t
end

---@param callback function
local function modify_loclist(callback)
  vim.api.nvim_buf_set_option(0, 'modifiable', true)
  callback()
  vim.api.nvim_buf_set_option(0, 'modifiable', false)
  vim.api.nvim_buf_set_option(0, 'modified', false)
end

---@param toggle? boolean Whether to toggle the cursor position
---@return number bufnr Filewin buffer number
---@return number extmark-id Extmark id of hunks
local function adjust_filewin(toggle)
  local loc_row = current_line(0)
  local loc_contents = vim.fn.getloclist(0, { all = 0 })
  local filewin = loc_contents.items[loc_row]
  local winnr, text = filewin.bufnr, filewin.text
  local extid = text:gsub('^(%d+).+', '%1')
  local markers = buffers[winnr][tonumber(extid)]
  local winid = loc_contents.filewinid
  local win_row = current_line(winid)
  local new_row = split_text(vim.api.nvim_get_current_line())[2] - 0
  local subtraction = markers._ours - 1 - new_row
  local theirs = markers._theirs - subtraction
  local selected = vim.api.nvim_get_current_line():match(',$') == nil

  if winid == 0 or loc_row ~= loc_contents.idx then
    vim.api.nvim_command('ll ' .. loc_row)
    winid = vim.api.nvim_get_current_win()
    vim.api.nvim_command('wincmd p')
  elseif toggle and not selected and new_row >= win_row then
    new_row = theirs <= win_row and new_row or theirs
  end

  vim.api.nvim_win_call(winid, function()
    vim.api.nvim_command('normal ' .. new_row .. 'G' .. winpos)
  end)

  return winnr, markers
end

---@param close number End of the conflict region
---@param selected string Selected diff-content
local function update_loclist(close, selected)
  local filename, begin, stop, ext_id = unpack(split_text(vim.api.nvim_get_current_line()))
  local new_lines = {}
  new_lines[1] = filename .. '|' .. begin .. '-' .. close + 1 .. '| ' .. ext_id .. ',' .. selected

  local subtraction = (stop - begin) - (1 + close - begin)
  local lnum = current_line(0)
  local lines = vim.api.nvim_buf_get_lines(0, lnum, -1, false)

  for i, v in ipairs(lines) do
    if v:find(filename, 1, true) then
      _, begin, stop, ext_id = unpack(split_text(v))
      begin = begin - subtraction
      stop = stop - subtraction
      new_lines[i + 1] = filename .. '|' .. begin .. '-' .. stop .. '| ' .. ext_id .. ','
    end
  end

  modify_loclist(function()
    vim.api.nvim_buf_set_lines(0, lnum - 1, #new_lines + lnum - 1, false, new_lines)
  end)
end

---@param bufnr number
---@param extid number
---@return number # hunk begin line number
---@return number # hunk end line number
local function expose_hunk_region(bufnr, extid)
  local contents = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, extid, { details = true })
  local detail = contents[3]

  return contents[1], detail.end_row + 1
end

---@param bufnr number Loclist bufnr
---@param markers number Extmark number
---@param selected string Selected diff-content
local function pick_contents(bufnr, markers, selected)
  local hunk_begin, hunk_end = expose_hunk_region(bufnr, markers.id)
  local hunk_height, contents

  if selected == 'both' then
    hunk_height = #markers.ours + #markers.theirs
    contents = vim.deepcopy(markers.ours)
    vim.list_extend(contents, markers.theirs)
  else
    hunk_height = #markers[selected]
    contents = markers[selected]
  end

  local end_row = hunk_height == 0 and hunk_begin or hunk_begin + hunk_height - 1
  local end_col = hunk_height == 0 and 0 or vim.api.nvim_strwidth(contents[#contents])

  update_loclist(end_row, selected)
  vim.api.nvim_buf_set_lines(bufnr, hunk_begin, hunk_end, false, contents)
  vim.api.nvim_buf_set_extmark(bufnr, ns, hunk_begin, 0, {
    id = markers.id,
    end_row = end_row,
    end_col = end_col,
    hl_group = 'MugConflict' .. selected,
    priority = 5000,
    sign_text = _G.Mug.filewin_beacon,
    sign_hl_group = 'MugConflictBeacon',
  })

  ---Note: If you make multiple changes to different buffers without moving focus, the number of changes will
  --- be counted as one. This creates gaps in undo/redo, so multiple changes must be counted correctly.
  vim.api.nvim_command('wincmd p|wincmd p')
end

---@param command string `undo` or `redo`
local function youth_memories(command)
  modify_loclist(function()
    vim.api.nvim_command(command)
  end)

  adjust_filewin()
  local winid = vim.fn.getloclist(0, { filewinid = 0 }).filewinid
  vim.api.nvim_win_call(winid, function()
    vim.api.nvim_command(command)
  end)
end

---@param key string Keys to send filewin
local function sendkey_filewin(key)
  local winid = vim.fn.getloclist(0, { filewinid = 0 }).filewinid
  vim.api.nvim_win_call(winid, function()
    vim.api.nvim_command('exe "normal ' .. key .. '"')
  end)
end

local function syncview_command()
  vim.api.nvim_buf_create_user_command(0, 'MMMugLoclistSyncview', function(opts)
    local row = current_line(0)
    local count = opts.count == 0 and 1 or opts.count + 1 - row
    row = opts.args == 'j' and math.min(row + count, vim.api.nvim_buf_line_count(0)) or math.max(row - count, 1)

    set_cursor(0, row)

    if vim.b.toggle_syncview then
      adjust_filewin()
    end
  end, { nargs = '?', count = true })
end

local function on_detach(bufnr, files, swb, cm_hl)
  vim.api.nvim_create_autocmd({ 'BufWipeout' }, {
    group = 'mug',
    buffer = bufnr,
    once = true,
    callback = function()
      buffers, loclist = {}, {}
      vim.g.mug_loclist_loaded = nil

      vim.api.nvim_set_option('switchbuf', swb)

      if cm_hl == 1 then
        vim.api.nvim_set_var('conflict_marker_enable_highlight', cm_hl)
      end

      for _, v in ipairs(files) do
        local nr = vim.fn.bufnr(v)
        vim.api.nvim_buf_clear_namespace(nr, ns, 0, -1)

        if vim.api.nvim_buf_get_option(nr, 'modified') then
          vim.api.nvim_buf_call(nr, function()
            vim.api.nvim_command('silent edit!')
          end)
        end
      end
    end,
    desc = 'Detach conflict loclist',
  })
end

local function commit_message()
  local choice = util.confirm(
    'Conflict resolved. Continue merging and create commit now.',
    'Edit commit-message\nUse default commit-message\nCancel',
    1,
    HEADER
  )

  if choice < 3 then
    vim.api.nvim_command('tabclose')
    local pwd = util.pwd()

    if choice == 1 then
      require('mug.commit').commit_buffer('continue')
    elseif choice == 2 then
      local merge_msg = pwd .. '/.git/MERGE_MSG'

      local stdout, err =
        job.await(util.gitcmd({ cmd = 'commit', opts = { '--cleanup=strip', '--file=' .. merge_msg } }))
      util.notify(stdout, HEADER, err, false)

      if err == 2 then
        require('mug.branch').branch_name(pwd)
      end
    end
  end
end

---@param files table Conflict files
local function on_attach(files)
  vim.api.nvim_buf_set_var(0, 'toggle_syncview', true)
  syncview_command()

  map.ref_maps()
  map.buf_set(true, 'n', { 'q', '<Esc>' }, function()
    if util.confirm('Quit? ', 'Quit\nStay', 1, HEADER) ~= 1 then
      return
    end

    vim.api.nvim_command('tabclose')
  end, 'Close MugConflict')
  map.buf_set(true, 'n', 'w', function()
    do
      local modified

      for _, v in ipairs(files) do
        local nr = vim.fn.bufnr(v)

        if vim.api.nvim_buf_get_option(nr, 'modified') then
          modified = true
          vim.api.nvim_buf_call(nr, function()
            vim.api.nvim_command('silent update')
          end)
        end
      end

      if not modified then
        util.notify('No changes', HEADER, 2)
        return
      end
    end

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)

    for _, v in ipairs(lines) do
      if v:find(',$') then
        util.notify('Update modified files', HEADER, 2)
        return
      end
    end

    job.async(function()
      local cmd = util.gitcmd({ cmd = 'add', opts = { files } })
      local stdout, err = job.await(cmd)

      if err > 2 then
        util.notify(stdout, HEADER, err, false)
        return
      end

      if #get_conflict_files() == 0 then
        commit_message()
      else
        vim.api.nvim_command('tabclose')
      end
    end)
  end, 'Stage and commit')
  map.buf_set(true, 'n', '^', function()
    local isSync = not vim.b.toggle_syncview
    vim.api.nvim_buf_set_var(0, 'toggle_syncview', isSync)
    util.notify('Syncview=' .. tostring(isSync), HEADER, 2)
  end, 'toggle syncview')
  map.buf_set(true, 'n', '<C-r>', function()
    youth_memories('redo')
  end, 'Redo')
  map.buf_set(true, 'n', 'u', function()
    youth_memories('undo')
  end, 'Undo')
  map.buf_set(true, 'n', 'gg', function()
    set_cursor(0, 1)
    if vim.b.toggle_syncview then
      adjust_filewin()
    end
  end, 'Syncview top')
  map.buf_set(true, 'n', 'G', function()
    set_cursor(0, -1)

    if vim.b.toggle_syncview then
      adjust_filewin()
    end
  end, 'Syncview bottom')
  map.buf_set(true, 'n', 'j', ':MMMugLoclistSyncview j<CR>', 'Syncview down')
  map.buf_set(true, 'n', 'k', ':MMMugLoclistSyncview k<CR>', 'Syncview up')
  map.buf_set(true, 'n', '<C-d>', function()
    sendkey_filewin('\\<C-d>')
  end, 'Page half down on filewin')
  map.buf_set(true, 'n', '<C-u>', function()
    sendkey_filewin('\\<C-u>')
  end, 'Page half up on filewin')
  map.buf_set(true, 'n', '<C-j>', function()
    sendkey_filewin('j')
  end, 'Cursor down on filewin')
  map.buf_set(true, 'n', '<C-k>', function()
    sendkey_filewin('k')
  end, 'Cursor up on filewin')
  map.buf_set(true, 'n', 'b', function()
    local winnr, markers = adjust_filewin()
    pick_contents(winnr, markers, 'base')
  end, 'get contents (base)')
  map.buf_set(true, 'n', '<S-b>', function()
    local winnr, markers = adjust_filewin()
    pick_contents(winnr, markers, 'both')
  end, 'get contents (both)')
  map.buf_set(true, 'n', 'o', function()
    local winnr, markers = adjust_filewin()
    pick_contents(winnr, markers, 'ours')
  end, 'get contents (ours)')
  map.buf_set(true, 'n', 't', function()
    local winnr, markers = adjust_filewin()
    pick_contents(winnr, markers, 'theirs')
  end, 'get contents (theirs)')
  map.buf_set(true, 'n', '<CR>', function()
    adjust_filewin(true)
  end, 'Toggle position between ours and theirs')
end

---@param bufnr number Loclist filewin number
---@param name string Highlight name
---@param b number Hunk begin line number
---@param e number Hunk end line number
---@param priority number Extmark priority
---@param beacon? boolean Highlight line number
---@return number|nil # Extmark id of hunk region
local function set_extmark(bufnr, name, b, e, priority, beacon)
  local contents = vim.api.nvim_buf_get_lines(bufnr, e - 1, e, true)
  local len = e == '' and 0 or vim.api.nvim_strwidth(contents[1])
  local opts = { end_row = e - 1, end_col = len, priority = priority }

  if vim.fn.hlexists(name) == 1 then
    opts['hl_group'] = name
  end

  if beacon then
    opts['sign_text'] = _G.Mug.filewin_beacon
    opts['sign_hl_group'] = 'MugConflictBeacon'
  end

  return vim.api.nvim_buf_set_extmark(bufnr, ns, b - 1, 0, opts)
end

---@param bufnr number Loclist filewin number
---@param lnum table Hunk contents
---@return table {id: number, _ours: number, _theirs: number, ours: table, base: table, theirs: table }
local function prepare_hunks(bufnr, lnum)
  local ours = vim.api.nvim_buf_get_lines(bufnr, lnum._begin, lnum._anc - 1, false)
  local base = vim.api.nvim_buf_get_lines(bufnr, lnum._anc, lnum._sep - 1, false)
  local theirs = vim.api.nvim_buf_get_lines(bufnr, lnum._sep, lnum._end - 1, false)
  local extid = set_extmark(bufnr, 'Normal', lnum._begin, lnum._end, 200, true)
  set_extmark(bufnr, 'MugConflictOurs', lnum._begin + 1, lnum._anc - 1, 5010)
  set_extmark(bufnr, 'MugConflictBase', lnum._anc + 1, lnum._sep - 1, 5010)
  set_extmark(bufnr, 'MugConflictTheirs', lnum._sep + 1, lnum._end - 1, 5010)
  set_extmark(bufnr, 'MugConflictHeader', lnum._begin, lnum._begin, 5010)
  set_extmark(bufnr, 'MugConflictHeader', lnum._sep, lnum._sep, 5010)
  set_extmark(bufnr, 'MugConflictHeader', lnum._anc, lnum._anc, 5010)
  set_extmark(bufnr, 'MugConflictHeader', lnum._end, lnum._end, 5010)

  return { id = extid, _ours = lnum._begin + 1, _theirs = lnum._sep + 1, ours = ours, base = base, theirs = theirs }
end

---@param filename string Name of the conflicted file
local function load_buffers(filename)
  local bufnr = vim.fn.bufnr(filename)
  buffers[bufnr] = {}
  loclist = {}
  local lnum, hunks, hunk_info = {}, {}, {}
  local loc_line
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)

  for i = 1, #lines do
    lnum = {}

    if lines[i]:find(_G.Mug.conflict_begin) then
      lnum._begin = i

      for j = i, #lines do
        i = j

        if lines[j]:find(_G.Mug.conflict_anc) then
          lnum._anc = j
        elseif lines[j]:find(_G.Mug.conflict_sep) then
          lnum._sep = j
          lnum._anc = lnum._anc or j
        elseif lines[j]:find(_G.Mug.conflict_end) then
          lnum._end = j

          break
        end
      end

      hunk_info = prepare_hunks(bufnr, lnum)
      hunks[hunk_info.id] = hunk_info
      loc_line = filename .. ':' .. lnum._begin .. '-' .. lnum._end .. ':' .. hunk_info.id .. ','
      table.insert(loclist, loc_line)
    end
  end

  vim.fn.setloclist(0, {}, 'a', { nr = '$', filename = filename, efm = '%f:%l-%e:%m', lines = loclist })
  buffers[bufnr] = hunks
end

---@return table files # Conflict file names
local function arglist()
  local files = get_conflict_files()
  local files_esc = {}

  if #files == 0 then
    return {}
  end

  for i, v in ipairs(files) do
    if v:find('"', 1, true) then
      files[i] = v:sub(2, -2)
      files_esc[i] = files[i]:gsub(' ', '\\ ')
    else
      files_esc[i] = files[i]
    end
  end

  vim.api.nvim_command('silent arglocal ' .. table.concat(files_esc, ' '))

  return files
end

---@param nonumber? boolean Disable column of line number
local function hide_column(nonumber)
  vim.api.nvim_win_set_option(0, 'signcolumn', 'no')
  vim.api.nvim_win_set_option(0, 'foldcolumn', '0')

  if nonumber then
    vim.api.nvim_win_set_option(0, 'number', false)
    vim.api.nvim_win_set_option(0, 'relativenumber', false)
  end
end

---@param position string|nil Loclist window position
---@return number # Loclist buffer number
local function open_loclist(position)
  local winsize = 36
  position = position or _G.Mug.loclist_position

  if position == 'top' or position == 'bottom' then
    winsize = 10
  elseif position ~= 'right' then
    position = 'left'
  end

  vim.api.nvim_command(tbl.positions[position] .. winsize .. 'lwindow|clearjumps')
  vim.api.nvim_buf_set_option(0, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_name(0, 'Mug://conflict')
  hide_column(_G.Mug.loclist_disable_number)
  vim.api.nvim_set_var('mug_loclist_loaded', vim.api.nvim_get_current_win())

  return vim.api.nvim_get_current_buf()
end

---@param position string|nil Loclist window location
M.loclist = function(position)
  vim.api.nvim_command('-tabnew')
  vim.api.nvim_buf_set_option(0, 'bufhidden', 'wipe')

  local conflict_files = arglist()

  if #conflict_files == 0 then
    util.notify('There was no conflict', HEADER, 2)
    vim.api.nvim_command('tabclose')

    return
  end

  local swb = vim.api.nvim_get_option('switchbuf')
  local cm_hl = vim.g.conflict_marker_enable_highlight

  if cm_hl == 1 then
    vim.api.nvim_set_var('conflict_marker_enable_highlight', '0')
  end

  vim.api.nvim_set_option('switchbuf', 'uselast')
  vim.api.nvim_win_set_hl_ns(0, ns)
  vim.api.nvim_command('silent argdo! edit!')

  buffers = {}

  for _, v in ipairs(conflict_files) do
    load_buffers(v)
  end

  vim.api.nvim_command('silent lfirst|clearjumps|normal ' .. winpos)

  if not vim.api.nvim_win_get_option(0, 'signcolumn') then
    vim.api.nvim_win_set_option(0, 'signcolumn', true)
  end

  local locnr = open_loclist(position)

  on_attach(conflict_files)
  on_detach(locnr, conflict_files, swb, cm_hl)
end

local function filewin_adjust_key()
  local key = { upper = 'zt', center = 'zz', lower = 'zb' }
  winpos = key[_G.Mug.filewin_indicate_position] or winpos
end

local function close_loclist()
  if vim.g.mug_loclist_loaded then
    local id = tonumber(vim.g.mug_loclist_loaded)
    vim.api.nvim_win_call(id, function()
      vim.api.nvim_command('tabclose')
    end)
  else
    local bufs = vim.api.nvim_list_bufs()

    for _, bufnr in ipairs(bufs) do
      if vim.api.nvim_buf_get_option(bufnr, 'filetype') == 'qf' then
        vim.fn.setloclist(0, {}, 'r')
        vim.api.nvim_command('lclose')
        break
      end
    end
  end
end

vim.api.nvim_create_user_command(NAMESPACE, function(opts)
  if not util.has_repo(HEADER) then
    return
  end

  close_loclist()
  filewin_adjust_key()
  M.loclist(opts.fargs[1])
end, {
  nargs = '?',
  complete = function(a, l, _)
    return comp.filter(a, l, { 'top', 'bottom', 'left', 'right' })
  end,
})

return M
