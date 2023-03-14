local util = require('mug.module.util')
local comp = require('mug.module.comp')
local tbl = require('mug.module.table')
local map = require('mug.module.map')
local job = require('mug.module.job')

local HEADER = 'mug/diff'
local DIFF_URI = 'mug:/cat-file/'

---@class Mug
---@field diff_position string Position of diff window

local function on_attach()
  map.buf_set(true, 'x', 'do', ':diffget<CR>', 'Get selection diff')
  map.buf_set(true, 'x', 'dp', ':diffput<CR>', 'Put selection diff')
  map.buf_set(true, 'x', 'dd', 'd', 'Delete selection range')
  map.buf_set(true, { 'n', 'x' }, 'du', '<Cmd>diffupdate<CR>', 'Update diff comparison status')
end

---@param bufnr number Buffer number
---@param diffnr number Diff buffer number
local function on_detach(bufnr, diffnr)
  vim.api.nvim_create_autocmd({ 'BufWipeout' }, {
    group = 'mug',
    once = true,
    buffer = diffnr,
    callback = function()
      map.buf_del(bufnr, 'x', { 'do', 'dp', 'dd' })
      map.buf_del(bufnr, { 'x', 'n' }, 'du')
    end,
    desc = 'Delete keymaps for 2-way-diff',
  })
end

---@param arg string Git cat-file pathspec
---@param options table Diff command arguments
---@return table|nil # {pos: string, treeish: string, path: stirng}
local function catfile(arg, options)
  if util.file_exist(vim.fn.expand(arg)) then
    options.path = arg

    return options
  end

  util.notify('Specified file does not exist', HEADER, 3)

  return nil
end

---@param arg string Git cat-file treeish
---@param options table Diff command arguments
---@return table # {pos: string, treeish: string, path: stirng}
local function treeish(arg, options)
  if util.file_exist(vim.fn.expand(arg)) then
    options.path = arg
  else
    options.treeish = arg
  end

  return options
end

---@param arg string Diff buffer position
---@param options table Diff command arguments
---@return table # {pos: string, treeish: string, path: stirng}
local function position(arg, options)
  local pos = arg:lower():gsub('%w+', tbl.positions)

  if arg == pos then
    treeish(arg, options)
  else
    options.pos = pos
  end

  return options
end

local function window_position()
  local userspec = tbl.positions[_G.Mug.diff_position]

  if not userspec then
    userspec = vim.go.diffopt:find('vertical', 1, true) and 'vertical ' or ''
  end

  return userspec
end

---@param path string Comparison file path
---@return string # Adjusted comparison file path
---@return boolean # The comparison target is the same file
local function adjust_path(path)
  local cwd =  util.pwd()
  local current_file = util.filepath('/')
  local pathspec = vim.loop.fs_realpath(vim.fn.expand(path)):gsub('\\', '/')
  pathspec = pathspec:find(cwd, 1, true) and pathspec:sub(#cwd + 2) or pathspec
  local is_same = pathspec == current_file

  return pathspec, is_same
end

---@param name string Diff command name
---@param ... string Diff command arguments
local function let_compare(name, ...)
  if not util.belongtoRepo(HEADER) then
    return
  end

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
    local stdout, err
    local branchspec = options.treeish:gsub('^origin/', '')

    if name == 'FetchRemote' then
      if branchspec == '' then
        branchspec = vim.b.mug_branch_name
      end

      options.treeish = 'origin/' .. branchspec

      stdout, err = job.await(util.gitcmd({ cmd = 'branch', opts = { '-r', '--list', options.treeish } }))

      if #stdout == 0 then
        util.notify('Remote ' .. options.treeish .. ' is not exist', HEADER, 3)
        return
      end

      stdout, _ = job.await(util.gitcmd({ cmd = 'fetch', opts = { 'origin', branchspec } }))

      if stdout[1]:find('fatal:', 1, true) then
        util.notify('Cannot fetch ' .. options.treeish, HEADER, 2)
        return
      end
    end

    local pathspec, same_file = adjust_path(options.path)

    if same_file then
      stdout, _ = job.await(util.gitcmd({ cmd = 'diff', opts = { '--no-color', branchspec, '--', pathspec } }))

      if #stdout == 0 then
        util.notify('No difference', HEADER, 2)
        return
      end
    end

    local refs = options.treeish .. ':' .. pathspec
    local filename = DIFF_URI .. refs

    stdout, err = job.await(util.gitcmd({ noquotepath = true, cmd = 'cat-file', opts = { '-p', refs } }))

    if err > 2 then
      util.notify(stdout[1], HEADER, 3)
      return
    end

    local bufnr = vim.api.nvim_get_current_buf()
    local handle = vim.api.nvim_get_current_win()

    on_attach()

    vim.api.nvim_command('silent ' .. options.pos .. 'new ' .. filename)
    local diffnr = vim.api.nvim_get_current_buf()

    util.nofile(true, 'wipe')
    vim.api.nvim_buf_set_lines(diffnr, 0, -1, false, stdout)
    vim.api.nvim_command('diffthis')
    vim.api.nvim_set_current_win(handle)
    vim.api.nvim_command('diffthis')

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
