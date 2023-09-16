---@class util
local M = {}
local has_shellslash = vim.fn.exists('+shellslash') == 1
local is_win = vim.fn.has('win32')

---Convert backslash to slash
---@param item string String to convert
---@return string item
M.conv_slash = function(item)
  return (item:gsub('\\', '/'))
end

---Returns the current path separator
---@return string # `slash` or `backslash`
M.get_sep = function()
  local s = '/'

  if has_shellslash then
    s = vim.api.nvim_get_option('shellslash') and '/' or '\\'
  end

  return s
end

---Normalize the path using current path separator
---@param path string Normalization target
---@param sep? string Slash or backslash character-code
---@return string # Normalized path
---@return integer # Match count
M.normalize = function(path, sep)
  if not sep or not sep:match('[/\\]') then
    sep = M.get_sep()
  end

  local target_chr = {
    ['/'] = '\\',
    ['\\'] = '/',
  }

  ---NOTE: to maintain compatibility, we believe that drive letters in paths passed to the editor should be upper case
  path = path:sub(1, 1):upper() .. path:sub(2)

  return path:gsub(target_chr[sep], sep)
end

---Returns the current working directory
---@return string # working directory path separated by slashes
M.pwd = function()
  return vim.uv.cwd():gsub('\\', '/')
end

---Normalize path of the file being edited
---@param sep string? Path separator
---@param response? boolean Display notification
---@return string|nil # Normalized path of the current file
M.filepath = function(sep, response)
  local path = vim.api.nvim_buf_get_name(0)

  if path == '' then
    return response and M.notify('File not found', 'mug', 4) or nil
  end

  return sep and M.normalize(path, sep) or path
end

---Normalize parent directory of the file being edited
---@param sep string? Path separator
---@return string # Parent directory path of the current file
M.dirpath = function(sep)
  local path = vim.api.nvim_buf_get_name(0)
  path = path == '' and vim.uv.cwd() or path:gsub('^(.+)[/\\].*$', '%1')

  return sep and M.normalize(path, sep) or path
end

---Format the message displayed in the prompt
---@param message string[] Notification message
---@return string # Merged message
local function merge_message(message)
  local merged = ''
  local connect

  for _, v in ipairs(message) do
    if v:find('[', 1, true) == 1 and not v:find(']', 1, true) and v:find('%s$', 2) then
      connect = v
    elseif connect then
      merged = string.format('%s%s%s\n', merged, connect, v)
      -- merged = merged .. connect .. v .. tail_blank .. '\n'
      connect = nil
    else
      merged = string.format('%s%s\n', merged, v)
      -- merged = merged .. v .. tail_blank .. '\n'
    end
  end

  return merged
end

---Wrap vim.notify()
---@param message string|table Notification message
---@param title string Message header
---@param loglevel integer vim.log.levels
---@param multiline? boolean Whether to support multiple lines for message
---@return string|nil # Message for debug
M.notify = function(message, title, loglevel, multiline)
  _G.Mug._ow('loglevel', loglevel)

  if type(message) == 'table' then
    message = merge_message(message)
  end

  if vim.g.mug_debug then
    return message
  end

  local header = ''

  if not package.loaded['notify'] then
    local concatenate = multiline and '\n' or ' '
    header = string.format('[%s]%s', title, concatenate)
  end

  if is_win then
    message = message:gsub('%[[%d;]*[%w]', '')
  end

  vim.notify(header .. vim.trim(message), loglevel, { title = title })
end

---Interactive question
---@param message string Question
---@param title string The header of the question
---@param selection? 'y'|'n' Default select the character
---@return boolean # Answer to the question
M.interactive = function(message, title, selection)
  if vim.g.mug_debug then
    return true
  end

  selection = selection or 'n'

  local choice = { y = 'Y/n', n = 'y/N' }
  local msg = string.format('[%s] %s [%s] ', title, message, choice[selection])
  local res = vim.fn.inputdialog(msg, '', 'n')

  if res:lower() == 'y' then
    return true
  end

  return res == '' and selection == 'y'
end

---Confirm question
---@param message string|string[] Question
---@param choices string Choices for question
---@param default integer Default answer
---@param header string The header of the question
---@return integer|boolean # Selected answer
M.confirm = function(message, choices, default, header)
  local title = string.format('[%s]', header)

  if vim.g.mug_debug then
    return true
  end

  if type(message) == 'table' then
    message = merge_message(message)
    title = string.format(' \n', title)
  end

  return vim.fn.confirm(title .. message, choices, default)
end

---Merge tables by omitting duplicate values
---NOTE: Properties with the same key are overridden by the one found later
---@param ... table Tables to merge
---@return table # Merged table
M.tbl_merges = function(...)
  local new = {}

  for _, t in ipairs({ ... }) do
    assert(type(t) == 'table', 'type error :: expected table')

    for k, v in pairs(t) do
      if type(k) ~= 'number' then
        new[k] = v
      elseif not vim.tbl_contains(new, v) then
        vim.list_extend(new, { v })
      end
    end
  end

  return new
end

