local wd = vim.fn.expand("%:p:h:h")
vim.opt.runtimepath:append(wd)
---commands must be default name
local edit_cmd = vim.fn.exists(':Edit')
local file_cmd = vim.fn.exists(':File')
local write_cmd = vim.fn.exists(':Write')
package.loaded['mug'] = nil
package.loaded['mug.workspace'] = nil
package.loaded['mug.config'] = nil
local mug = require('mug')
local config = require('mug.config')
local ws = require('mug.workspace')

describe('user setup', function()
  it('additional root patterns', function()
    local expect = 'pack.json,node_modules/'
    mug.setup({ variables = { root_patterns = { 'pack.json', 'pack.json', 'node_modules/' } } })
    assert.equals(expect, table.concat(_G.Mug.root_patterns, ','))
  end)
  it('additional ignore files', function()
    local expect = 'git,gitcommit,gitrebase,lua'
    mug.setup({ variables = { ignore_filetypes = { 'lua' } } })
    assert.equals(expect, table.concat(_G.Mug.ignore_filetypes, ','))
  end)
  it('init variables', function()
    config.init()
    local expect = '.git/,.gitignore'
    assert.equals(expect, table.concat(_G.Mug.root_patterns, ','))
  end)
end)

describe('findroot', function()
  it('changed root', function()
    vim.api.nvim_command('silent lcd %:p:h')
    assert.equals('change', ws.set_workspace_root())
  end)
  it('skip same root', function()
    assert.equals('same', ws.set_workspace_root())
  end)
  it('ignore nofile buffer', function()
    vim.api.nvim_buf_set_option(0, 'buftype', 'nofile')

    assert.equals('special', ws.set_workspace_root(false))
    vim.api.nvim_buf_set_option(0, 'buftype', '')
  end)
  it('ignore filetype', function()
    vim.api.nvim_buf_set_option(0, 'filetype', 'git')
    assert.equals('ignore', ws.set_workspace_root())
    vim.api.nvim_buf_set_option(0, 'filetype', 'lua')
  end)
  it('set mug_findroot_disable', function ()
    vim.api.nvim_command('MugFindroot stopglobal')
    assert.equals(true, vim.g.mug_findroot_disable)
  end)
  it('stop mug_findroot globally', function ()
    local pwd = vim.fn.expand('%:p:h')
    vim.api.nvim_command('chdir ' .. pwd .. '|tabnew|let g:mug_test_findroot=getcwd()')
    assert.equals(pwd, vim.g.mug_test_findroot)
    vim.api.nvim_command('tabclose|unlet g:mug_test_findroot')
    ws.set_workspace_root()
  end)
end)

vim.opt.runtimepath:remove(wd)
if edit_cmd ~= 2 then
  vim.api.nvim_del_user_command('Edit')
end
if file_cmd ~= 2 then
  vim.api.nvim_del_user_command('File')
end
if write_cmd ~= 2 then
  vim.api.nvim_del_user_command('Write')
end
