local wd = vim.fn.expand("%:p:h:h")
vim.opt.runtimepath:append(wd)
package.loaded["mug.module.protect"] = nil

local saved = getmetatable(Mug)

require("mug.module.protect")

describe("protected variable", function()
  it("new variable", function()
    Mug._def("test", true)
    assert.equals(true, Mug.test)
  end)

  it("do not allows change variable", function()
    Mug._def("test", false)
    assert.equals(true, Mug.test)
  end)

  it("overwrite variable", function()
    Mug._ow("test")
    assert.equals(nil, Mug.test)
  end)
end)

setmetatable(Mug, saved)
vim.opt.runtimepath:remove(wd)
