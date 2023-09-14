local map = require('mug.module.map')
local util = require('mug.module.util')
local hl = require('mug.module.highlight')

---@class float
local M = {}
local HEADER = 'mug/float'
local NAMESPACE = 'MugFloat'
local toggle_float = '<M-p>'
---@type table|nil Value of the maparg
local store_keymap
---@type integer|string, integer|string
local normal_bg, nc_bg
local normal_float = { 'NormalNC', 'NormalFloat', 'FloatTitle', 'FloatBorder', 'ColorColumn' }
local nc_float = { 'FloatTitle', 'FloatBorder' }

---@class Mug
---@field float_winblend integer MugFloat/MugTerm transparency
_G.Mug._def('float_winblend', 0, true)

---@alias NameSpace integer ID of namespace
---Disable highlighting for the floating window border
local ns_normal = vim.api.nvim_create_namespace(NAMESPACE)
local ns_nc = vim.api.nvim_create_namespace('MugFloatNC')

---Get the bgcolor of the specified hlgroup
---@param ns NameSpace
---@param name string Hlgroup
---@return integer # Background color code
local get_bgcolor = function(ns, name)
  local color_tbl = vim.api.nvim_get_hl(ns, { name = name })
  local bg = 0

  if color_tbl.bg then
    bg = color_tbl.bg
  elseif color_tbl.link then
    bg = vim.api.nvim_get_hl(ns, { name = color_tbl.link }).bg or 0
  end

  return bg
end

---Set the bgcolor of the specified hlgroups
---@param ns NameSpace
---@param bg integer|string Bgcolor
---@param hlgroups string[] `"normal_float"`|`"nc_float"`
local set_highlights = function(ns, bg, hlgroups)
  for _, name in ipairs(hlgroups) do
    hl.set_hl(name, { ns = ns, hl = { bg = bg } })
  end
end

---Restore bgcolor of the specified hlgroups
---@param ns integer
---@param state string State of the float window. `"normal"`|`"nc"`
local restore_highlights = function(ns, state)
  local tbl = {
    nc = { bg = nc_bg, hlgroups = nc_float },
    normal = { bg = normal_bg, hlgroups = normal_float },
  }
  local t = tbl[state]

  for _, name in ipairs(t.hlgroups) do
    hl.set_hl(name, { ns = ns, hl = { bg = t.bg } })
  end
end

hl.late_record(function()
  normal_bg = get_bgcolor(0, 'Normal')
  nc_bg = get_bgcolor(0, 'NormalNC')

  if normal_bg == 0 then
    normal_bg = 'NONE'
  end

  set_highlights(ns_normal, normal_bg, normal_float)
  set_highlights(ns_nc, nc_bg, nc_float)
  set_highlights(ns_nc, normal_bg, { 'NormalFloat' })
end)

---@alias float_relative string Layout the float to place at
---@alias float_anchor string Decides which corner of the float to place at
---@alias float_style string Configure the appearance of the window
---@alias float_title string Window title
---@alias float_title_pos string Title position
---@alias float_noautocmd boolean Skip autocmd events
---@alias float_height number Number of lines
---@alias float_width number Window width or ratio
---@alias float_border string Window border
---@alias float_zindex number Floats stacking order
---@alias float_callback function Content expanded in window

---@class Float
---@field private relative float_relative
---@field private anchor float_anchor
---@field private style float_style
---@field private title_pos float_title_pos
---@field private noautocmd float_noautocmd
---@field private _new function
local Float = {
  style = 'minimal',
  title_pos = 'center',
  border = 'none',
  relative = 'editor',
  anchor = 'NW',
  noautocmd = true,
}

---Get global option value
---@param option string Option name
---@return any # Option value
local get_global = function(option)
  return vim.api.nvim_get_option_value(option, { scope = 'global' })
end

---Get title of the floating window
---@param title string Float title
---@param width number Float width
---@return string # Adjusted float title
M.title = function(title, width)
  title = string.format(' %s ', title)
  local title_len = vim.api.nvim_strwidth(title)

  if title_len > width then
    title = string.format('%s... ', title:sub(1, math.max(1, title_len - 13)))
  end

  return title
end

---Get max range of the floating window
---@return number # Float max width
---@return number # Float max height
local function max_range()
  local lastline = get_global('cmdheight')
    + (get_global('laststatus') == 0 and 0 or 1)
    + (get_global('showtabline') == 0 and 0 or 1)
    + 2
  local w = get_global('columns')
  local h = get_global('lines') - lastline

  return w, h
end

---Close floating window and display notification
---@param bufnr integer ID of the floating window
---@param title string Title of the floating window
---@param reason string Reason for closing
local function buf_close(bufnr, title, reason)
  vim.cmd.bwipeout(bufnr)
  util.notify(reason, title, 3)
end

