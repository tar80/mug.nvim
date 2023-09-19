local util = require('mug.module.util')
local job = require('mug.module.job')
local comp = require('mug.module.comp')
local tbl = require('mug.module.table')
local float = require('mug.module.float')
local syntax = require('mug.module.syntax')

---@class Mug
require('mug.module.protect')

local HEADER = 'Mug'
local buffer_id = 0
local float_handle = 0

---Float-window syntaxs
local show_syntax = function()
  syntax.general()
  syntax.log()
  syntax.diff()
  syntax.stats()
end

---CompleteList of command Mag
---@param _ string Arglead
---@param l string Cmdline
---@return table CompleteList
local function complist(_, l)
  local input = vim.split(l, ' ', { plain = true })

  if #input <= 2 then
    return util.is_repo(HEADER) and tbl.sub_commands or { 'init', 'clone' }
  end

  local options = tbl[string.format('%s_options', input[2])]

  return options and options or {}
end

---Set the keymap for the Mug result buffer
---@param bufnr integer Buffer number
local function setmap(bufnr)
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'p', 'callback', {
    callback = function()
      if float.focus(float_handle) then
        return
      end

      local word = vim.fn.expand('<cword>')

      if not word:find('[^%w]') then
        job.async(function()
          ---@type integer, table
          local loglevel, result
          loglevel, result = job.await_job(util.gitcmd({ cmd = 'show', opts = { word } }))

          if loglevel == 2 then
            float_handle = float.open({
              title = string.format('git show %s', word:sub(1, 7)),
              height = 1,
              width = 0.3,
              border = 'rounded',
              contents = function()
                return result
              end,
              post = show_syntax,
            }).handle
          end
        end)
      end
    end,
  })

  if type(_G.Mug.result_map) == 'table' then
    for key, map in pairs(_G.Mug.result_map) do
      vim.api.nvim_buf_set_keymap(bufnr, map[1], key, map[2], map[3])
    end
  end
end

---Check if options contains items
---@param opts table Git subcommand options
---@param contains table Items to check
local opts_contain = function(opts, contains)
  for _, opt in ipairs(contains) do
    if vim.tbl_contains(opts, opt) then
      return true
    end
  end

  return false
end

util.user_command('sub_command', function(opts)
  if #opts.fargs == 0 then
    return
  end

  if buffer_id ~= 0 then
    pcall(vim.api.nvim_buf_delete, buffer_id, { force = true })
    buffer_id = 0
  end

  local root = vim.fs.find('.git', { type = 'directory', upward = true })[1]
  root = root and root:sub(1, -6) or vim.uv.cwd()

  local subcmd = opts.fargs[1]
  local cmd_options = { select(2, unpack(opts.fargs)) }

  ---@type string, boolean
  local cfg, termopen
  local rg_term = vim.regex([[^\(add\|branch\|checkout\|reset\|restore\|stage\|stash\)$]])
  local rg_sub = vim.regex([[^\(diff\|grep\|log\|show\|tag\)$]])
  local patches = {'-e', '--edit', '--edit-description', '-i', '--interactive', '-p', '--patch'}
  local help = {'-h', '--help'}

  if (subcmd == 'commit') or (subcmd == 'rebase') then
    termopen = true
  elseif rg_term:match_str(subcmd) and opts_contain(opts.fargs, patches) then
    termopen = true
  else
    if not rg_sub:match_str(subcmd) or opts_contain(opts.fargs, help) then
      cfg = 'color.status=always'
    else
      cmd_options = util.tbl_merges({ '--color=always' }, cmd_options)
    end
  end

  local gitcmd =
    util.gitcmd({ wd = root, quotepath = false, editor = true, cfg = cfg, cmd = subcmd, opts = cmd_options })

  job.async(function()
    ---@type integer, JobTerm
    local loglevel, resp = job.await_term(gitcmd, {
      name = string.format('%s://%s', HEADER, subcmd),
      pos = _G.Mug.result_position,
      listed = true,
      termopen = termopen,
    })
    ---@type integer
    buffer_id = resp.bufnr

    if (loglevel == 2) and buffer_id ~= 0 then
      setmap(resp.bufnr)
    end
  end)
end, {
  nargs = '+',
  bang = false,
  complete = function(a, l, _)
    return comp.filter(a, l, complist(a, l))
  end,
})
