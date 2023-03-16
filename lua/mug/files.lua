local util = require('mug.module.util')
local job = require('mug.module.job')
local branch_stats = require('mug.branch').branch_stats

local HEADER = 'mug/files'

---@param wd string working directory
---@param oldname string Source
---@param newname string Destination
---@param force boolean Force move
local function do_move(wd, oldname, newname, force)
  local cmd = 'mv'
  local mid = { [true] = { '--force' }, [false] = { '' } }
  local post = { oldname, newname }
  local mv_cmd = util.gitcmd({ wd = wd, cmd = cmd, opts = { mid[force], post } })

  job.async(function()
    local result, err = job.await(mv_cmd)

    if err > 2 then
      util.notify(result, HEADER, err, false)
    else
      branch_stats()

      local old_bufnr = vim.api.nvim_get_current_buf()

      vim.api.nvim_command('edit! ' .. wd .. '/' .. newname)
      vim.api.nvim_command('silent bwipeout! ' .. old_bufnr)
    end
  end)
end

---@param wd string Working directory
---@param name string Remove target
---@param force boolean Whether to delete
local function do_remove(wd, name, force)
  local cmd = 'rm'
  local mid = { [true] = { '--force' }, [false] = { '--cached' } }
  local post = { name }
  local rm_cmd = util.gitcmd({ wd = wd, cmd = cmd, opts = { mid[force], post } })

  job.async(function()
    local result, err = job.await(rm_cmd)

    if err > 2 then
      util.notify(result, HEADER, err, false)
    else
      branch_stats()

      local msg = force and 'Delete ' or 'Remove index '
      util.notify(msg .. name, HEADER, err, false)
    end
  end)
end

local function prepare()
  if not vim.bo.modified then
    return true
  end

  local choice = util.confirm('File has been modified', '&Stop\n&Continue\n&Write and continue', 1, HEADER)

  if choice == 0 then
    vim.api.nvim_command('redraw|echo')

    return false
  elseif choice == 3 then
    vim.api.nvim_command('write')

    return true
  end
end

---@param wd string Working directory
---@param opts table User-command arguments
---@return boolean? # Whether to continue the operation
local function path_verify(wd, opts)
  local pathspec = opts.args

  if pathspec:find('[\\/]') then
    pathspec = pathspec:gsub('^%.?[\\/]?(.+)[\\/].+', '%1')

    if vim.fn.isdirectory(wd .. '/' .. pathspec) == 0 then
      local choice = util.confirm(pathspec .. ' does not exist', '&Create and continue\n&Stop operation', 1, HEADER)
      if choice == 2 then
        vim.api.nvim_command('redraw|echo')

        return false
      end

      vim.fn.mkdir(pathspec, 'p')
    end
  end

  if not opts.bang and util.file_exist(opts.args) then
    util.notify(opts.args .. ' is exist', HEADER, 3)

    return false
  end

  return true
end

vim.api.nvim_create_user_command('MugFileRename', function(opts)
  if not prepare() then
    return
  end

  if opts.args:find('[\\/]') then
    util.notify('Moving to other directory is not allowed. Use MugFileMove', HEADER, 3)
    return
  end

  local wd = util.dirpath('/')

  if not path_verify(wd, opts) then
    return
  end

  local name = vim.fn.expand('%:t')

  do_move(wd, name, opts.args, opts.bang)
end, { nargs = 1, bang = true })

vim.api.nvim_create_user_command('MugFileMove', function(opts)
  if not prepare() then
    return
  end

  local wd = util.dirpath('/')

  if not path_verify(wd, opts) then
    return
  end

  local path = vim.fn.expand('%')

  do_move(wd, path, opts.args, opts.bang)
end, { nargs = 1, bang = true, complete = 'dir' })

vim.api.nvim_create_user_command('MugFileDelete', function(opts)
  local wd = util.dirpath('/')
  local name = vim.fn.expand('%:t')

  do_remove(wd, name, opts.bang)
end, { nargs = 0, bang = true })
