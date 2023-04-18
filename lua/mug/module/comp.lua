local util = require('mug.module.util')

---@class comp
---@field filter function Narrow down the target from completion candidates
---@field branches function Extract branch names
---@field files function Extract the path under the specified directory
---@field commit_prefix function
local M = {}

---@param a string Arglead
---@param l string Cmdline
---@param list table Complition list
---@return table # Candidates corresponding to the typed string
M.filter = function(a, l, list)
  if not list or vim.tbl_isempty(list) or l:find('!$') then
    return {}
  end

  local candidates = {}

  for _, item in ipairs(list) do
    if vim.startswith(item, a) then
      table.insert(candidates, item)
    end
  end

  return candidates
end

---@return table # Branch names
M.branches = function()
  local parent = util.pwd() .. '/.git/refs/heads'

  if vim.fn.isdirectory(parent) == 0 then
    return {}
  end

  local branches = {}

  for file in vim.fs.dir(parent) do
    table.insert(branches, file)
  end

  return branches
end

---@param dir string Specified directory path
---@return table # Paths under the specified directory
M.files = function(dir)
  local paths = {}
  local fd = vim.loop.fs_scandir(dir)

  while true do
    local name = vim.loop.fs_scandir_next(fd)

    if not name then
      break
    end

    table.insert(paths, name)
  end

  return paths
end

M.commit_prefix = function ()
  local template = require('mug.template.' .. _G.Mug.commit_notation).abbrev
  local prefixes = {}

  for _, v in pairs(template) do
    table.insert(prefixes, v)
  end

  return prefixes
end

return M
