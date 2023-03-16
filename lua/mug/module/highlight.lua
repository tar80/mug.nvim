---@class hl
---@field shade function Change the shade of the specified highlight
---@field store function Store highlight-group setting
---@field set function Setup the specified highlight
---@field customize function Customize the specified highlights
---@field lazy_load function Highlights set after applying a colorscheme
---@field init function Mug-specific highlight preferences
local M = {}
local stored_hl = {}

---@alias ratio integer Percentage to increace or decreace
---@alias ns number Namespace
---@alias hlname string Highlight name
---@alias opts table Highlight options

---@param int ratio
---@return integer # Incremental value
local function ratio_calculate(int)
  return math.floor(int * 255 / 100)
end

---@param decimal integer Background color in decimal notation
---@param color string The name of primary color
---@param int ratio
---@return number # Value of the primary color
local function adjust_color(decimal, color, int)
  local digit = { red = { 1, 2 }, green = { 3, 4 }, blue = { 5 } }
  local intensity = string.format('%06x', decimal):sub(unpack(digit[color]))
  local merged = tonumber(intensity, 16) + ratio_calculate(int)

  return merged > 0 and math.min(255, merged) or 0
end

---@param options opts
---@return table options
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

---@param name hlname
---@param red integer Incremental ratio of red
---@param green integer Incremental ratio of green
---@param blue integer Incremental ratio of blue
---@return string # Color-code in decimal notation
M.shade = function(name, red, green, blue)
  local decimal = vim.api.nvim_get_hl_by_name(name, true).background or 0
  local r = adjust_color(decimal, 'red', red)
  local g = adjust_color(decimal, 'green', green)
  local b = adjust_color(decimal, 'blue', blue)

  return string.format('#%02x%02x%02x', r, g, b)
end

---@param name hlname
---@param options opts
M.store = function(name, options)
  options = unity_fields(options)
  stored_hl = vim.tbl_deep_extend('force', stored_hl, { [name] = { opts = options } })
end

---@param name hlname
---@param options opts
---@param keep? boolean Table merge behavior choose "keep"
M.set = function(name, options, keep)
  local behavior = keep and 'keep' or 'force'
  options = unity_fields(options)
  stored_hl = vim.tbl_deep_extend(behavior, stored_hl, { [name] = { opts = options } })

  vim.api.nvim_set_hl(0, name, stored_hl[name].opts)
end

---@param items table Hl-group settings
M.customize = function(items)
  if not items then
    return
  end

  for k, v in pairs(items) do
    M.store(k, v)
  end
end

---@param callback function Hl-group settings
M.lazy_load = function(callback)
  if vim.g.colors_name then
    callback()
  else
    vim.api.nvim_create_autocmd('CursorHold', {
      group = 'mug',
      pattern = '*',
      once = true,
      callback = function()
        callback()
      end,
      desc = 'Lazy setup mug highlights',
    })
  end
end

M.init = function()
  for k, v in pairs(stored_hl) do
    if vim.fn.hlexists(k) == 1 and not vim.api.nvim_get_hl_by_name(k, true)[true] then
      M.store(k, vim.api.nvim_get_hl_by_name(k, {}))
    else
      vim.api.nvim_set_hl(0, k, v.opts)
    end
  end
end

return M
