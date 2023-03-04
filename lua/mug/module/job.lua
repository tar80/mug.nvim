---@see https://github.com/ms-jpq/lua-async-await

---@class job
---@field async function
---@field await function
local M = {}

---@param command table Shell-command and options
---@return function thunk Async job
local async_job = function(command)
  local thunk = function(step)
    local result = {}
    local errorlevel = 2

    vim.fn.jobstart(command, {
      on_stdout = function(_, data)
        if data[1] ~= '' then
          result = vim.list_extend(result, data)
        end
      end,

      on_stderr = function(_, data)
        if data[1] ~= '' then
          errorlevel = 3
          result = vim.list_extend(result, data)
        end
      end,

      on_exit = function()
        step(result, errorlevel)
      end,
    })
  end

  return thunk
end

---@param func function Coroutine thread
---@param callback? function Post-processing thread
M.async = function(func, callback)
  assert(type(func) == 'function', 'type error :: expected func')

  local thread = coroutine.create(func)
  local step = nil

  step = function(...)
    local stat, ret = coroutine.resume(thread, ...)
    assert(stat, ret)

    if coroutine.status(thread) == 'dead' then
      (callback or function(ret) end)(ret)
    else
      assert(type(ret) == 'function', 'type error :: expected func')
      ret(step)
    end
  end

  step()
end


---@param command table Shell-command and options
---@return table stdout, number loglevel
M.await = function(command)
  return coroutine.yield(async_job(command))
end

return M
