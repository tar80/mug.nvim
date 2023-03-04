local wd = vim.fn.expand("%:p:h:h")
vim.opt.runtimepath:append(wd)

package.loaded["mug"] = nil
package.loaded["mug.config"] = nil
package.loaded["mug.branch"] = nil

local branch = require("mug.branch")

describe("method branch_name", function()
  local hash
  before_each(function ()
    hash = branch.branch_name(vim.fn.getcwd())
  end)

  vim.cmd.lchdir("c:/")
  it("current directory is not repository", function()
    assert.is_same("", hash)
  end)

  vim.cmd.lchdir(wd)
  it("branch_cache_key[save]", function()
    assert.is_same("saved", hash)
  end)

  it("branch_cache_key[cache]", function()
    assert.is_same("cached", hash)
  end)
end)

vim.opt.runtimepath:remove(wd)
