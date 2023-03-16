local util = require('mug.module.util')
local job = require('mug.module.job')
local set_ws_root = require('mug.workspace').set_workspace_root

local HEADER = 'mug/mkrepo'

---@class Mug
---@field commit_initial_message string Message of initial commit
---@field remote_url string Remote repository url
_G.Mug._def('commit_initial_message', 'Initial commit', true)

local function do_mkrepo(root, compared, contain)
  local log, result, err = {}, {}, 2
  local function log_table(title)
    table.insert(log, title .. table.concat(result, ''))
  end
  local function notify()
    util.notify(log, HEADER, err, true)
  end

  job.async(function()
    result, err = job.await(util.gitcmd({ noquotepath = true, cmd = 'init', opts = { root } }))

    if err == 2 then
      log_table('init > success: ')
    else
      log_table('init > ')
      return
    end

    if not _G.Mug.remote_url then
      log_table('remote-add > failure: Mug.remote_url not set')
    else
      local url = _G.Mug.remote_url .. '/' .. vim.fs.basename(root) .. '.git'
      result, err = job.await(util.gitcmd({ wd = root, cmd = 'remote', opts = { 'add', 'origin', url } }))

      if err == 2 then
        table.insert(log, 'remote-add > success: origin ' .. url)
      else
        log_table('remote-add > ')
      end
    end

    if contain then
      result, err = job.await(util.gitcmd({ wd = root, cmd = 'add', opts = { '.' } }))

      if err > 2 then
        log_table('add > ')
        return
      end
    end

    if _G.Mug.commit_initial_message == nil or _G.Mug.commit_initial_message == '' then
      _G.Mug._ow('commit_initial_message', 'Initial commit', true)
    end

    result, err = job.await(
      util.gitcmd({ wd = root, cmd = 'commit', opts = { '--allow-empty', '-m' .. _G.Mug.commit_initial_message } })
    )

    if err == 2 then
      log_table('commit > success: ')

      if compared == 'differ' then
        local ok = util.interactive("Change 'lcd' to the repository path you created?", HEADER, 'y')

        if ok then
          vim.api.nvim_command('lcd ' .. root)
        end
      end
    else
      log_table('commit > ')
    end

    set_ws_root()
  end, notify)
end

vim.api.nvim_create_user_command('MugMkrepo', function(opts)
  local root = util.dirpath('/')
  local repo_root = root
  local pathspec = util.normalize(opts.args, '/'):gsub('/$', '')

  if pathspec ~= '' then
    repo_root = pathspec:find('/', 1, true) and pathspec or root .. '/' .. pathspec
  end

  local compared = root == repo_root and 'same' or 'differ'
  root, pathspec = nil, nil

  if vim.fn.isdirectory(repo_root .. '/.git') ~= 0 then
    return util.notify('Already exist', HEADER, 3)
  end

  local ok = util.interactive('Create a repository in ' .. repo_root .. '?', HEADER, 'y')

  if not ok then
    return vim.api.nvim_command('redraw|echo')
  end

  do_mkrepo(repo_root, compared, opts.bang)
end, { nargs = '?', bang = true })
