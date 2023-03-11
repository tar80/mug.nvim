local util = require('mug.module.util')
local float = require('mug.module.float')
local job = require('mug.module.job')
local hl = require('mug.module.highlight')
local map = require('mug.module.map')
local comp = require('mug.module.comp')
local branch_stats = require('mug.branch').branch_stats

---@class commit
---@field commit_buffer function Open unique commit-edit buffer
local M = {}
local HEADER, NAMESPACE = 'mug/commit', 'MugCommit'
local COMMIT_BUFFER_URI = 'Mug://commit'
local DIFFCACHED_URI = 'Mug://diffcached'
local TEMPLATE_DIR = _G.Mug.root .. '/lua/mug/template/'

---@type boolean|nil Put gpg signature
local signature

---@type table {cwd: bufnr}
local diffcached_bufnr = {}
local float_handle = 0

---@class Mug
---@field strftime string Date-time formats. that can be inserted when editing a commit-message
---@field commit_notation string Notation used to prefix commit-message
---@field commit_diffcached_height integer Diffcached buffer height
---@field commit_gpg_sign string Specify gpg sign keyid
_G.Mug._def('strftime', '%c', true)
_G.Mug._def('commit_notation', 'none', true)
_G.Mug._def('commit_diffcached_height', 20, true)

hl.link(0, 'MugLogHash', 'Special')
hl.link(0, 'MugLogDate', 'Statement')
hl.link(0, 'MugLogOwner', 'Conditional')
hl.link(0, 'MugLogHead', 'Keyword')

---Setup commit-edit own abbreviations
---@param notation string Prefix notation format
---@return function|nil # Functions describing user-added settings
local function setup_abbrev(notation)
  if notation == 'none' then
    return nil
  end

  local setting_filepath = TEMPLATE_DIR .. notation .. '.lua'

  if not util.file_exist(setting_filepath) then
    util.notify('Could not get abbreviations. "template/' .. notation .. '.lua" is not exist', HEADER, 3)
    return nil
  end

  ---@module 'template'
  local template = require('mug.template.' .. notation)

  for k, v in pairs(template.abbrev) do
    vim.api.nvim_command('inorea <buffer> ' .. k .. ' ' .. v)
  end

  return template.additional_settings
end

---Warn when failure is expected
---@async
---@param staged number Count of files staged
local function async_warning(staged)
  if staged == 0 then
    util.notify('No files staged', HEADER, 3)
    return
  end

  job.async(function()
    local result, err = job.await(util.gitcmd({ cmd = 'commit', opts = { '--dry-run' } }))
    local no_stages = not vim.tbl_contains(result, 'Changes to be committed:')
    local conflicts = vim.tbl_contains(result, 'You have unmerged paths.')
    local msg = ''

    if conflicts then
      msg = 'There are unmerged paths'
    elseif err > 2 or no_stages then
      msg = 'There is some problem. Will probably fail'
    end

    if msg ~= '' then
      util.notify(msg, HEADER, 3)
    end
  end)
end

---Create a table of git command and options
---@param editmsg string Path of the COMMIT_EDITMSG used for editing
---@param optspec? string Specified commit options. `amend` or `empty`
---@param msgspec? boolean Create commit without message
---@param commitmsg? table Commit-message
---@return table # Git command and options
local function create_gitcmd(editmsg, optspec, msgspec, commitmsg)
  local cmd = 'commit'
  local sign = _G.Mug.commit_gpg_sign and '--gpg-sign=' .. _G.Mug.commit_gpg_sign or '--gpg-sign'
  local pre = signature and { sign } or {}
  local mid = {}
  local post = { '--cleanup=strip', '--file=' .. editmsg }
  local opt = {
    amend = { '--amend' },
    empty = { '--allow-empty', '--only' },
    m = { '-m' },
  }
  local msg = {
    amend = { '--no-edit' },
    empty = { '--message=empty commit(created by mug)' },
    m = commitmsg,
  }

  if optspec then
    mid = opt[optspec]
  end

  if msgspec then
    post = msg[optspec]
  end

  return util.gitcmd({ noquotepath = true, cmd = cmd, opts = { pre, mid, post } })
end

