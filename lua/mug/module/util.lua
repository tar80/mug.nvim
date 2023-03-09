---@class util
---@field slash function Returns currently path separator
---@field normalize function Normalize path using crrently path separator
---@field pwd function Returns current working directory
---@field filepath function Normalize path of the file being edited
---@field dirpath function Normalize parent directory of the file being edited
---@field notify function Display notification
---@field interactive function Ask permission
---@field confirm function Confirm request a response
---@field tbl_merges function Merge multiple tables
---@field tbl_docking function Docking multiple elements
---@field file_exist function Check for file existence
---@field get_stdout function Get shell command stdout
---@field get_bufs function Extract specified element from all buffers
---@field belongtoRepo function Returns whether the file being edited belongs to the repository or not
---@field isRepo function Returns whether the specified path is a repository or not
---@field gitcmd function Returns git command and options as a table
---@field nofile function Apply settings as virtual buffer to buffer
local M = {}
local has_shellslash = vim.fn.exists('+shellslash') == 1

---@return string # `slash` or `backslash`
M.slash = function()
  local s = '/'

  if has_shellslash then
    s = vim.api.nvim_get_option('shellslash') and '/' or '\\'
  end

  return s
end

---@return string # path-separated normalization
M.normalize = function(path, sep)
  if not sep or not sep:match('[/\\]') then
    sep = M.slash()
  end

  local target_chr = {
    ['/'] = '\\',
    ['\\'] = '/',
  }

  return path:gsub(target_chr[sep], sep)
end

---@param base? string? Specifying `parent` returns the parent directory is normalized
---@return string # working directory path separated by slashes
M.pwd = function(base)
  if base ~= 'parent' then
    local current_dir = vim.loop.cwd():gsub('\\', '/')
    return current_dir
  end

  local parent_dir = vim.fs.dirname(vim.api.nvim_buf_get_name(0))
  return parent_dir ~= '.' and parent_dir or vim.loop.cwd():gsub('\\', '/')
end

---@param sep string? Normalize the filepath
---@return string # Fullpath of being edited file
M.filepath = function(sep)
  local path = vim.api.nvim_buf_get_name(0)

  if path == '' then
    M.notify('File not found', 'mug', 4)
    return ''
  end

  return sep and M.normalize(path, sep) or path
end

---@param sep string? Normalize the filepath
---@return string # Parent directory of current filepath
M.dirpath = function(sep)
  local path = vim.api.nvim_buf_get_name(0)
  path = path == '' and vim.loop.cwd() or path:gsub('^(.+)[/\\].*$', '%1')

  return sep and M.normalize(path, sep) or path
end

---If the highlight has a bold attribute,
---the characters at the end of the word are cut off, so add a space to deal with it
---@param highlight string Highlight group name
---@return string # Linewise tail spaces
local function adjust_tail_blank(highlight)
  local tbl = {}
  tbl = vim.api.nvim_get_hl_by_name(highlight, false)
  tbl = vim.tbl_keys(tbl)

  return vim.tbl_contains(tbl, 'bold') and '  ' or ''
end

---Format the message displayed in the prompt
---@param message table Prompt notification
---@param name string Function name used
---@param loglevel number Error level
---@return string # Merged message
local function merge_message(message, name, loglevel)
  local tail_blank = '  '
  local merged = ''
  local connect

  -- if name == 'confirm' then
  --   tail_blank = adjust_tail_blank('MoreMsg')
  -- elseif loglevel == 3 then
  --   tail_blank = adjust_tail_blank('WarningMsg')
  -- end

  for _, v in ipairs(message) do
    if v:find('[', 1, true) == 1 and not v:find(']', 1, true) and v:find('%s$', 2) then
      connect = v
    elseif connect then
      merged = merged .. connect .. v .. tail_blank .. '\n'
      connect = nil
    else
      merged = merged .. v .. tail_blank .. '\n'
    end
  end

  return merged
end

---@param message string|table Notification message
---@param title string Message-header
---@param loglevel number vim.log.levels
---@param multiline? boolean Whether to support multiple lines for error-message
---@return string|nil # Return message for debug
M.notify = function(message, title, loglevel, multiline)
  _G.Mug._ow('loglevel', loglevel)

  if type(message) == 'table' then
    message = merge_message(message, 'notify', loglevel)
  end

  if vim.g.mug_debug then
    return message
  end

  local header = ''

  if not package.loaded['notify'] then
    local concatenate = multiline and '  \n' or ' '
    header = '[' .. title .. ']' .. concatenate
  end

  vim.notify(header .. vim.trim(message), loglevel, { title = title })
end

---@param message string Question
---@param title string Question-header
---@param selection? string `y` or `n`
---@return boolean # Answer to the question
M.interactive = function(message, title, selection)
  if vim.g.mug_debug then
    return true
  end

  selection = selection or 'n'

  local choice = { y = ' [Y/n] ', n = ' [y/N] ' }
  local res = vim.fn.inputdialog('[' .. title .. '] ' .. message .. choice[selection], '', 'n')

  if res:lower() == 'y' then
    return true
  end

  return res == '' and selection == 'y'
end

---@param message string Question
---@param choices string Question-choices
---@param default number Default answer
---@param header string Question-header
---@return number|boolean # User selection
M.confirm = function(message, choices, default, header)
  header = '[' .. header .. '] '

  if vim.g.mug_debug then
    return true
  end

  if type(message) == 'table' then
    message = merge_message(message, 'confirm', _)
    header = header .. ' \n'
  end

  return vim.fn.confirm(header .. message, choices, default)
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
---@param path string Path to be checked for existence
---@return boolean # Existed or not
M.file_exist = function(path)
  local handle = io.open(path, 'r')

  if handle ~= nil then
    io.close(handle)
  end

  return handle ~= nil
end

---Get standard output of shell commands
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

---@param header string Notification-header
---@return boolean # In git-repository
---@return string # Git-repository root path
M.belongtoRepo = function(header)
  local path = vim.fs.find('.git', { type = 'directory', upward = true })[1]

  if not path then
    M.notify('Not a git repository', header, 2)
    return false, ''
  end

  return true, path
end

---@param header string Notification-header
---@return boolean # Is it a git-repository
M.isRepo = function(header)
  if vim.fn.isdirectory(vim.loop.cwd() .. M.slash() .. '.git') == 0 then
    M.notify('Current direcotry does not point to git-root', header, 3)
    return false
  end

  return true
end

---@param tbl table Specified git subcommand and options
---@return table # Table of normalized git command and options
M.gitcmd = function(tbl)
  local wd = tbl.wd or M.pwd()
  local quotepath = tbl.noquotepath and { '-c', 'core.quotepath=false' } or {}
  local editor = tbl.noeditor and { '-c', 'core.editor=false' } or {}
  local cfg = tbl.cfg and { '-c', tbl.cfg } or {}
  local subcmd = tbl.cmd

  return M.tbl_docking('git', '-C', wd, quotepath, editor, cfg, subcmd, tbl.opts)
end

---Setup virtual buffer
---@param listed boolean Whether to put on the buffer list
---@param hidden string Behavior on buffer close
---@param type? string Specify buffer type
M.nofile = function(listed, hidden, type)
  type = type or 'nofile'
  vim.api.nvim_buf_set_option(0, 'swapfile', false)
  vim.api.nvim_buf_set_option(0, 'buflisted', listed)
  vim.api.nvim_buf_set_option(0, 'bufhidden', hidden)
  vim.api.nvim_buf_set_option(0, 'buftype',type)
end

return M
