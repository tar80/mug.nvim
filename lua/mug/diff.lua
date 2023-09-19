local comp = require('mug.module.comp')
local job = require('mug.module.job')
local map = require('mug.module.map')
local tbl = require('mug.module.table')
local util = require('mug.module.util')

local HEADER = 'mug/diff'
local DIFF_URI = 'mug://cat-file/'

---@class Mug
---@field diff_position string Position of diff window

---Apply MugDiff specification to buffer
---@param ... string Buffer number
local function on_attach(...)
  for _, bufnr in ipairs({ ... }) do
    map.buf_set(bufnr, 'x', 'do', ':diffget<CR>', 'Get selection diff')
    map.buf_set(bufnr, 'x', 'dp', ':diffput<CR>', 'Put selection diff')
    map.buf_set(bufnr, 'x', 'dd', 'd', 'Delete selection range')
    map.buf_set(bufnr, { 'n', 'x' }, 'du', '<Cmd>diffupdate<CR>', 'Update diff comparison status')
  end
end

---Remove MugDiff specification from buffer
---@param bufnr integer Buffer number
---@param diffnr integer Diff buffer number
local function on_detach(bufnr, diffnr)
  local exist = vim.api.nvim_get_autocmds({ group = 'mug', event = 'BufWipeout', buffer = diffnr })

  if not vim.tbl_isempty(exist) then
    return
  end

  vim.api.nvim_create_autocmd({ 'BufWipeout' }, {
    group = 'mug',
    once = true,
    buffer = diffnr,
    callback = function()
      local bufs = vim.api.nvim_list_bufs()

      for _, v in ipairs(bufs) do
        if not (v == diffnr) and vim.api.nvim_buf_get_name(v):find(DIFF_URI, 1, true) then
          return
        end
      end

      map.buf_del(bufnr, 'x', { 'do', 'dp', 'dd' })
      map.buf_del(bufnr, { 'x', 'n' }, 'du')
    end,
    desc = 'Delete keymaps for 2-way-diff',
  })
end

---Existence check of pathspec
---@param arg string Git cat-file pathspec
---@param options table Diff command arguments
---@return table|nil # {`pos`: string, `treeish`: string, `path`: stirng}
local function catfile(arg, options)
  if util.file_exist(vim.fn.expand(arg)) then
    options.path = arg

    return options
  end

  util.notify('Specified file does not exist', HEADER, 3)

  return nil
end

---Check and set tree-ish
---@param arg string Git cat-file tree-ish
---@param options table Diff command arguments
---@return table # {`pos`: string, `treeish`: string, `path`: stirng}
local function treeish(arg, options)
  if util.file_exist(vim.fn.expand(arg)) then
    options.path = arg
  else
    options.treeish = arg
  end

  return options
end

---Ckech and set buffer position
---@param arg string Diff buffer position
---@param options table Diff command arguments
---@return table # {`pos`: string, `treeish`: string, `path`: stirng}
local function position(arg, options)
  local pos = arg:lower():gsub('%w+', tbl.positions)

  if arg == pos then
    treeish(arg, options)
  else
    options.pos = pos
  end

  return options
end

---Determine buffer position
---@return string # bufffer position
local function window_position()
  local userspec = tbl.positions[_G.Mug.diff_position]

  if not userspec then
    userspec = vim.go.diffopt:find('vertical', 1, true) and 'vertical ' or ''
  end

  return userspec
end

