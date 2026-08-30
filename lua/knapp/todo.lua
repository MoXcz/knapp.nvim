-- Markdown task lists: `- [ ] something`.
--
-- Deliberately just the reading half. Parsing tasks out of a file is what the
-- dashboard needs, and it is the piece any richer task handling would be built
-- on, so it lives in its own module rather than inside the dashboard.
local config = require("knapp.config")
local util = require("knapp.util")

local M = {}

---@class knapp.Task
---@field lnum integer 1-based line the task is on
---@field done boolean
---@field marker string what was between the brackets: " ", "x", "/", ...
---@field text string the task itself, without the checkbox
---@field indent integer leading spaces, so nesting survives

--- Every task in `text`.
---
--- Tasks inside fenced code blocks are skipped, the same way links are: a
--- checkbox in a code sample is not a task.
---@param text string
---@return knapp.Task[]
function M.parse(text)
  local out = {}
  local fence = nil
  local lnum = 0
  for line in (text .. "\n"):gmatch("(.-)\n") do
    lnum = lnum + 1
    local f = line:match("^%s*(```+)") or line:match("^%s*(~~~+)")
    if fence then
      if f and #f >= #fence and f:sub(1, 1) == fence:sub(1, 1) then fence = nil end
    elseif f then
      fence = f
    else
      local indent, marker, body = line:match("^(%s*)[-*+]%s+%[(.)%]%s?(.*)$")
      if marker then
        out[#out + 1] = {
          lnum = lnum,
          done = marker ~= " ",
          marker = marker,
          text = vim.trim(body),
          indent = #indent,
        }
      end
    end
  end
  return out
end

--- The configured todo file, as a vault-relative path.
---@return string
function M.rel()
  local rel = config.opts.dashboard.todo
  return util.is_md(rel) and rel or (rel .. ".md")
end

--- Absolute path of the configured todo file, or nil when it does not exist.
---@return string?
function M.path()
  local abs = config.abs(M.rel())
  return vim.uv.fs_stat(abs) and abs or nil
end

--- Tasks in the configured todo file. Empty when there is no such file.
---@return knapp.Task[]
function M.items()
  local abs = M.path()
  if not abs then return {} end
  return M.parse(util.read_file(abs) or "")
end

--- Open the todo file, at `lnum` when given.
---@param lnum integer?
function M.open(lnum)
  local abs = config.abs(M.rel())
  vim.cmd.edit(vim.fn.fnameescape(abs))
  if lnum then pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 }) end
end

return M
