local timer = require('mug.module.timer')

---@class extmark
---@field release_line function
---@field select_line function
---@field virtual_txt function
---@field clear_ns function
---@field warning function
local M = {}
local ns_error = vim.api.nvim_create_namespace('MugExtmark')
local get_line = vim.api.nvim_buf_get_lines

---@param row number Cursor line number
---@param col number Extmark start column
---@param hl string Highlight group
---@param ns number Namespace
---@return table # {ext_id = extmark id, line_num = line number, contents = string linewise}
local function _select(row, col, hl, ns)
  local contents = get_line(0, row - 1, row, false)[1]
  local linelen = contents == '' and 0 or vim.api.nvim_strwidth(contents)
  col = math.min(col, linelen)
  local extid = vim.api.nvim_buf_set_extmark(0, ns, row - 1, col, {
    end_row = row - 1,
    end_col = linelen,
    hl_group = hl,
  })

  return { ext_id = extid, line_num = row, hl_group = hl, contents = contents:sub(col + 1) }
end

---@param ln number Element number of table(Selection)
---@param ns number Namespace
---@param selection table Select lines information
M.release_line = function(ln, ns, selection)
  local lnum = ln or vim.api.nvim_win_get_cursor(0)[1]

  for index, value in ipairs(selection) do
    if value.line_num == lnum then
      vim.api.nvim_buf_del_extmark(0, ns, value.ext_id)
      table.remove(selection, index)
      break
    end
  end

  return selection
end


---@param row number Current line number
---@param col number Extmark start column
---@param ns number Namespace
---@param selection table Select line information
---@param hl string Highlight group
---@return table selection
M.select_line = function(row, col, ns, selection, hl)
  row = row or vim.api.nvim_win_get_cursor(0)[1]
  col = col or 0

  for i, v in ipairs(selection) do
    if v.line_num == row then
      vim.api.nvim_buf_del_extmark(0, ns, v.ext_id)
      table.remove(selection, i)
      return selection
    end
  end

  table.insert(selection, _select(row, col, hl, ns))

  return selection
end

---@param row number Current line number
---@param col number Extmark start column
---@param ns number Namespace
---@param msg string virtual text
---@param hl string highlight group
M.virtual_txt = function(bufnr, row, col, ns, msg, hl)
  row = row or vim.api.nvim_win_get_cursor(0)[1]
  col = col or 0

  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_set_extmark(bufnr, ns, row - 1, col, {
      priority = 51,
      virt_text = { { msg, hl } },
      virt_text_pos = 'overlay',
      hl_mode = 'combine',
    })
  end
end

---@param bufnr number Target buffer
---@param ns number Namespace
---@param start number Start of range of lines to clear
---@param last number End of range of lines to clear
M.clear_ns = function(bufnr, ns, start, last)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, start, last)
  end
end

---@param messages table Error messages
---@param level number Error level
---@param row number Line to put virtual text
M.warning = function(messages, level, row)
  local winid = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_get_current_buf()
  local header, msg
  local msg_count = #messages
  local wait, delay = 4000, 400
  local hlname = level > 3 and 'ErrorMsg' or 'WarningMsg'

  timer.discard(winid, function()
    M.clear_ns(bufnr, ns_error, 0, -1)
  end)
  timer.set(winid, wait, delay, function(i, timeout)
    if i > msg_count then
      return true
    end


    header = msg_count > 1 and string.format('(%s/%s)', i, msg_count) or '!'
    msg =  header .. messages[i]

    M.virtual_txt(bufnr, row, 0, ns_error, msg, hlname)
    vim.defer_fn(function()
      M.clear_ns(bufnr, ns_error, 0, -1)
    end, timeout)
  end)
end

return M