setmetatable(Float, {
  __index = {
    ---@param title float_title
    ---@param height float_height
    ---@param width float_width
    ---@param border? float_border `single`|`double`|`rounded`|`solid`|`shadow`
    ---@param relative float_relative
    ---@param anchor float_anchor
    ---@param zindex float_zindex
    ---@param callback? float_callback
    ---@return table|nil `{bufnr: integer, opts: table}`
    _new = function(self, title, height, width, border, relative, anchor, zindex, callback)
      local opts = vim.deepcopy(self)
      local bufnr = vim.api.nvim_create_buf(false, true)
      local disp_width, disp_height = max_range()
      local buf_height

      opts.border = border or opts.border
      opts.relative = relative or opts.relative
      opts.anchor = anchor or opts.anchor
      opts.zindex = zindex

      if type(callback) == 'string' then
        opts.width = math.floor(disp_width * width)
        opts.height = math.floor(disp_height * height)
        opts.col = math.floor((disp_width - opts.width) / 2)
        opts.row = math.max(1, math.floor((disp_height - opts.height) / 2))
        opts.title = M.title(table.concat({ title, callback }, ' '), opts.width)

        return { bufnr = bufnr, opts = opts }
      end

      if not callback then
        buf_height = height
      else
        local contents = callback()

        if type(contents) ~= 'table' then
          vim.api.nvim_buf_set_lines(bufnr, 0, height, false, { contents })
        else
          if vim.tbl_isempty(contents) == 0 then
            buf_close(bufnr, title, 'empty')
            return
          end

          if vim.tbl_count(contents) <= 1 and table.concat(contents, ''):match('^%s*$') then
            buf_close(bufnr, title, 'nil')
            return
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
        opts.height = math.min(disp_height, buf_height)
        opts.col = math.floor((disp_width - opts.width) / 2)
        opts.row = math.max(1, math.floor((disp_height - opts.height) / 2))
      else
        opts.width = math.min(disp_width, width) or 15
        opts.height = 1
        opts.col = 1
        opts.row = 1
      end

      opts.title = M.title(title or HEADER, opts.width)
      vim.api.nvim_buf_set_name(bufnr, string.format('%s://%s', NAMESPACE, title))

      return { bufnr = bufnr, opts = opts }
    end,
  },
})

---Set keymap and function for the floating window
local function float_win_cmd_and_map()
  local function float_move(key)
    local count = vim.v.count
    local direction = {
      h = { row = -1, col = -2 - count },
      j = { row = 0 + count, col = -1 },
      k = { row = -2 - count, col = -1 },
      l = { row = -1, col = 0 + count },
    }

    local d = direction[key]
    vim.api.nvim_win_set_config(0, { relative = 'win', row = d.row, col = d.col })
  end

  map.buf_set(true, 'n', '<M-h>', function()
    float_move('h')
  end, 'Float shift left')
  map.buf_set(true, 'n', '<M-j>', function()
    float_move('j')
  end, 'Float shift right')
  map.buf_set(true, 'n', '<M-k>', function()
    float_move('k')
  end, 'Float shift down')
  map.buf_set(true, 'n', '<M-l>', function()
    float_move('l')
  end, 'Float shift up')
  map.ref_maps()
  map.quit_key()
end

---Set keymap for focus
local function float_win_focus_map()
  store_keymap = vim.fn.maparg(toggle_float, 'n', false, true)

  vim.api.nvim_set_option_value('winblend', _G.Mug.float_winblend, { win = 0 })
  vim.keymap.set('n', toggle_float, function()
    local bufs = util.get_bufs(string.format('%s://', NAMESPACE))
    local handle = 0

    for _, v in ipairs(bufs) do
      if v ~= vim.api.nvim_get_current_buf() then
        handle = vim.fn.bufwinid(v)
      end
    end

    if handle <= 0 then
      local key = handle == 0 and '<C-w>p' or toggle_float
      key = vim.api.nvim_replace_termcodes(key, true, false, true)
      vim.api.nvim_feedkeys(key, 'n', false)
    else
      vim.api.nvim_set_current_win(handle)
    end
  end, { desc = 'Focus Mug float window' })
end

---Processing after starting the floating window
---@param bufnr integer ID of floating window
---@param addition function Additional process
local function float_win_post(bufnr, addition)
  vim.api.nvim_buf_set_option(bufnr, 'bufhidden', 'wipe')
  float_win_cmd_and_map()

  if addition then
    addition()
  end
end

