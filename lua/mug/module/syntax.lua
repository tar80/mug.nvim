---@class syntax
local M = {}

M.general = function()
  ---FIXME: In summary, there's some kind of error.
  vim.api.nvim_command([[syntax region None start="="hs=s+1 end="$" contains=String,Boolean,Number,Delimiter]])
  vim.api.nvim_command([[
    syntax match Number excludenl "\d\+$" contained
    syntax match Delimiter "=" contained
    syntax match Delimiter ","
    syntax region String start='"' end='"' keepend
    syntax region String start='`' end='`' keepend
    syntax keyword Boolean true false
  ]])
  vim.api.nvim_command([[syntax region Comment start="^\s\+--[- ][^ ]" end="$"]])
end

M.index = function()
  vim.api.nvim_command([[
    syn match MugIndexHeader "^\s##\s.\+$" display
    syn match MugIndexUnstage "^\s.[MADRC]\s" display
    syn match MugIndexStage "^\s[MADRC]" display
    syn match MugIndexUnstage "^\s[?!U]\{2}" display
  ]])
end

M.log = function()
  vim.api.nvim_command([[
    syntax match MugLogHash "^\s\?\w\{7,8}" display
    syntax match MugLogHash "^\scommit\s\w\+$" display
    syntax match MugLogDate "\d\{4}-\d\d-\d\d" display
    syntax match MugLogDate "\sAuthor:\s.\+$" display
    syntax match MugLogOwner "<\w\+>" display
    syntax match MugLogOwner "\sDate:\s.\+$" display
    syntax match MugLogHead "(HEAD\s->\s.\+)" display
  ]])
end

M.diff = function()
  vim.api.nvim_command([[
    syntax match Directory "^\sdiff\s--git\s.\+$"
    syntax match Special "^\s@@\s[0-9\-+, ]\+\s@@"
    syntax region DiffChange start="^\s+[^+]"hs=s+1 end="$"
    syntax region DiffDelete start="^\s-[^-]"hs=s+1 end="$"
  ]])
end

M.stats = function()
  vim.api.nvim_command([[
      syntax match diffRemoved "-\+$" display
      syntax match diffChanged "+\+\(-\+\)\?$" contains=diffRemoved keepend
      syntax match Comment "\s|\s" display
      syntax match Special "(new)" display
    ]])
end

M.rebase = function()
  vim.api.nvim_command([[syntax match Comment "^\%^.\+$" display]])
end

return M
