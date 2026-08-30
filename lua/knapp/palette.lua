-- Obsidian-style command palette over vim.ui.select (snacks picker).
local actions = require("knapp.actions")
local format = require("knapp.format")
local index = require("knapp.index")
local config = require("knapp.config")

local M = {}

local function pick_note(prompt, cb)
  index.ensure()
  local items = {}
  for _, note in ipairs(index.notes()) do
    items[#items + 1] = note.rel
  end
  vim.ui.select(items, { prompt = prompt }, function(choice)
    if choice then cb(choice) end
  end)
end

function M.find_notes()
  local ok, Snacks = pcall(require, "snacks")
  if ok then
    Snacks.picker.files({ cwd = config.opts.vault, ft = "md" })
  else
    pick_note("Open note", function(rel) vim.cmd.edit(vim.fn.fnameescape(config.abs(rel))) end)
  end
end

function M.grep_vault()
  local ok, Snacks = pcall(require, "snacks")
  if ok then
    Snacks.picker.grep({ cwd = config.opts.vault })
  else
    vim.ui.input({ prompt = "Grep vault: " }, function(q)
      if q and q ~= "" then
        vim.cmd(("silent grep! %s %s"):format(vim.fn.shellescape(q), vim.fn.fnameescape(config.opts.vault)))
      end
    end)
  end
end

function M.new_note()
  vim.ui.input({ prompt = "New note: " }, function(name)
    if name and vim.trim(name) ~= "" then actions.create_note(vim.trim(name)) end
  end)
end

--- Palette entries. Extend with M.register().
M.commands = {
  { name = "Merge current note into another note", fn = actions.merge },
  { name = "Move current note to folder", fn = actions.move },
  { name = "Rename current note", fn = actions.rename },
  { name = "Open note", fn = function() M.find_notes() end },
  { name = "Search in vault", fn = function() M.grep_vault() end },
  { name = "New note", fn = function() M.new_note() end },
  { name = "Toggle backlinks pane", fn = function() require("knapp.pane").toggle() end },
  { name = "Toggle readable width", fn = function() require("knapp.view").toggle() end },
  { name = "Show backlinks in quickfix", fn = actions.backlinks },
  { name = "Follow link under cursor", fn = actions.follow },
  { name = "Toggle bold", fn = format.action("bold") },
  { name = "Toggle italics", fn = format.action("italic") },
  { name = "Toggle code", fn = format.action("code") },
  { name = "Toggle highlight", fn = format.action("highlight") },
  { name = "Toggle strikethrough", fn = format.action("strike") },
  { name = "Insert wikilink", fn = format.action("link") },
  {
    name = "Trash current note",
    fn = function()
      local rel = actions.current()
      if rel then actions.trash(rel) end
    end,
  },
  { name = "Open today's daily note", feature = "journal", fn = function() require("knapp.journal").daily() end },
  { name = "Open yesterday's daily note", feature = "journal", fn = function() require("knapp.journal").daily(-1) end },
  { name = "Open tomorrow's daily note", feature = "journal", fn = function() require("knapp.journal").daily(1) end },
  { name = "Open this week's weekly note", feature = "journal", fn = function() require("knapp.journal").weekly() end },
  {
    name = "Open last week's weekly note",
    feature = "journal",
    fn = function() require("knapp.journal").weekly(-1) end,
  },
  { name = "New fleeting note (zettel)", feature = "journal", fn = function() require("knapp.journal").zettel() end },
  { name = "Open calendar", feature = "calendar", fn = function() require("knapp.calendar").open() end },
  { name = "Insert template", fn = function() require("knapp.template").insert() end },
  { name = "Rebuild vault index", fn = actions.reindex },
}

--- Add an entry to the command palette.
---
--- Public API: call from your config after setup().
---@param name string label shown in the palette
---@param fn fun() run when the entry is picked
function M.register(name, fn) M.commands[#M.commands + 1] = { name = name, fn = fn } end

--- Entries whose feature is not switched off in the config.
local function available()
  return vim.tbl_filter(function(c)
    local feature = c.feature and config.opts[c.feature]
    return not (feature and feature.enabled == false)
  end, M.commands)
end

function M.open()
  local commands = available()
  local names = vim.tbl_map(function(c) return c.name end, commands)
  vim.ui.select(names, { prompt = "Knapp" }, function(_, idx)
    if idx then commands[idx].fn() end
  end)
end

return M