---Set autocmd for the floating window
---@param bufnr integer ID of the floating window
---@param leavecmd function Executed when a floating window is deleted
---@param terminal? boolean If the buffer is a therminal
local function float_win_autocmd(bufnr, leavecmd, terminal)
  local float_col = math.max(1, get_global('columns') - 30)
  local float_width = vim.api.nvim_win_get_width(0)
  local float_height = vim.api.nvim_win_get_height(0)
  local row, col = unpack(vim.api.nvim_win_get_position(0))

  local au_id_bufleave = vim.api.nvim_create_autocmd({ 'BufLeave' }, {
    group = 'mug',
    buffer = bufnr,
    callback = function()
      vim.api.nvim_win_set_option(0, 'winblend', 20)
      restore_highlights(ns_nc, 'normal')

      pcall(vim.api.nvim_win_set_config, 0, {
        relative = 'editor',
        row = 1,
        col = float_col,
        height = math.min(10, float_height),
        width = math.min(30, float_width),
      })

      if terminal then
        vim.api.nvim_win_set_cursor(0, { 10, 1 })
      end
    end,
    desc = 'Move the float to the edge when out of focus',
  })
  local au_id_bufenter = vim.api.nvim_create_autocmd({ 'BufEnter' }, {
    group = 'mug',
    buffer = bufnr,
    callback = function()
      restore_highlights(ns_nc, 'nc')

      if terminal then
        vim.cmd.startinsert()
      end

      vim.api.nvim_set_option_value('winblend', _G.Mug.float_winblend, { win = 0 })
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

      local float_exist = util.get_bufs(string.format('%s://', NAMESPACE))

      if #float_exist == 1 then
        local err = pcall(vim.fn.mapset, 'n', false, store_keymap)
        store_keymap = nil

        if not err then
          vim.keymap.del('n', toggle_float)
          restore_highlights(ns_nc, 'nc')
        end
      end

      if leavecmd then
        leavecmd()
      end
    end,
    desc = 'Additional processing performed when wipeout a floating-window',
  })
end

---@alias float_table table
---@alias float_num {bufnr?: integer, handle?: integer}

---Create the floating window
---@param bufnr integer ID of the floating window
---@param opts table Options of the floating window
---@return table float_num
local function create_float(bufnr, opts)
  local handle = vim.api.nvim_open_win(bufnr, true, opts)
  vim.cmd.clearjumps()

  return { bufnr = bufnr, handle = handle }
end

---Open the floating window
---@param tbl float_table
---@return table float_num
M.open = function(tbl)
  local win = Float:_new(tbl.title, tbl.height, tbl.width, tbl.border, 'editor', 'NW', 50, tbl.contents)

  if not win then
    return {}
  end

  local buf = create_float(win.bufnr, win.opts)

  vim.api.nvim_win_set_hl_ns(0, ns_nc)
  float_win_focus_map()
  float_win_post(buf.bufnr, tbl.post)
  float_win_autocmd(buf.bufnr, tbl.leave)

  return buf
end

---Open the floating window as a terminal
---@param tbl float_table
---@return table float_num
M.term = function(tbl)
  local cmd = tbl.cmd or ''
  local win = Float:_new(tbl.title, tbl.height, tbl.width, tbl.border, 'editor', 'NW', 50, tbl.cmd)
  NAMESPACE = 'MugTerm'

  if not win then
    return {}
  end

  local buf = create_float(win.bufnr, win.opts)

  util.termopen(cmd, buf)
  vim.api.nvim_win_set_hl_ns(0, ns_nc)
  float_win_focus_map()
  float_win_post(buf.bufnr, tbl.post)
  float_win_autocmd(buf.bufnr, tbl.leave, true)

  return buf
end

---Open the input-bar
---@param tbl float_table
---@return table float_num
M.input = function(tbl)
  local current_bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_set_option_value('winhighlight', 'NormalNC:Normal', { win = 0 })

  local win = Float:_new(tbl.title, 1, tbl.width, tbl.border, tbl.relative, tbl.anchor, 99, tbl.contents)
  local input_bar = win ~= nil and create_float(win.bufnr, win.opts) or {}
  win = nil

  vim.api.nvim_set_option_value('winblend', 0, { win = 0 })
  vim.api.nvim_win_set_hl_ns(0, ns_normal)
  float_win_post(input_bar.bufnr, tbl.post)
  map.input_keys()
  vim.cmd.startinsert({ bang = true })
  vim.api.nvim_create_autocmd({ 'WinEnter' }, {
    group = 'mug',
    once = true,
    buffer = current_bufnr,
    callback = function()
      -- restore_highlights(ns_normal, 'normal')
      vim.wo.winhighlight = nil
    end,
    desc = 'Clear winhighlight',
  })

  return input_bar
end

---Open the input-bar as a floating window
---@param tbl float_table
---@return table float_num
M.input_nc = function(tbl)
  local win = Float:_new(tbl.title, 1, tbl.width, tbl.border, tbl.relative, tbl.anchor, 99, tbl.contents)
  local input_bar = win ~= nil and create_float(win.bufnr, win.opts) or {}

  vim.api.nvim_set_option_value('winblend', 0, { win = 0 })
  map.input_keys()
  float_win_post(input_bar.bufnr, tbl.post)
  vim.cmd.startinsert({ bang = true })

  return input_bar
end

---Focus the floating window
---@param handle integer Handle of the floating window
---@return boolean # Whether the handle exists
M.focus = function(handle)
  return vim.fn.win_gotoid(handle) ~= 0
end

---Create the hints for the keymaps
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
