-- Small shared helpers. Nothing here touches plugin state.
local M = {}

--- Read a whole file.
---
--- Returns `nil, reason` rather than a bare `nil` so callers can say *why* a
--- note could not be read: "permission denied" and "no such file" are very
--- different problems to be told about.
---@param path string
---@return string? text
---@return string? reason
function M.read_file(path)
  local fd, open_err = io.open(path, "r")
  if not fd then return nil, open_err or ("could not open " .. path) end
  local text, read_err = fd:read("*a")
  fd:close()
  if not text then return nil, read_err or ("could not read " .. path) end
  return text
end

--- Write a whole file.
---@param path string
---@param text string
---@return boolean ok
---@return string? reason
function M.write_file(path, text)
  local fd, err = io.open(path, "w")
  if not fd then return false, err or ("could not open " .. path .. " for writing") end
  local ok, write_err = fd:write(text)
  fd:close()
  if not ok then return false, write_err or ("could not write " .. path) end
  return true
end

--- Decode JSON, reporting the parse error rather than swallowing it.
---@param text string
---@return table? value
---@return string? reason
function M.decode_json(text)
  local ok, value = pcall(vim.json.decode, text)
  if not ok then return nil, tostring(value) end
  if type(value) ~= "table" then return nil, "expected a JSON object" end
  return value
end

--- Does `name` look like a markdown note?
---
--- Case-insensitive: Obsidian happily indexes `Note.MD`, and on a
--- case-insensitive filesystem the same file can be reached either way.
---@param name string
---@return boolean
function M.is_md(name) return type(name) == "string" and name:sub(-3):lower() == ".md" end

--- Wrap `fn` so that a burst of calls collapses into one, `ms` after the last.
---
--- `WinResized` fires continuously while a split boundary is dragged, and
--- `BufEnter` and `BufWinEnter` both fire for a single note switch. Without
--- this, each event does the full work.
---
--- The wrapped function is called on the main loop (`vim.schedule_wrap`), so it
--- may use the whole API. Arguments from the *last* call win.
---@param ms integer
---@param fn function
---@return function debounced
function M.debounce(ms, fn)
  local timer, args, argc
  return function(...)
    args, argc = { ... }, select("#", ...)
    if not timer then timer = vim.uv.new_timer() end
    timer:stop()
    timer:start(ms, 0, vim.schedule_wrap(function() fn(unpack(args, 1, argc)) end))
  end
end

return M
