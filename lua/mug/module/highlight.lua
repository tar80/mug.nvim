---@class hl
local M = {}
---@type {[string]: table}
local stored_hl = {}
---@type function[]
local stored_func = {}

---@alias ns integer Namespace
---@alias hlname string Highlight name
---@alias ratio integer Percentage to increace or decreace
---@alias opts {ns: integer, hl: table} Highlight options

---@param int ratio
---@return integer # Incremental value
local function ratio_calculate(int)
  return math.floor(int * 255 / 100)
end

---@param decimal integer Background color in decimal notation
---@param color string The name of primary color
---@param int ratio
---@return integer # Value of the primary color
local function adjust_color(decimal, color, int)
  local digit = { red = { 1, 2 }, green = { 3, 4 }, blue = { 5 } }
  local intensity = string.format('%06x', decimal):sub(unpack(digit[color]))
  local merged = tonumber(intensity, 16) + ratio_calculate(int)

  return merged > 0 and math.min(255, merged) or 0
end

---@param options opts
---@return table opts
local function unity_fields(options)
  local items = { bg = 'background', fg = 'foreground' }

  for k, v in pairs(items) do
    if options[v] then
      options[k] = options[v]
      options[v] = nil
    end
  end

  return options
end

---Increments the field values of the specified hlgroup by a percentage
---@param ns integer Namespace
---@param name hlname
---@param red integer Incremental ratio of red
---@param green integer Incremental ratio of green
---@param blue integer Incremental ratio of blue
---@return string # Color-code in decimal notation
M.shade = function(ns, name, red, green, blue)
  local hl_tbl = vim.api.nvim_get_hl(ns, { name = name })
  local decimal
  if hl_tbl.bg then
    decimal = hl_tbl.bg
  elseif hl_tbl.link then
    decimal = vim.api.nvim_get_hl(ns, { name = hl_tbl.link }).bg or 0
  else
    decimal = 0
  end

  local r = adjust_color(decimal, 'red', red)
  local g = adjust_color(decimal, 'green', green)
  local b = adjust_color(decimal, 'blue', blue)

  return string.format('#%02x%02x%02x', r, g, b)
end

---Record hlgroup settings
---@param name hlname
---@param options opts
M.record = function(name, options)
  if stored_hl[name] then
    return
  end

  local hl = unity_fields(options.hl)
  stored_hl = vim.tbl_deep_extend('force', stored_hl, { [name] = { ns = options.ns, opts = hl } })
end

---Record and set hlgroup after applying a colorscheme
---@param callback function
M.late_record = function(callback)
  table.insert(stored_func, callback)
end

---Record and set hlgroup setting
---@param name hlname
---@param options opts
M.set_hl = function(name, options)
  vim.api.nvim_set_hl(options.ns, name, options.hl)
  M.record(name, options)
end

---Update stored_hl
---@param items table|nil Hlgroup settings
M.customize = function(items)
  if not items then
    return
  end

  for k, v in pairs(items) do
    v = unity_fields(v)
    stored_hl[k] = { ns = 0, opts = v }
  end
end

---Setup highlights
local post_process = function()
  for _, func in ipairs(stored_func) do
    func()
  end

  vim.api.nvim_create_autocmd('ColorScheme', {
    group = 'mug',
    pattern = '*',
    callback = function()
      M.init()
    end,
    desc = 'Setup mug highlights',
  })
end

---Defer setup highlights at vim startup
---@param callback function hlgroup settings
M.lazy_load = function(callback)
  if vim.g.colors_name then
    callback()
    post_process()
  else
    vim.api.nvim_create_autocmd('ColorScheme', {
      group = 'mug',
      pattern = '*',
      once = true,
      callback = function()
        callback()
        post_process()
      end,
      desc = 'Lazy setup the mug highlights',
    })
  end
end

M.init = function()
  for name, hl in pairs(stored_hl) do
    vim.api.nvim_set_hl(hl.ns, name, hl.opts)
  end
end

return M
