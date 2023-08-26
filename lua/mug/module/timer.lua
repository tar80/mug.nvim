---@class timer
---@field set function
---@field discard function
local M = {}
local time_tbl = {}
local start_wait = 0

---@param timer userdata Timer thread
---@param winid number Window handle
local function close(timer, winid)
  timer:stop()
  timer:close()
  time_tbl[winid] = nil
end

---@param winid number Window handle
---@param timeout number Waiting time
---@param interval number Interval until next run
---@param callback function Timer content
---@param post function Post process
M.set = function(winid, timeout, interval, callback, post)
  local timer = vim.uv.new_timer()
  local i = 1

  timer:start(
    start_wait,
    timeout + interval,
    vim.schedule_wrap(function()
      if not vim.api.nvim_win_is_valid(winid) then
        if post then
          post()
        end

        close(timer, winid)
        return
      end

      local stop = callback(i, timeout)

      if stop then
        close(timer, winid)
        return
      end

      i = i + 1
    end)
  )
  time_tbl[winid] = timer
  start_wait = 0
end

---@param winid number Window handle
---@param callback function Post process
M.discard = function(winid, callback)
  local bss = time_tbl[winid]
  if bss and vim.uv.is_active(bss) then
    close(bss, winid)
    callback()
    start_wait = 100
  end
end

return M