---Write the edited contents to the COMMIT_EDITMSG in the repository and execute the command
---@param optspec? string Specified commit options. `amend` or `empty`
---@param msgspec? boolean Create commit without message
---@param commitmsg? table Commit-message
local function create_commit(optspec, msgspec, commitmsg)
  local root = util.pwd()
  local editmsg = root .. '/.git/COMMIT_EDITMSG'

  if not util.isRepo(HEADER) then
    return
  end

  local bufname = vim.api.nvim_buf_get_name(0)
  local is_commit_buffer = vim.startswith(bufname, COMMIT_BUFFER_URI)

  if is_commit_buffer then
    vim.api.nvim_command('write! ' .. editmsg)
  end

  job.async(function()
    local cmd = create_gitcmd(editmsg, optspec, msgspec, commitmsg)
    local stdout, err = job.await(cmd)
    signature = nil

    util.notify(stdout, HEADER, err, true)
    -- util.notify(vim.trim(table.concat(result, '\n')), HEADER, err, true)

    if err == 2 then
      if is_commit_buffer then
        if diffcached_bufnr[root] and vim.api.nvim_buf_is_loaded(diffcached_bufnr[root]) then
          vim.api.nvim_command('silent bwipeout ' .. diffcached_bufnr[root])
        end

        vim.api.nvim_command('silent bwipeout')
      end

      branch_stats(root, false)
    end
  end)
end

local function diffchaced_maps()
  local close_diff = function()
    vim.api.nvim_buf_set_option(0, 'buflisted', false)
    vim.api.nvim_command('silent close')
  end

  map.buf_set(true, 'n', { 'q', '<F6>', '<F7>' }, function()
    close_diff()
  end, 'Close buffer')
end

local function column_width()
  local get_win = vim.api.nvim_win_get_option
  local width = get_win(0, 'signcolumn') == 'yes' and 2 or 0
  local numwidth = 0
  width = width + tonumber(get_win(0, 'foldcolumn'))

  if get_win(0, 'number') or get_win(0, 'relativenumber') then
    numwidth = math.max(3, tonumber(get_win(0, 'numberwidth')))
    width = width + numwidth
  end

  return width, numwidth
end

---Show diff with staged-files
---@param vertical? boolean open buffer vertically
local function mug_diffcached(vertical)
  local pwd = util.pwd()
  local pos = { direction = 'horizontal', method = 'nvim_win_set_height' }
  local range = _G.Mug.commit_diffcached_height
  local column, numwidth = column_width()

  if vertical then
    pos = { direction = 'vertical', method = 'nvim_win_set_width' }
    range = math.max(1, vim.api.nvim_get_option('columns') - 73 - column)
  end

  if diffcached_bufnr[pwd] then
    local bufnr = diffcached_bufnr[pwd]

    if vim.api.nvim_buf_is_valid(bufnr) then
      if vim.fn.buflisted(bufnr) == 0 then
        vim.api.nvim_buf_set_option(bufnr, 'buflisted', true)
        vim.api.nvim_command('silent ' .. pos.direction .. ' botright sbuffer ' .. DIFFCACHED_URI)
        vim.api[pos.method](0, range)
      else
        vim.api.nvim_buf_set_option(bufnr, 'buflisted', false)
        vim.api.nvim_win_close(vim.fn.bufwinid(bufnr), {})
      end

      return
    end
  end

  job.async(function()
    local cmd = util.gitcmd({
      noquotepath = true,
      cmd = 'diff',
      opts = {
        '--patch',
        '--cached',
        '--no-color',
        '--no-ext-diff',
        '--compact-summary',
        '--stat=' .. range - numwidth,
      },
    })
    local result, err = job.await(cmd)

    if err > 3 then
      util.notify(result, HEADER, err)
      return
    end

    if #result == 0 then
      util.notify('No difference', HEADER, err)
      return
    end

    vim.api.nvim_command('silent ' .. pos.direction .. ' botright ' .. range .. 'new ' .. DIFFCACHED_URI)
    util.nofile(true, 'hide')
    vim.api.nvim_command('setfiletype git|set foldcolumn=0 signcolumn=no number')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, result)

    diffcached_bufnr[pwd] = vim.api.nvim_get_current_buf()
    diffchaced_maps()
  end)
end

