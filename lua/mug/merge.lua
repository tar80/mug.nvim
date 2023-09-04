local util = require('mug.module.util')
local comp = require('mug.module.comp')
local job = require('mug.module.job')
local branch_name = require('mug.branch').branch_name
local commit_buffer = require('mug.commit').commit_buffer

local HEADER, NAMESPACE = 'mug/merge', 'MugMerge'
local comp_on_process = { '--abort', '--continue', '--quit' }

---Do git fetch
---@param command string[] command line
local function do_fetch(command)
  local stdout, err = {}, 2

  local function notify()
    if #stdout == 0 and err == 2 then
      stdout = { 'Success' }
    end

    table.remove(stdout, 1)
    util.notify(stdout, HEADER, err, false)
  end

  job.async(function()
    stdout, err = job.await(command)

    branch_name(util.pwd())
  end, notify)
end

---Do git merge
---@param ff string Fast-forward or not. `""` or `"FF"`
---@param pwd string Current directory path
---@param command table Git merge options
local function do_merge(ff, pwd, command)
  local stdout, err = {}, 2

  local function notify()
    local multi = true

    if #stdout == 0 and err == 2 then
      if vim.tbl_contains(command, '--abort') then
        local filepath = util.filepath()

        if filepath and util.interactive('Aborted. Reload current buffer?', HEADER, 'n') then
          vim.cmd.edit({filepath, bang = true})
        end

        return
      end

      stdout = { 'Success' }
      multi = false
    end

    util.notify(stdout, HEADER, err, multi)
  end

  job.async(function()
    local choice
    stdout, err = job.await(command)

    if err == 2 then
      branch_name(pwd)

      if ff == '' and #stdout > 0 then
        if vim.b.mug_branch_stats.u > 0 and package.loaded['mug.conflict'] then
          choice = util.confirm(stdout, 'Open loclist\nAbort merging\nCancel', 1, HEADER)

          if choice == 1 then
            require('mug.conflict').loclist()
          elseif choice == 2 then
            stdout, err = job.await(util.gitcmd({ cmd = 'merge', opts = { '--abort' } }))
            branch_name(pwd)
          end

          return nil
        elseif stdout[1] ~= 'Already up to date.' then
          choice = util.confirm('Merge completed. Edit commit-message?', 'Yes\nNo', 1, HEADER)

          if choice == 1 then
            commit_buffer('merged')
          end

          return nil
        end
      end
    end

    notify()
  end)
end

local function complist(_, l)
  local comp_merge = {
    '--edit',
    '--file=',
    '--cleanup=',
    '--gpq-sign=',
    '--log',
    '--signoff',
    '--squash',
    '--strategy=',
    '--strategy-option=',
    '--verify-signatures',
    '--summary',
    '--quiet',
    '--verbose',
    '--autostash',
    '--allow-unrelated-histories',
    '--rerere-autoupdate',
    '--no-verify',
    '--no-overwrite-ignore',
  }
  local comp_force = { '--strategy-option=ours', '--strategy-option=theirs' }

  if vim.b.mug_branch_info ~= '' and vim.b.mug_branch_info ~= 'Detached' then
    return comp_on_process
  end

  local input = vim.split(l, ' ', { plain = true })

  if #input <= 2 then
    return comp.branches()
  end

  if l:find('%w+!%s') then
    return comp_force
  end

  return comp_merge
end

---Do the MugMerge
---@param name string Suffix of the MugMerge. `""`|`"FF"`
local function mug_merge(name)
  vim.api.nvim_create_user_command(NAMESPACE .. name, function(opts)
    local cmdspec = name == '' and '--no-ff' or '--ff-only'
    local ok, pwd = util.has_repo(HEADER)

    if not ok then
      return
    end

    local merge_msg = string.format('%s/.git/MERGE_MSG', pwd)

    for _, v in ipairs(comp_on_process) do
      if opts.args:find(v) then
        if not util.file_exist(merge_msg) then
          util.notify('There is no merge in progress', HEADER, 3)
          return
        end

        if v == '--continue' then
          commit_buffer('continue')
          return
        end

        cmdspec = ''
        break
      end
    end

    do_merge(
      name,
      pwd,
      util.gitcmd({
        cmd = 'merge',
        cfg = 'merge.conflictStyle=diff3',
        noquotepath = false,
        opts = { cmdspec, opts.fargs },
      })
    )
  end, {
    nargs = '+',
    bang = true,
    complete = function(a, l, _)
      return comp.filter(a, l, complist(a, l))
    end,
  })
end

vim.api.nvim_create_user_command(NAMESPACE .. 'To', function(opts)
  if not util.has_repo(HEADER) then
    return
  end

  local force = opts.bang and '--force' or ''
  local branchspec = string.format('%s:%s', vim.b.mug_branch_name, opts.args)

  do_fetch(util.gitcmd({ cmd = 'fetch', noquotepath = false, opts = { force, '.', branchspec } }))
end, {
  nargs = 1,
  bang = true,
  complete = function(a, l, _)
    return comp.filter(a, l, comp.branches())
  end,
})

mug_merge('')
mug_merge('FF')
