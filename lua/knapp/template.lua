-- Obsidian core-template expansion: {{title}}, {{date}}, {{time}},
-- {{date:FMT}}, {{DATE:FMT}} and offsets like {{date+6d:MMMM D, YYYY}}.
local config = require("knapp.config")
local date = require("knapp.date")
local ocfg = require("knapp.obsidian_cfg")

local uv = vim.uv
local M = {}

local function read(path)
  local fd = io.open(path, "r")
  if not fd then return nil end
  local text = fd:read("*a")
  fd:close()
  return text
end

--- Expand template placeholders. `ctx` takes { title, time }.
function M.expand(text, ctx)
  ctx = ctx or {}
  local base = ctx.time or os.time()
  local t = ocfg.get().templates
  return (
    text:gsub("{{(.-)}}", function(body)
      local name, fmt = body:match("^([^:]+):(.*)$")
      name = name or body
      local key = name:match("^[%a_]+")
      local offset = name:sub(#(key or "") + 1)
      if not key then return "{{" .. body .. "}}" end
      local lower = key:lower()
      if lower == "title" then
        return ctx.title or ""
      elseif lower == "date" or lower == "time" then
        local time = base
        local n, unit = date.parse_offset(offset)
        if n then time = date.shift(base, n, unit) end
        if fmt and fmt ~= "" then return date.format(fmt, time) end
        return date.format(lower == "date" and t.date_format or t.time_format, time)
      end
      return "{{" .. body .. "}}"
    end)
  )
end

--- Resolve a template name (as written in Obsidian's settings) to a path.
function M.path(name)
  if not name or name == "" then return nil end
  local rel = name:sub(-3) == ".md" and name or (name .. ".md")
  local candidates = { rel, vim.fs.joinpath(ocfg.get().templates.folder, rel) }
  for _, c in ipairs(candidates) do
    local abs = config.abs(c)
    if uv.fs_stat(abs) then return abs end
  end
  return nil
end

--- Template body, expanded. Returns "" when the template is missing.
function M.render(name, ctx)
  local path = M.path(name)
  if not path then return "" end
  return M.expand(read(path) or "", ctx)
end

--- Every template in the templates folder, as display names.
function M.list()
  local dir = config.abs(ocfg.get().templates.folder)
  local out = {}
  local handle = uv.fs_scandir(dir)
  if not handle then return out end
  while true do
    local name, kind = uv.fs_scandir_next(handle)
    if not name then break end
    if kind == "file" and name:sub(-3) == ".md" then out[#out + 1] = name:sub(1, -4) end
  end
  table.sort(out)
  return out
end

--- Insert a template at the cursor (Obsidian's "Insert template").
function M.insert()
  local names = M.list()
  if #names == 0 then
    vim.notify("no templates found", vim.log.levels.WARN, { title = "knapp" })
    return
  end
  vim.ui.select(names, { prompt = "Insert template" }, function(choice)
    if not choice then return end
    local title = vim.fn.expand("%:t:r")
    local body = M.render(choice, { title = title })
    local lines = vim.split(body, "\n", { plain = true })
    if lines[#lines] == "" then table.remove(lines) end
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    if #buf_lines == 1 and buf_lines[1] == "" then
      -- empty note: replace instead of pushing a blank first line
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    else
      vim.api.nvim_buf_set_lines(0, row, row, false, lines)
    end
  end)
end

return M