---@param merged string For merged commit
---@param callback function|nil user-settings to load later
local function open_buffer_post(merged, callback)
  ---Git-commit
  vim.api.nvim_buf_create_user_command(0, 'C', function()
    local option = merged == 'merged' and 'amend' or nil
    create_commit(option)
  end, {})

  ---Git-commit-amend
  vim.api.nvim_buf_create_user_command(0, 'CA', function()
    create_commit('amend')
  end, {})

  ---Git-commit-allow-empty
  vim.api.nvim_buf_create_user_command(0, 'CE', function()
    create_commit('empty')
  end, {})

  ---Toggle spellcheck
  map.buf_set(true, 'n', '^', '<Cmd>setlocal spell!<CR>', 'Toggle spellcheck')

  ---Insert datetime
  map.buf_set(true, { 'n', 'i' }, '<F5>', function()
    local time = os.date(_G.Mug.strftime)
    vim.api.nvim_put({ time }, 'c', false, true)
  end, 'Insert DateTime')

  ---Open diffchaced-window horizontally
  map.buf_set(true, 'n', '<F6>', function()
    mug_diffcached()
  end, 'Open diff-buffer horizontally')

  ---Open diffchaced-window vertically
  map.buf_set(true, 'n', '<F7>', function()
    mug_diffcached(true)
  end, 'Open diff-buffer horizontally')

  ---Append
  map.buf_set(true, 'n', '<F8>', function()
    local msg = vim.fn.systemlist(util.gitcmd({ cmd = 'log', opts = { '-1', '--oneline', '--format=%B' } }))
    vim.api.nvim_buf_set_text(0, 0, 0, 0, 0, msg)
  end, 'Expand head commit message')

  if type(callback) == 'function' then
    callback()
  end
end

---Preparation before opening commit-buffer
---@param merged string For merged commit
---@param notation string Commit-message prefix notation
local function setup_commit_buffer(merged, notation)
  vim.api.nvim_set_var('no_gitcommit_commands', true)
  vim.api.nvim_buf_set_option(0, 'filetype', 'gitcommit')
  util.nofile(false, 'hide')
  vim.opt_local.signcolumn = 'no'
  vim.opt_local.spell = true
  vim.opt_local.spellfile = TEMPLATE_DIR .. 'en.utf-8.add'
  vim.opt_local.spellcapcheck = ''
  vim.opt_local.spelllang:append({ 'cjk' })
  vim.api.nvim_command('clearjumps')

  local additional_settings = setup_abbrev(notation)
  open_buffer_post(merged, additional_settings)
end

---Open commit-edit buffer
---@param merged string For merged commit
M.commit_buffer = function(merged)
  local pwd = util.pwd()
  local filename = COMMIT_BUFFER_URI .. '/' .. vim.fs.basename(pwd)
  local notation = _G.Mug.commit_notation
  local loaded_buffer = vim.fn.bufexists(filename) == 1
  local diffnr = diffcached_bufnr[pwd]

  if diffnr then
    diffcached_bufnr[pwd] = nil

    if vim.api.nvim_buf_is_valid(diffnr) then
      vim.api.nvim_command('silent bwipeout ' .. diffnr)
    end
  end

  branch_stats(pwd, false)

  local branch = vim.api.nvim_buf_get_var(0, 'mug_branch_name')
  local branch_info = vim.api.nvim_buf_get_var(0, 'mug_branch_info')
  local stats = vim.api.nvim_buf_get_var(0, 'mug_branch_stats')
  local staged = stats and stats.s or 0

  vim.api.nvim_command('silent -tabnew ' .. filename)

  ---Memorize the repository information of the execution-buffer
  vim.api.nvim_buf_set_var(0, 'mug_branch_name', branch)
  vim.api.nvim_buf_set_var(0, 'mug_branch_info', branch_info)
  vim.api.nvim_buf_set_var(0, 'mug_branch_stats', stats)

  if loaded_buffer then
    return
  end

  if notation ~= 'none' and not util.file_exist(TEMPLATE_DIR .. notation) then
    util.notify(notation .. ' is not exist', HEADER, 3)
    notation = 'none'
  end

  if not merged then
    ---Expand unique template on buffer
    vim.api.nvim_command('silent keepalt 0r ++edit ' .. TEMPLATE_DIR .. notation)
  else
    local merge_msg = pwd .. '/.git/MERGE_MSG'

    if util.file_exist(merge_msg) then
      vim.api.nvim_command('silent keepalt 0r ++edit ' .. TEMPLATE_DIR .. notation)
      vim.api.nvim_command('silent 0d _|keepalt 0r ++edit ' .. merge_msg)
    else
      local commit_msg = vim.fn.systemlist(util.gitcmd({ cmd = 'log', opts = { '-1', '--oneline', '--format=%B' } }))

      vim.api.nvim_command('silent keepalt 0r ++edit ' .. TEMPLATE_DIR .. notation)
      vim.api.nvim_buf_set_text(0, 0, 0, 0, 0, commit_msg)
    end
  end

  setup_commit_buffer(merged, notation)

  if not merged then
    async_warning(staged)
  end
