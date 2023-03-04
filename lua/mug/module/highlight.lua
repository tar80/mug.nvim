---@class hl
---@field shade function Change the shade of the specified highlight
---@field link function Link to the specified highlight
local M = {}

---@alias ratio integer Percentage to increace or decreace

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

---@param hlname string Name of highlight
---@param red integer Incremental ratio of red
---@param green integer Incremental ratio of green
---@param blue integer Incremental ratio of blue
---@return string # Color-code in decimal notation
M.shade = function(hlname, red, green, blue)
  local decimal = vim.api.nvim_get_hl_by_name(hlname, true).background or 0
  local r = adjust_color(decimal, 'red', red)
  local g = adjust_color(decimal, 'green', green)
  local b = adjust_color(decimal, 'blue', blue)

  return string.format('#%02x%02x%02x', r, g, b)
end

---@param namespace number
---@param name string Name of the highlight
---@param linkname string Name of the link to highlight
M.link = function(namespace, name, linkname)
  vim.api.nvim_set_hl(namespace, name, { link = linkname })
end

return M
