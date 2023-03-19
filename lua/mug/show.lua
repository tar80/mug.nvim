local float = require('mug.module.float')
local syntax = require('mug.module.syntax')
local notify = require('mug.module.util').notify
local user_command = require('mug.module.util').user_command


local HEADER, NAMESPACE = 'mug/show', 'MugShow'
local float_handle = 0

---MugShow float-window syntaxs
local show_syntax = function()
  syntax.general()
  syntax.log()
  syntax.diff()
  syntax.stats()
end

---Extract type from literal and define
---@param literal string parameter
---@return any
local function define_type(literal)
  local value

  if literal:match('^%d+$') then
    value = tonumber(literal)
  elseif literal:find('["\']') then
    value = literal:gsub('["\']', '')
  elseif literal == 'true' then
    value = true
  elseif literal == 'false' then
    value = false
  elseif literal == '' then
    value = nil
  end

  return value
end

---Extract elements from literals and convert them to table
---@param literals string
---@return table
local function str_to_tbl(literals)
  local tbl = {}
  literals = literals:gsub('^%s*[{[]%s*(.+)[}%]]%s*$', '%1')

  if literals:find(',', 1, true) then
    local t = vim.split(literals, ',', { plain = true })

    for _, v in ipairs(t) do
      if v:find('[{[]') then
        table.insert(tbl, str_to_tbl(v))
      elseif v:find('=', 1, true) then
        v = vim.split(v, '=', { plain = true })
        tbl[vim.trim(v[1])] = define_type(vim.trim(v[2]))
      else
        table.insert(tbl, define_type(vim.trim(v)))
      end
    end
  elseif literals ~= '{}' and literals:match('%g+') then
    tbl = { define_type(literals) }
  end

  return tbl
end

---Convert literals to fit function and parameter
---@param presented string MugShow option
---@param obj string function source
---@return function vim.xxx.method()
local function makeup_func(presented, obj)
  local arg_tbl = {}
  local delim = 'm9^~^'
  local s = presented:gsub('^(.+)%((.*)%)$', '%1' .. delim .. '%2')
  s = vim.split(s, delim, { plain = true })
  local func = vim[obj][s[1]]

  if s[2] == '' then
    return func()
  end

  arg_tbl = str_to_tbl(s[2])

  return vim.tbl_isempty(arg_tbl) and func(arg_tbl) or func(unpack(arg_tbl))
end

local function expand_obj(obj, literals)
  local o = obj
  local elements = vim.split(literals, '.', { plain = true })

  for _, v in ipairs(elements) do
    o = o[v]
  end

  return o
end

---Convert literals to fit function parameter
---@param presented string MugShow option
---@return function vim.method()
local function makeup_vimfunc(presented)
  local arg_tbl = {}
  local s = { presented }

  if presented:sub(-1) == ')' then
    s = vim.split(presented:sub(1, -2), '(', { plain = true })
  end

  local vimfunc = expand_obj(vim, s[1])

  if not s[2] then
    local tbl = vim.inspect(vimfunc):gsub(',', ';')

    return tbl:gsub(';?\n', ',')
  elseif s[2] == '' then
    return vimfunc()
  else
    arg_tbl = str_to_tbl(s[2])
  end

  return vim.tbl_isempty(arg_tbl) and vimfunc() or vimfunc(unpack(arg_tbl))
end

local function get_value(opts)
  if opts.bang then
    return vim.fn.systemlist(opts.args)
  elseif opts.args:match('^:') then
    return vim.trim(vim.api.nvim_exec(opts.args:sub(2), {})):gsub('\n', ',')
  elseif opts.args:match('^[bwtgv]:') then
    local v = vim.split(opts.args:gsub('(.):(.+)', '%1,%2'), ',', { plain = true })
    return vim[v[1]][v[2]]
  elseif opts.args:match('^$%w+') then
    return vim.env[opts.args:sub(2)]:gsub(';', ',')
  elseif opts.args:match('^&%w+') then
    return vim.api.nvim_get_option_value(opts.args:sub(2), {})
  elseif opts.args:match('^_G%.') and type(opts.args) then
    local f = expand_obj(_G, opts.args:sub(4))
    local tbl = vim.inspect(f):gsub(',', ';')
    return tbl:gsub(';?\n', ',')
  elseif opts.args:match('^vim%.') then
    return makeup_vimfunc(opts.args:sub(5))
  elseif opts.args:match('^nvim_') then
    return makeup_func(opts.args, 'api')
  elseif opts.args:match('.+%(.*%)$') then
    return makeup_func(opts.args, 'fn')
  end

  local exitcode, output = pcall(vim.api.nvim_exec, opts.args, {})

  if not exitcode then
    return notify(output, HEADER, 3)
  end

  return vim.trim(output):gsub('\n', ',')
end

user_command('show_command', function(opts)
  if float.focus(float_handle) then
    return
  end

  local result = vim.deepcopy(get_value(opts))
  local bang = opts.bang and '! ' or ' '

  if type(result) == 'nil' then
    return
  end

  if result == '' or (type(result) == table and vim.tbl_isempty(result) == 0) then
    return notify(opts.args .. ' is empty', HEADER, 3)
  end

  local create_tbl = function()
    local adjust_line = {}

    if type(result) ~= 'table' then
      result = vim.split(tostring(result), ',', { plain = true })
    end

    local format = vim.tbl_keys(result)[1] == 1 and function(_)
      return ' '
    end or function(key)
      return key .. '='
    end

    for key, value in pairs(result) do
      if type(value) == 'table' then
        local tbl = vim.inspect(value):gsub(',', ';')

        table.insert(adjust_line, format(key) .. tbl:gsub(';?\n', ','))
      else
        table.insert(adjust_line, format(key) .. tostring(value))
      end
    end

    return adjust_line
  end

  float_handle = float.open({
    title = NAMESPACE .. bang .. opts.args,
    height = 1,
    width = 0.3,
    border = 'rounded',
    contents = create_tbl,
    post = show_syntax,
  }).handle
end, {
  nargs = '+',
  bang = true,
  complete = function(a, _, _)
    if vim.startswith(a, '$') then
      return vim.fn.getcompletion(a:sub(2), 'environment')
    elseif vim.startswith(a, '&') then
      return vim.fn.getcompletion(a:sub(2), 'option')
    elseif vim.startswith(a, ':') then
      return vim.fn.getcompletion(a:sub(2), 'command')
    elseif vim.startswith(a, 'g:') then
      return vim.fn.getcompletion(a, 'var')
    elseif vim.startswith(a, 'v:') then
      return vim.fn.getcompletion(a, 'var')
    elseif vim.startswith(a, 'w:') then
      return vim.fn.getcompletion(a, 'var')
    elseif vim.startswith(a, 'b:') then
      return vim.fn.getcompletion(a, 'var')
    elseif vim.startswith(a, 'nv') then
      return vim.fn.getcompletion(a, 'function')
    else
      return vim.fn.getcompletion(a, 'cmdline')
    end
  end,
})