---Normalize path and adjust root
---@param path string Comparison file path
---@return string # Adjusted comparison file path
---@return boolean # The comparison target is the same file
local function adjust_path(path)
  local current_file = util.filepath('/')
  local root = vim.fs.find('.git', { type = 'directory', upward = true })[1]
  root = root:gsub('/.git', '')

  local path_ = vim.fn.expand(path)

  if vim.fn.getftype(path_) == 'link' then
    ---NOTE: uv.fs_realpath() changes the path even when it is not a simlink
    --- resolve() returns the original path as is
    path_ = vim.fn.resolve(path_)
  end

  path_ = util.conv_slash(path_)
  path_ = (function()
    if path_:find(root, 1, true) then
      return path_:sub(#root + 2)
    else
      local cwd = util.pwd()
      if cwd ~= root then
        return string.format('%s/%s', cwd:sub(#root + 2), path_)
      end
      return path_
    end
  end)()

  local is_same = path_ == current_file

  return path_, is_same
end

---Compare files
---@param name string Diff command name
---@param ... string Diff command arguments
local function let_compare(name, ...)
  local args = { ... }
  local win_pos = window_position()
  local options = { pos = win_pos, treeish = '', path = '%' }
  local func = { [1] = position, [2] = treeish, [3] = catfile }
  local result

  for i = 1, #args do
    result = func[i](args[i], options)

    if not result then
      return
    end
  end

  job.async(function()
    ---@type string|string[], integer
    local stdout, loglevel
    local branchspec = options.treeish:gsub('^origin/', '')

    if name == 'FetchRemote' then
      if branchspec == '' then
        branchspec = vim.b.mug_branch_name
      end

      options.treeish = string.format('origin/%s', branchspec)
      loglevel, stdout = job.await(util.gitcmd({ cmd = 'branch', opts = { '-r', '--list', options.treeish } }))

      if stdout == '' then
        local msg = string.format('Remote %s is not exist', options.treeish)
        util.notify(msg, HEADER, 3)
        return
      end

      loglevel, stdout = job.await(util.gitcmd({ cmd = 'fetch', opts = { 'origin', branchspec } }))

      if stdout:find('fatal:', 1, true) then
        local msg = string.format('Cannot fetch %s', options.treeish)
        util.notify(msg, HEADER, 2)
        return
      end
    end

    local pathspec, same_file = adjust_path(options.path)

    if same_file then
      loglevel, stdout = job.await(util.gitcmd({ cmd = 'diff', opts = { '--no-color', branchspec, '--', pathspec } }))

      if #stdout == 0 then
        util.notify('No difference', HEADER, 2)
        return
      end
    end

    local refs = string.format('%s:%s', options.treeish, pathspec)
    local filename = string.format('%s%s', DIFF_URI, refs)
    loglevel, stdout = job.await_job(util.gitcmd({ noquotepath = true, cmd = 'cat-file', opts = { '-p', refs } }))

    if loglevel > 2 then
      util.notify(stdout[1], HEADER, 3)
      return
    end

    local bufnr = vim.api.nvim_get_current_buf()
    local handle = vim.api.nvim_get_current_win()
    vim.cmd(string.format('silent %snew %s', options.pos, filename))

    local diffnr = vim.api.nvim_get_current_buf()
    util.nofile(diffnr, true, 'wipe', 'nofile')

    ---remove blank line
    table.remove(stdout)
    vim.api.nvim_buf_set_lines(diffnr, 0, -1, false, stdout)
    vim.cmd.diffthis()
    vim.api.nvim_set_current_win(handle)
    vim.cmd.diffthis()

    on_attach(bufnr)
    on_attach(diffnr)
    on_detach(bufnr, diffnr)
  end)
end

---":MugDiffXxx [<position>] [<tree-ish>] [<filespec>]"
---Execute git cat-file against the current-buffer and compare differences
---@param name string Append to command name
local mug_diff = function(name)
  vim.api.nvim_create_user_command('MugDiff' .. name, function(opts)
    if #opts.fargs > 3 then
      util.notify('There are many arguments. All you need is [<position>] [<tree-ish>] [<filespec>]', HEADER, 3)
      return
    end

    if not util.has_repo(HEADER) then
      return
    end

    let_compare(name, unpack(opts.fargs))
  end, {
    nargs = '*',
    complete = function(a, l, _)
      local input = #vim.split(l, ' ', { plain = true })

      if input > 1 then
        return input == 2 and comp.filter(a, l, { 'top', 'bottom', 'left', 'right' })
          or comp.filter(a, l, comp.branches())
      else
        return {}
      end
    end,
  })
end

mug_diff('')
mug_diff('FetchRemote')
