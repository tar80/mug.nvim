---@class syntax
local M = {}

M.general = function()
  ---FIXME: In summary, there's some kind of error.
  vim.cmd([[syntax region None start="="hs=s+1 end="$" contains=String,Boolean,Number,Delimiter]])
  vim.cmd([[
    syntax match Number excludenl "\d\+$" contained
    syntax match Delimiter "=" contained
    syntax match Delimiter ","
    syntax keyword Boolean true false
  ]])
  vim.cmd([[syntax region Comment start="^\s\+--[- ][^ ]" end="$"]])
end

M.index = function()
  vim.cmd([[
    syn match MugIndexHeader "^\s\?##\s.\+$" display
    syn match MugIndexUnstage "^\s\?.[MADRC]\s" display
    syn match MugIndexStage "^\s\?[MADRC]" display
    syn match MugIndexUnstage "^\s\?[?!U]\{2}" display
  ]])
end

M.log = function()
  vim.cmd([[
    syntax match MugLogHash "^\s\?\w\{7,8}\s" display
    syntax match MugLogHash "^\s\?commit\s\w\+$" display
    syntax match MugLogDate "\d\{4}-\d\d-\d\d" display
    syntax match MugLogDate "\sAuthor:\s.\+$" display
    syntax match MugLogOwner "<\w\+>" display
    syntax match MugLogOwner "\sDate:\s.\+$" display
    syntax match MugLogHead "(HEAD\s->\s.\+)" display
  ]])
end

M.diff = function()
  vim.cmd([[
    syntax match Error "^\s\?diff\s--git\s.\+$"
    syntax match Error "^\s\?index\s\w\+\.\..\+$"
    syntax match Directory "^\s\?@@\s[0-9\-+, ]\+\s@@"
    syntax region DiffChanged start="^\s\?+[^+]"hs=s+1 end="$"
    syntax region DiffRemoved start="^\s\?-[^-]"hs=s+1 end="$"
  ]])
end

M.stats = function()
  vim.cmd([[
      syntax match diffRemoved "-\+$" display
      syntax match diffChanged "+\+\(-\+\)\?$" contains=diffRemoved keepend
      syntax match Comment "\s|\s" display
      syntax match Special "(new)" display
    ]])
end

M.rebase = function()
  vim.cmd([[syntax match Comment "^\%^.\+$" display]])
end

return M
