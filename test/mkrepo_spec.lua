vim.opt.runtimepath:append(vim.fn.expand('%:p:h:h'))
package.loaded['mug'] = nil
package.loaded['mug.mkrepo'] = nil
package.loaded['mug.util'] = nil

require('mug.mkrepo')
local util = require('mug.module.util')

vim.g.mug_debug = true

local temp_name = 'mugmkrepo'
local temp_dir = util.normalize(vim.fn.tempname(), '/')
temp_dir = temp_dir:gsub('(.+/).+', '%1') .. temp_name
local pwd = util.pwd()
local msg = Mug.commit_initial_message
local remote = Mug.remote_url
local test_url = 'https://github.com/test'
Mug._ow('commit_initial_message', '')
Mug._ow('remote_url', test_url)

describe('do mkrepo', function()
  Mug._ow('loglevel', 0)
  vim.cmd('MugMkrepo ' .. temp_dir)

  vim.wait(200, function()
    return false
  end)

  local repo_exist = vim.fn.isdirectory(temp_dir .. '/.git')

  it('make repository', function()
    assert.equals(repo_exist, 1)
  end)

  vim.wait(200, function()
    return false
  end)

  local remote_url = vim.fn.systemlist('git -C ' .. temp_dir .. ' config --local remote.origin.url')

  it('remote add origin url', function()
    local repo_url = test_url .. '/' .. temp_name .. '.git'
    assert.equals(repo_url, remote_url[1])
  end)

  vim.wait(200, function()
    return false
  end)

  local log = vim.fn.systemlist('git -C ' .. temp_dir .. ' log -1 --color=never --format=%s')

  vim.wait(200, function()
    return false
  end)

  it('initial empty commit', function()
    assert.equals('Initial commit', table.concat(log, ''))
  end)

  it('changed working directory', function()
    local wd = Mug.loglevel == 2 and temp_dir or pwd
    assert.equals(wd, util.pwd())
  end)
end)

vim.g.mug_debug = nil
Mug._ow('commit_initial_message', msg)
Mug._ow('remote_url', remote)
vim.cmd.lch(pwd)
