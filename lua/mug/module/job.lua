--[[
-- This code based on the lua-async-await(https://github.com/ms-jpq/lua-async-await)
-- Under the MIT license
--]]

local util = require('mug.module.util')
local map = require('mug.module.map')
local shell = require('mug.module.shell')

---@class job
local M = {}

---Sub process of the job.async. Asynchronous execution job
---@async
---@param command table Shell-command and options
---@return function thunk Async job
local async_job = function(command)
  local thunk = function(step)
    local result = {}
    local loblevel = 2

    vim.fn.jobstart(command, {
      on_stdout = function(_, data)
        if data[1] ~= '' then
          result = vim.list_extend(result, data)
        end
      end,

      on_stderr = function(_, data)
        if data[1] ~= '' then
          loblevel = 3
          result = vim.list_extend(result, data)
        end
      end,

      on_exit = function()
        step(loblevel, result)
      end,
    })
  end

  return thunk
end

---@type JobTerm
local Term = {
  name = 'Mug://',
  filetype = 'gitresult',
  listed = false,
  pos = 'botright',
  row = 1,
  code = 0,
  signal = 0,
  stdout = {},
  stderr = {},
}
local new = function(self)
  self.bufnr = vim.api.nvim_create_buf(false, true)
  util.nofile(self.bufnr, self.listed, 'wipe', 'nofile')
  vim.api.nvim_set_option_value('filetype', self.filetype, { buf = self.bufnr })
  map.buf_set(self.bufnr, 'n', { 'q' }, '<Cmd>q!<CR>', 'Close buffer')
  vim.api.nvim_buf_set_keymap(self.bufnr, 'n', 'o', 'callback', {
    callback = function()
      local path = vim.fn.expand('<cfile>')
      local winid = vim.fn.bufwinid('#')

      if winid ~= -1 then
        vim.api.nvim_win_call(winid, function()
          vim.cmd.edit(path)
        end)
        vim.cmd.balt(path)
      end
    end,
  })
  map.buf_set(self.bufnr, 'n', { 'a', 'A', 'i', 'I', 'r', 'R', 'c', 'C' }, '<Nop>', 'Ignore insert-mode')
  vim.api.nvim_buf_set_keymap(self.bufnr, 'n', '<CR>', 'callback', {
    callback = function()
      local path = vim.fn.expand('<cfile>')
      if vim.fn.filereadable(path) == 1 then
        vim.cmd.bwipeout({ bang = true })
        vim.cmd.edit(path)
      end
    end,
  })
end

local std = (function()
  ---@type integer|nil
  local nl
  ---@type '\r\n'|nil
  local replace_nl = util.is_win and '\r\n' or nil

  return function(self, output, data)
    if data then
      table.insert(self[output], data)
      data, nl = data:gsub('\n', function()
        return replace_nl
      end)
      self.row = self.row + nl
      nl = nil
      vim.schedule(function()
        vim.api.nvim_chan_send(self.chan, data)
      end)
    end
  end
end)()

---@alias BufTerm {name: string, listed?: boolean, filetype?: string, pos?: string, termopen?: boolean}
---Sub process of the job.async. Asynchronous execution job on terminal
---@async
---@param command table Shell-command and options
---@param tbl BufTerm
---@return function thunk Async job
local async_term = function(command, tbl)
  ---@type JobTerm
  local _term = vim.deepcopy(Term)
  local self = setmetatable(_term, { __index = { _new = new, _std = std } })

  for key, value in pairs(tbl) do
    self[key] = value
  end

  self:_new()

  if tbl.termopen then
    vim.cmd.stopinsert()
    vim.cmd(string.format('noautocmd -tab buffer %s', self.bufnr))
    local server = shell.get_server()
    shell.set_env('NVIM_MUG_SERVER', server)
    shell.nvim_client('GIT_EDITOR')
    util.termopen(command, self.bufnr)
    -- vim.fn.termopen(command, {
    --   on_exit = function()
    --     vim.cmd.bwipeout({ bang = true })
    --   end,
    -- })
    vim.api.nvim_buf_set_name(self.bufnr, self.name)

    return function() end
  end

  self.chan = vim.api.nvim_open_term(self.bufnr, {
    on_input = function()
      return vim.cmd.stopinsert()
    end,
  })

  local thunk = function(step)
    vim.system(command, {
      text = true,
      stdout = function(_, data)
        self:_std('stdout', data)
      end,
      stderr = function(_, data)
        self:_std('stderr', data)
      end,
    }, function(obj)
      vim.schedule(function()
        if self.row == 1 then
          vim.api.nvim_buf_delete(self.bufnr, { force = true })
          self.bufnr = 0
        else
          vim.cmd.stopinsert()
          vim.cmd(string.format('noautocmd %s sbuffer %s', self.pos, self.bufnr))
          vim.api.nvim_win_set_height(0, self.row)
          vim.api.nvim_buf_set_name(self.bufnr, self.name)
          vim.o.signcolumn = 'no'
          vim.o.foldcolumn = '0'
          vim.cmd.clearjumps()
        end

        self.code = obj.code
        self.signal = obj.signal
        local loglevel = (obj.code == 0) and 2 or 3
        step(loglevel, self)
      end)
    end)
  end

  return thunk
end

---Sub process of the job.async. Asynchronous execution job on terminal
---@async
---@param command table Shell-command and options
---@return function thunk Async job
local async_resp = function(command)
  local thunk = function(step)
    vim.system(command, {
      text = true,
    }, function(obj)
      vim.schedule(function()
        local loglevel = (obj.code == 0) and 2 or 3
        local resp = loglevel and obj.stdout or obj.stderr
        step(loglevel, { resp })
      end)
    end)
  end

  return thunk
end

---Asynchronous execution process
---@async
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

---Wait for the result of the async job
---@param command table Shell-command and options
---@return integer loglevel, table stdout
M.await = function(command)
  return coroutine.yield(async_resp(command))
end

---Wait for the result of the async job
---@param command table Shell-command and options
---@return integer loglevel, table stdout
M.await_job = function(command)
  return coroutine.yield(async_job(command))
end

---Wait for the result of the async job
---@param tbl BufTerm
---@param command table Shell-command and options
---@return integer loglevel, table BufTerm
M.await_term = function(command, tbl)
  return coroutine.yield(async_term(command, tbl))
end

return M
