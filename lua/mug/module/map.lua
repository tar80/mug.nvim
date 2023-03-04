---@class map
---@field buf_set function
---@field buf_del function
---@field quit_key function
---@field input_keys function
---@field ref_maps function
local M = {}

---@alias buffer boolean|number
---@alias keymode string|table
---@alias usekey string|table

---@param bufnr buffer Value of option buffer
---@param mode keymode Target key-mode
---@param key usekey Target key
---@param callback string|function Ex command or function
---@param description string
M.buf_set = function(bufnr, mode, key, callback, description)
  if type(key) ~= 'table' then
    vim.keymap.set(mode, key, callback, { silent = true, buffer = bufnr, desc = description })
    return
  end

  for _, v in ipairs(key) do
    vim.keymap.set(mode, v, callback, { silent = true, buffer = bufnr, desc = description })
  end
end

---@param bufnr buffer Value of option buffer
---@param mode keymode Target key-mode
---@param key usekey Target key
M.buf_del = function(bufnr, mode, key)
  if type(key) ~= 'table' then
    vim.keymap.del(mode, key, { buffer = bufnr })
    return
  end

  for _, v in ipairs(key) do
    vim.keymap.del(mode, v, { buffer = bufnr })
  end
end

---@param tab? boolean Whether to exit the tab
M.quit_key = function(tab)
  local close = tab and 'tabclose' or 'close'
  local cmd = '<Cmd>' .. close .. '<CR>'

  M.buf_set(true, 'n', { 'q', '<Esc>' }, cmd, 'Close buffer')
end

M.input_keys = function()
  M.buf_set(true, 'i', '<C-A>', '<HOME>')
  M.buf_set(true, 'i', '<C-E>', '<END>')
  M.buf_set(true, 'i', '<ESC>', '<ESC>:quit<CR>')
  M.buf_set(true, 'i', '<C-c>', '<ESC>:quitCR>')
end

M.ref_maps = function()
  M.buf_set(true, 'n', 'g?', require('mug.module.float').maps, 'Refs keymaps')
end

return M
