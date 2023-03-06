local map = require('mug.module.map')
local util = require('mug.module.util')

---@class float
---@filed title function Adjust float title
---@field open function Open MugFloat buffer
---@field input function Open MugFloat input-bar without fade highlighting
---@field input_nc function Open MugFloat input-bar with fade highlighting
---@field focus function Focus MugFloat
---@field maps function Open MugFloat and display keymaps
local M = {}
local HEADER, NAMESPACE = 'mug/float', 'MugFloat'
local store_keymap

---@class Mug
---@field float_winblend integer MugFloat transparency
_G.Mug._def('float_winblend', 0, true)

---Disable highlighting for floating-window when navigating to input-bar
local ns_inputbar = vim.api.nvim_create_namespace(NAMESPACE)

do
  local normal_bg = vim.api.nvim_get_hl_by_name('Normal', true).background
  local items = {
    'Title',
    'NormalNC',
    'NormalFloat',
    'FloatBorder',
    'ColorColumn',
  }

  for _, v in ipairs(items) do
    vim.api.nvim_set_hl(ns_inputbar, v, { bg = normal_bg })
  end
end

---@class Float
---@field private relative string
---@field private anchor string
---@field private style string
---@field private title_pos string
---@field private noautocmd boolean
---@field private _new function
local Float = {
  style = 'minimal',
  title_pos = 'center',
  border = 'none',
  relative = 'editor',
  anchor = 'NW',
  noautocmd = true,
}

local get_global = vim.api.nvim_get_option

---@param title string Float title
---@param width number Float width
---@return string # Adjusted float title
M.title = function(title, width)
  title = ' ' .. title .. ' '
  local title_len = vim.api.nvim_strwidth(title)

  if title_len > width then
    title = title:sub(1, math.max(1, title_len - 13)) .. '... '
  end

  return title
end

setmetatable(Float, {
  __index = {
    ---@param title string window title
    ---@param height integer window number of lines
    ---@param width number window width ratio
    ---@param border? string window border `single`|`double`|`rounded`|`solid`|`shadow`
    ---@param callback? function content expanded on window
    ---@return table|nil
    _new = function(self, title, height, width, border, relative, anchor, zindex, callback)
      local opts = vim.deepcopy(self)
      local bufnr = vim.api.nvim_create_buf(false, true)

      vim.api.nvim_buf_set_name(bufnr, NAMESPACE .. ':/' .. title)
      vim.api.nvim_buf_set_option(bufnr, 'bufhidden', 'wipe')
      local lastline = get_global('cmdheight')
        + (get_global('laststatus') == 0 and 0 or 1)
        + (get_global('showtabline') == 0 and 0 or 1)
        + 2
      local disp_width = get_global('columns')
      local disp_height = get_global('lines') - lastline
      local buf_height

      opts.border = border or opts.border
      opts.relative = relative or opts.relative
      opts.anchor = anchor or opts.anchor
      opts.zindex = zindex

      if not callback then
        buf_height = height
      else
        local contents = callback()

        if type(contents) ~= 'table' then
          vim.api.nvim_buf_set_lines(bufnr, 0, height, false, { contents })
        else
          if vim.tbl_isempty(contents) == 0 then
            return vim.notify('[' .. title .. '] empty')
          end

          if vim.tbl_count(contents) <= 1 and table.concat(contents, ''):match('^%s*$') then
            return vim.notify('[' .. title .. '] nil')
          end

          local max_digit = 1

          for _, value in pairs(contents) do
            max_digit = math.max(max_digit, vim.api.nvim_strwidth(value) + 1)
          end

          max_digit = math.min(max_digit, disp_width) / disp_width
          width = math.max(width or 0, max_digit)
          buf_height = vim.tbl_count(contents)
          vim.api.nvim_buf_set_lines(bufnr, 0, buf_height, false, contents)
        end
      end

      if relative == 'editor' then
        opts.width = width > 1 and math.min(disp_width, width) or math.floor(disp_width * width)
        opts.col = math.floor((disp_width - opts.width) / 2)
        opts.height = math.min(disp_height, buf_height)
        opts.row = math.max(1, math.floor((disp_height - opts.height) / 2))
      else
        opts.width = math.min(disp_width, width) or 15
        opts.col = 1
        opts.height = 1
        opts.row = 1
      end

      opts.title = M.title(title or HEADER, opts.width)

      return { bufnr = bufnr, opts = opts }
    end,
  },
})

local function float_buffer_cmd_and_map()
  vim.api.nvim_buf_create_user_command(0, 'MMMugFloatMove', function(opts)
    local direction = {
      h = { row = -1, col = -2 - opts.count },
      j = { row = 0 + opts.count, col = -1 },
      k = { row = -2 - opts.count, col = -1 },
      l = { row = -1, col = 0 + opts.count },
    }

    local d = direction[opts.args]
    vim.api.nvim_win_set_config(0, { relative = 'win', row = d.row, col = d.col })
  end, { count = true, nargs = 1 })

  map.buf_set(true, 'n', '<M-h>', ':MMMugFloatMove h<CR>', 'Float shift left')
  map.buf_set(true, 'n', '<M-j>', ':MMMugFloatMove j<CR>', 'Float shift right')
  map.buf_set(true, 'n', '<M-k>', ':MMMugFloatMove k<CR>', 'Float shift down')
  map.buf_set(true, 'n', '<M-l>', ':MMMugFloatMove l<CR>', 'Float shift up')
  map.ref_maps()
  map.quit_key()
end

---@param addition function specified buffer unique maps
local function float_buffer_post(addition)
  float_buffer_cmd_and_map()

  if addition then
    addition()
  end
end