end

local function get_git_log()
  local wd = util.pwd()
  local format = '%h %as <%cn> %d%s'
  local max_log = 50
  local cmd = util.gitcmd({
    wd = wd,
    noquotepath = true,
    cmd = 'log',
    opts = { '-n' .. max_log, '--no-color', '--format=' .. format },
  })
  return vim.fn.systemlist(cmd)
end

local function fixup_buffer_attach()
  vim.api.nvim_command([[syn match MugLogHash "^\s\?\w\{7}" display oneline]])
  vim.api.nvim_command([[syn match MugLogDate "\d\{4}-\d\d-\d\d" display oneline]])
  vim.api.nvim_command([[syn match MugLogOwner "<\w\+>" oneline]])
  vim.api.nvim_command([[syn match MugLogHead "(HEAD\s->\s.\+)" oneline]])

  vim.keymap.set('n', '<CR>', function()
    local hash = vim.api.nvim_get_current_line():sub(1, 7)
    vim.api.nvim_command('bwipeout|stopinsert!')

    local log = vim.fn.systemlist({ 'git', 'commit', '--fixup', hash })

    if vim.v.shell_error == 1 then
      util.notify(log, HEADER, 3)
      return
    end

    -- if util.interactive('Shall we run rebase?', HEADER, 'n') then
    --   print('Not yet done!')
    -- else
    vim.api.nvim_command('redraw|echo')
    -- end
  end, { buffer = true, silent = true })
end

---User command "MugCommit"
local function mug_commit(name)
  vim.api.nvim_create_user_command(NAMESPACE .. name, function(opts)
    signature = name == 'Sign'

    if float.focus(float_handle) then
      return
    end

    if not util.isRepo(HEADER) then
      return
    end

    if opts.bang then
      local log = vim.fn.system({ 'git', '-C', util.pwd(), 'add', '.' })

      if vim.v.shell_error == 1 then
        util.notify(log, HEADER, 3)
        return
      end
    end

    if opts.args == 'amend' then
      create_commit('amend', true)
      return
    end

    if opts.args == 'empty' then
      create_commit('empty', true)
      return
    end

    if opts.args == 'fixup' then
      branch_stats()

      if vim.b.mug_branch_stats.s == 0 then
        util.notify('Index is clean', HEADER, 3)
        return
      end

      float_handle = float.open({
        title = NAMESPACE .. ' Fixup',
        height = 3,
        width = 0.7,
        border = 'single',
        contents = get_git_log,
        post = fixup_buffer_attach,
      }).handle
      return
    end

    if opts.fargs[1] == 'm' then
      if #opts.fargs == 1 then
        util.notify('Argument "m" requires commit-message', HEADER, 3)
        return
      end

      local msg_tbl = vim.deepcopy(opts.fargs)
      table.remove(msg_tbl, 1)
      local msg = table.concat(msg_tbl, ' ')

      create_commit('m', true, { msg })
      return
    end

    M.commit_buffer()
  end, {
    nargs = '*',
    bang = true,
    complete = function(a, l, _)
      local input = vim.split(l, ' ', { plain = true })
      local list = input[1]:find('!', 1, true) and { 'amend', 'fixup' } or { 'amend', 'fixup', 'empty' }

      if input[2] ~= 'm' then
        return comp.filter(a, l, list)
      else
        return comp.filter(a, l, comp.commit_prefix())
      end
    end,
  })
end

mug_commit('')
mug_commit('Sign')

return M
