---@see https://qiita.com/iigura/items/7f337ac766935d1dbcee

local util = require('mug.module.util')

---General mug settings
_G.Mug = {}

---@class Mug
---Table for storing protected variables
---@field _def function Set default value
---@field _ow function Overwrite value
local tbl_const = {}

local HEADER = 'mug/protect'

---Set default variable
---@param name string Protect field name
---@param value any Protect field value
---@param quiet? boolean Run quietly
function tbl_const._def(name, value, quiet)
  if _G.Mug[name] ~= nil then
    local msg = string.format('"%s" is already defined', name)
    return not quiet and util.notify(msg, HEADER, 3, false)
  end

  _G.Mug[name] = nil
  tbl_const[name] = value
end

---Override default variable
---@param name string protect field name
---@param value any protect field value
function tbl_const._ow(name, value)
  tbl_const[name] = value
end

setmetatable(_G.Mug, {
  __index = tbl_const,

  ---@param name string new field name
  ---@param value any new field value
  __newindex = function(self, name, value)
    if tbl_const[name] ~= nil then
      local msg = string.format('"%s" is protected', name)
      util.notify(msg, HEADER, 3, false)
      return
    end

    rawset(self, name, value)
  end,
})