local function float_buffer_autocmd(bufnr, leavecmd)
  local float_col = math.max(1, get_global('columns') - 30)
  local float_width = vim.api.nvim_win_get_width(0)
  local float_height = vim.api.nvim_win_get_height(0)
  local row, col = unpack(vim.api.nvim_win_get_position(0))

  local au_id_bufleave = vim.api.nvim_create_autocmd({ 'BufLeave' }, {
    group = 'mug',
    buffer = bufnr,
    callback = function()
      vim.api.nvim_win_set_option(0, 'winblend', 20)
      pcall(vim.api.nvim_win_set_config, 0, {
        relative = 'editor',
        row = 1,
        col = float_col,
        height = math.min(10, float_height),
        width = math.min(30, float_width),
      })
    end,
    desc = 'Move the float to the edge when out of focus',
  })
  local au_id_bufenter = vim.api.nvim_create_autocmd({ 'BufEnter' }, {
    group = 'mug',
    buffer = bufnr,
    callback = function()
      vim.api.nvim_win_set_option(0, 'winblend', _G.Mug.float_winblend)
      vim.api.nvim_win_set_config(
        0,
        { relative = 'editor', row = row, col = col, height = float_height, width = float_width }
      )
    end,
    desc = 'Restore position when it gets focus',
  })
  vim.api.nvim_create_autocmd({ 'BufWipeout' }, {
    group = 'mug',
    once = true,
    buffer = bufnr,
    callback = function()
      vim.api.nvim_del_autocmd(au_id_bufleave)
      vim.api.nvim_del_autocmd(au_id_bufenter)

      local float_exist = util.get_bufs(NAMESPACE .. ':/')

      if #float_exist == 1 then
        pcall(vim.fn.mapset, 'n', false, store_keymap)
        store_keymap = nil
      end

      if leavecmd then
        leavecmd()
      end
    end,
    desc = 'Additional processing performed when wipeout a floating-window',
  })
end

---@param bufnr number buffer id of windowflo
---@param opts table options of window
---@return table # {bufnr = buffer id, handle = buffer handle}
local function create_float(bufnr, opts)
  local handle = vim.api.nvim_open_win(bufnr, true, opts)

  vim.api.nvim_command('clearjumps')

  return { bufnr = bufnr, handle = handle }
end

---@param tbl table nvim_open_win options
---@return table # { bufnr = buffer number, handle = buffer handle }
M.open = function(tbl)
  local win = Float:_new(tbl.title, tbl.height, tbl.width, tbl.border, 'editor', 'NW', 50, tbl.contents)

  if not win then
    return { bufnr = nil, handle = nil }
  end

  local buf = win ~= nil and create_float(win.bufnr, win.opts) or {}
  local keymap = '<C-w>p'
  store_keymap = vim.fn.maparg(keymap, 'n', false, true)

  vim.api.nvim_win_set_option(0, 'winblend', _G.Mug.float_winblend)
  vim.keymap.set('n', keymap, function()
    local bufs = util.get_bufs(NAMESPACE .. ':/')
    local handle = 0

    for _, v in ipairs(bufs) do
      if v ~= vim.api.nvim_get_current_buf() then
        handle = vim.fn.bufwinid(v)
      end
    end

    if handle == -1 then
      local key = vim.api.nvim_replace_termcodes('<C-w>p', true, false, true)
      vim.api.nvim_feedkeys(key, 'n', false)
    else
      vim.api.nvim_set_current_win(handle)
    end
  end, { desc = 'Focus Mug float buffer' })

  float_buffer_post(tbl.post)
  float_buffer_autocmd(buf.bufnr, tbl.leave)

  return buf
end

---@param tbl table nvim_open_win options
---@return table # { bufnr = buffer number, handle = buffer handle }
M.input = function(tbl)
  local current_bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_win_set_option(0, 'winhighlight', 'NormalNC:Normal')

  local win = Float:_new(tbl.title, 1, tbl.width, tbl.border, tbl.relative, tbl.anchor, 99, tbl.contents)
  local input_bar = win ~= nil and create_float(win.bufnr, win.opts) or {}
  win = nil

  vim.api.nvim_win_set_option(0, 'winblend', 0)
  vim.api.nvim_win_set_hl_ns(0, ns_inputbar)
  float_buffer_post(tbl.post)
  map.input_keys()
  vim.api.nvim_command('startinsert!')
  vim.api.nvim_create_autocmd({ 'WinEnter' }, {
    group = 'mug',
    once = true,
    buffer = current_bufnr,
    callback = function()
      vim.wo.winhighlight = nil
    end,
    desc = 'Clear winhighlight',
  })

  return input_bar
end

---@param tbl table nvim_open_win options
---@return table # { bufnr = buffer number, handle = buffer handle }
M.input_nc = function(tbl)
  local win = Float:_new(tbl.title, 1, tbl.width, tbl.border, tbl.relative, tbl.anchor, 99, tbl.contents)
  local input_bar = win ~= nil and create_float(win.bufnr, win.opts) or {}

  vim.api.nvim_win_set_option(0, 'winblend', 0)
  map.input_keys()
  float_buffer_post(tbl.post)
  vim.api.nvim_command('startinsert!')

  return input_bar
end

---@param handle number buffer handle
---@return boolean # whether the handle exists
M.focus = function(handle)
  return vim.fn.win_gotoid(handle) ~= 0
end

M.maps = function()
  local map_list = function()
    local tbl = {}
    local desc
    local maps = vim.api.nvim_buf_get_keymap(0, 'n')

    for _, v in ipairs(maps) do
      desc = v.desc or v.rhs or '?'
      table.insert(tbl, string.format(' %s\t= %s ', v.lhs, desc))
    end

    return tbl
  end

  M.open({
    title = 'Keymaps',
    border = 'rounded',
    relative = 'cursor',
    contents = map_list,
  })
end

return M
