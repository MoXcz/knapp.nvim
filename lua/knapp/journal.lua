-- Daily notes, weekly notes and zettel-prefixed fleeting notes, using the
-- folders, formats and templates configured in Obsidian.
local config = require("knapp.config")
local date = require("knapp.date")
local index = require("knapp.index")
local ocfg = require("knapp.obsidian_cfg")
local template = require("knapp.template")

local uv = vim.uv
local M = {}

local function join(folder, name)
  return folder == "" and (name .. ".md") or (folder .. "/" .. name .. ".md")
end

--- Vault-relative path of the daily note for `time`.
function M.daily_path(time)
  local d = ocfg.get().daily
  return join(d.folder, date.format(d.format, time or os.time()))
end

--- Vault-relative path of the weekly note for the week containing `time`.
function M.weekly_path(time)
  local w = ocfg.get().weekly
  local start = date.week_start(time or os.time(), w.week_start)
  return join(w.folder, date.format(w.format, start))
end

function M.exists(rel)
  return uv.fs_stat(config.abs(rel)) ~= nil
end

--- Open `rel`, seeding it from `template_name` when it does not exist yet.
function M.open(rel, template_name, ctx)
  local path = config.abs(rel)
  local fresh = not uv.fs_stat(path)
  if fresh then
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    local body = template_name and template.render(template_name, ctx) or ""
    local fd = io.open(path, "w")
    if not fd then
      vim.notify("could not create " .. rel, vim.log.levels.ERROR, { title = "knapp" })
      return
    end
    fd:write(body)
    fd:close()
  end
  vim.cmd("normal! m'")
  vim.cmd.edit(vim.fn.fnameescape(path))
  if fresh then
    index.update(rel)
    vim.cmd("normal! G")
  end
  return rel
end

--- Daily note, `offset` days from today.
function M.daily(offset)
  local time = date.shift(os.time(), offset or 0, "d")
  local d = ocfg.get().daily
  local rel = M.daily_path(time)
  return M.open(rel, d.template, { time = time, title = vim.fs.basename(rel):sub(1, -4) })
end

--- Weekly note, `offset` weeks from this week.
function M.weekly(offset)
  local time = date.shift(os.time(), offset or 0, "w")
  local w = ocfg.get().weekly
  local rel = M.weekly_path(time)
  -- templates use {{date:WW}} and {{date+6d:...}}: anchor them to the Monday
  local start = date.week_start(time, w.week_start)
  return M.open(rel, w.template, { time = start, title = vim.fs.basename(rel):sub(1, -4) })
end

--- Zettel-prefixed fleeting note. Prompts for a title, which is appended to
--- the timestamp prefix the way your existing Fleeting notes are named.
function M.zettel()
  local z = ocfg.get().zettel
  vim.ui.input({ prompt = "Fleeting note title: " }, function(title)
    if title == nil then return end
    title = vim.trim(title)
    local time = os.time()
    local prefix = date.format(z.format, time)
    local name = title ~= "" and (prefix .. " - " .. title) or prefix
    M.open(join(z.folder, name), z.template, { time = time, title = title })
  end)
end

--- The daily/weekly notes that already exist in a month, as { [day] = rel }.
function M.month_dailies(year, month)
  local out = {}
  local days = tonumber(os.date("*t", date.of(year, month + 1, 0)).day)
  for day = 1, days do
    local rel = M.daily_path(date.of(year, month, day))
    if M.exists(rel) then out[day] = rel end
  end
  return out
end

return M
