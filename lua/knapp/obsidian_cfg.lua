-- Reads <vault>/.obsidian/*.json so Obsidian stays the single source of truth
-- for folders, formats and templates.
local config = require("knapp.config")

local M = {}

local cache = nil

local function read_json(name)
  local path = vim.fs.joinpath(config.opts.vault, ".obsidian", name)
  local fd = io.open(path, "r")
  if not fd then return {} end
  local text = fd:read("*a")
  fd:close()
  local ok, decoded = pcall(vim.json.decode, text)
  return ok and decoded or {}
end

--- All relevant Obsidian settings, lazily read and memoized.
--- Call M.reload() after editing settings inside Obsidian.
function M.get()
  if cache then return cache end
  local app = read_json("app.json")
  local daily = read_json("daily-notes.json")
  local weekly = (read_json("plugins/calendar/data.json")) or {}
  local zk = read_json("zk-prefixer.json")
  local templates = read_json("templates.json")
  cache = {
    app = app,
    new_note_folder = app.newFileFolderPath or "",
    attachment_folder = app.attachmentFolderPath or "",
    daily = {
      folder = daily.folder or "",
      format = daily.format or "YYYY-MM-DD",
      template = daily.template,
    },
    weekly = {
      folder = weekly.weeklyNoteFolder or "",
      -- Obsidian's calendar plugin defaults to gggg-[W]ww when left blank
      format = (weekly.weeklyNoteFormat ~= "" and weekly.weeklyNoteFormat) or "YYYY-[W]WW",
      template = weekly.weeklyNoteTemplate,
      week_start = weekly.weekStart or "monday",
    },
    zettel = {
      folder = zk.folder or "",
      format = zk.format or "YYYYMMDDHHmm",
      template = zk.template,
    },
    templates = {
      folder = templates.folder or "Templates",
      date_format = templates.dateFormat or "YYYY-MM-DD",
      time_format = templates.timeFormat or "HH:mm",
    },
  }
  return cache
end

function M.reload()
  cache = nil
  return M.get()
end

return M