---Dock multiple elements
---NOTE: Properties with the same key are overridden by the one found later
---@param ... any Elements to docking
---@return table # Merged table
M.tbl_docking = function(...)
  local new_tbl = {}

  for _, t in ipairs({ ... }) do
    if type(t) ~= 'table' and t ~= '' then
      table.insert(new_tbl, t)
    else
      for k, v in pairs(t) do
        if type(k) ~= 'number' then
          new_tbl[k] = v
        elseif v and v ~= '' then
          if type(v) == 'table' then
            if not vim.tbl_isempty(v) and table.concat(v, '') ~= '' then
              vim.list_extend(new_tbl, v)
            end
          else
            table.insert(new_tbl, v)
          end
        end
      end
    end
  end

  return new_tbl
end

---Check to see if the file exists
---@param path string|nil Path to be checked for existence
---@return boolean # Exist or not
M.file_exist = function(path)
  if not path then
    return false
  end

  local handle = io.open(path, 'r')

  if handle ~= nil then
    io.close(handle)
  end

  return handle ~= nil
end

---Get standard output of the shell commands
---@param command string Shell-command with options
---@return string # Shell-command stdout
M.get_stdout = function(command)
  local handle = io.popen(command .. ' 2>&1', 'r')

  if not handle then
    return ''
  end

  local contents = handle:read('*all')

  handle:close()

  return contents
end

---Extract specified name from all buffers
---@param name string Target of extract
---@return table # Extrasted buffers
M.get_bufs = function(name)
  local bufs = vim.api.nvim_list_bufs()
  local tbl = {}

  for _, v in ipairs(bufs) do
    if vim.api.nvim_buf_get_name(v):find(name, 1, true) == 1 then
      table.insert(tbl, v)
    end
  end

  return tbl
end

---Check if the current file is in the git-repository
---@param header string The header of the notification
---@return boolean # In git-repository
---@return string # Git-repository root path
M.has_repo = function(header)
  if vim.bo.buftype ~= '' then
    M.notify('Can not run in special buffer', header, 3)
    return false, ''
  end

  ---@type string|nil
  local path = vim.fs.find('.git', { type = 'directory', upward = true })[1]

  if not path then
    M.notify('Not a git repository', header, 3)
    return false, ''
  end

  ---@type string
  local branch_name = vim.b.mug_branch_name

  if not branch_name or branch_name == _G.Mug.symbol_not_repository then
    package.loaded['mug.workspace'].set_workspace_root(false)
  end

  return true, path:sub(1, -6)
end

---Check if the current directory is the git-repository
---@param header string The header of the notification
---@return boolean # Is it a git-repository
M.is_repo = function(header)
  if vim.fn.isdirectory(vim.uv.cwd() .. M.get_sep() .. '.git') == 0 then
    M.notify('Current directory does not point to git-root', header, 3)
    return false
  end

  return true
end

---@class GitCmd
---@field cmd string
---@field wd? string
---@field noquotepath? boolean
---@field noeditor? boolean
---@field cfg? string
---@field opts? table<string,string>

---Create git command and option as a table
---@param tbl GitCmd Specified git subcommand and options
---@return table<string,string> # Table of normalized git command and options
M.gitcmd = function(tbl)
  local wd = tbl.wd or M.pwd()
  local quotepath = tbl.noquotepath and { '-c', 'core.quotepath=false' } or {}
  local editor = tbl.noeditor and { '-c', 'core.editor=false' } or {}
  local cfg = tbl.cfg and { '-c', tbl.cfg } or {}
  local subcmd = tbl.cmd

  return M.tbl_docking('git', '-C', wd, '-c', 'color.status=always', quotepath, editor, cfg, subcmd, tbl.opts)
end

---Setup the virtual buffer
---@param bufnr integer Buffer number
---@param listed boolean Whether to put on the buffer list
---@param hidden string Behavior on buffer close
---@param type? string Specify buffer type
M.nofile = function(bufnr, listed, hidden, type)
  type = type or 'nofile'
  vim.api.nvim_set_option_value('swapfile', false, { buf = bufnr })
  vim.api.nvim_set_option_value('buflisted', listed, { buf = bufnr })
  vim.api.nvim_set_option_value('bufhidden', hidden, { buf = bufnr })
  vim.api.nvim_set_option_value('buftype', type, { buf = bufnr })
end

---Adjust and register the name of the User-defined command
---@param name string User command name
---@param command function User command contents
---@param options table User command options
M.user_command = function(name, command, options)
  if _G.Mug[name] then
    if vim.fn.exists(':' .. _G.Mug[name]) ~= 2 then
      vim.api.nvim_create_user_command(_G.Mug[name], function(opts)
        command(opts)
      end, options)

      _G.Mug._ow(name, nil)
    end
  end
end

---Open terminal as buffer
---@param cmd string Launch command on terminal buffer
---@param buf {bufnr: integer, handle: integer}
M.termopen = function(cmd, buf)
  if #cmd == 0 then
    cmd = _G.Mug.term_shell or vim.api.nvim_get_option_value('shell', { scope = 'global' })
  end

  vim.fn.termopen(cmd, {
    on_exit = function()
      if vim.api.nvim_buf_is_valid(buf.bufnr) then
        vim.cmd.bwipeout()
      end
    end,
  })
end

return M
