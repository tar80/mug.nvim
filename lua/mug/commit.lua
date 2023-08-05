local util = require('mug.module.util')
local float = require('mug.module.float')
local job = require('mug.module.job')
local comp = require('mug.module.comp')
local branch = require('mug.branch')
local patch = require('mug.patch')
local rebase = require('mug.rebase')

---@class commit
---@field commit_buffer function Open unique commit-edit buffer
local M = {}
local HEADER, NAMESPACE = 'mug/commit', 'MugCommit'
local COMMIT_BUFFER_URI = 'Mug://commit'
local TEMPLATE_DIR = _G.Mug.root .. '/lua/mug/template/'

---@type boolean|nil Put gpg signature
local signature
local float_handle = 0

---@class Mug
---@field strftime string Date-time formats. that can be inserted when editing a commit-message
---@field commit_notation string Notation used to prefix commit-message
---@field commit_gpg_sign string Specify gpg sign keyid
_G.Mug._def('strftime', '%c', true)
_G.Mug._def('commit_notation', 'none', true)

---Setup commit-edit own abbreviations
---@param notation string Prefix notation format
---@return function|nil # Functions describing user-added settings
local function unique_setting(notation)
  local setting_filepath = TEMPLATE_DIR .. notation .. '.lua'

  if not util.file_exist(setting_filepath) then
    util.notify('Could not get abbreviations. "template/' .. notation .. '.lua" is not exist', HEADER, 3)
    return nil
  end

  ---@module 'template'
  local template = require('mug.template.' .. notation)

  if notation ~= 'none' then
    for k, v in pairs(template.abbrev) do
      vim.api.nvim_command('inorea <buffer> ' .. k .. ' ' .. v)
    end
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
    amend_sign = { '--amend', sign },
    empty = { '--allow-empty', '--only' },
    m = { '-m' },
    sign = { sign },
  }
  local msg = {
    amend = { '--no-edit' },
    empty = { '--message=empty commit(created by mug)' },
    m = commitmsg,
  }

  if optspec then
    mid = opt[optspec]

    if optspec == 'sign' or optspec == 'amend_sign' then
      pre = {}
    end
  end

  if msgspec then
    post = msg[optspec]
  end

  return util.gitcmd({ noquotepath = true, cmd = cmd, opts = { pre, mid, post } })
end

---Write the edited contents to the COMMIT_EDITMSG in the repository and execute the command
---@param optspec? string Specified commit options
---@param msgspec? boolean Create commit without message
---@param commitmsg? table Commit-message
local function create_commit(optspec, msgspec, commitmsg)
  local root = util.pwd()
  local editmsg = root .. '/.git/COMMIT_EDITMSG'

  if not util.is_repo(HEADER) then
    return
  end

  local bufname = vim.api.nvim_buf_get_name(0)
  local is_commit_buffer = vim.startswith(bufname, COMMIT_BUFFER_URI)

  if is_commit_buffer then
    vim.api.nvim_command('silent write! ' .. editmsg)
  end

  job.async(function()
    local cmdline = create_gitcmd(editmsg, optspec, msgspec, commitmsg)
    local stdout, err = job.await(cmdline)
    signature = nil

    util.notify(stdout, HEADER, err, true)

    if err == 2 then
      if is_commit_buffer then
        patch.close()
        vim.api.nvim_command('silent bwipeout')
      end

      branch.branch_stats(root, false)
    end
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

  ---Git-commit-sign
  vim.api.nvim_buf_create_user_command(0, 'CS', function()
    local option = merged == 'merged' and 'amend_sign' or 'sign'
    create_commit(option)
  end, {})

  ---Git-commit-amend
  vim.api.nvim_buf_create_user_command(0, 'CSA', function()
    create_commit('amend_sign')
  end, {})

  ---Git-commit-allow-empty
  vim.api.nvim_buf_create_user_command(0, 'CE', function()
    create_commit('empty')
  end, {})

  if type(callback) == 'function' then
    callback(merged)
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

  local additional_settings = unique_setting(notation)
  open_buffer_post(merged, additional_settings)
end

---Open commit-edit buffer
---@param merged string For merged commit
M.commit_buffer = function(merged)
  local pwd = util.pwd()
  local filename = COMMIT_BUFFER_URI .. '/' .. vim.fs.basename(pwd)
  local notation = _G.Mug.commit_notation
  local loaded_buffer = vim.fn.bufexists(filename) == 1

  patch.close()
  branch.branch_stats(pwd, false)

  local branch_name = vim.api.nvim_buf_get_var(0, 'mug_branch_name')
  local branch_info = vim.api.nvim_buf_get_var(0, 'mug_branch_info')
  local branch_stats = vim.api.nvim_buf_get_var(0, 'mug_branch_stats')
  local staged = branch_stats and branch_stats.s or 0

  vim.api.nvim_command('silent -tabnew ' .. filename)

  ---Memorize the repository information of the execution-buffer
  vim.api.nvim_buf_set_var(0, 'mug_branch_name', branch_name)
  vim.api.nvim_buf_set_var(0, 'mug_branch_info', branch_info)
  vim.api.nvim_buf_set_var(0, 'mug_branch_stats', branch_stats)

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

---User command "MugCommit"
local function mug_commit(name)
  vim.api.nvim_create_user_command(NAMESPACE .. name, function(opts)
    signature = name == 'Sign'

    if float.focus(float_handle) then
      return
    end

    if not util.has_repo(HEADER) then
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

    if opts.args == 'rebase' then
      branch.branch_stats()

      if vim.b.mug_branch_stats.s == 0 then
        util.notify('Index is clean', HEADER, 3)
        return
      end

      rebase.rebase_i(name, vim.b.mug_branch_stats, true, { 'HEAD' })
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
      local list = input[1]:find('!', 1, true) and { 'amend', 'rebase' } or { 'amend', 'rebase', 'empty' }

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
