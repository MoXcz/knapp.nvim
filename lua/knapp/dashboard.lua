-- A vault dashboard, drawn with snacks.nvim.
--
-- Deliberately not a snacks preset: it opens only when Nvim starts inside the
-- vault, so it does not replace whatever dashboard you already use elsewhere.
local config = require("knapp.config")

local M = {}

--- Is snacks available and new enough to have a dashboard?
local function snacks()
  local ok, s = pcall(require, "snacks")
  if not ok or not s.dashboard then return nil end
  return s
end

--- Turn one grid line plus its marks into snacks text segments, so the days
--- that already have a note keep the colour the calendar gives them.
---@param line string
---@param marks table[] `{ line, col_start, col_end, hl }`, 0-based line
---@param row integer 0-based line index
---@return table[]
local function segments(line, marks, row)
  local spans = {}
  for _, m in ipairs(marks) do
    if m[1] == row and m[2] < m[3] then spans[#spans + 1] = { m[2], m[3], m[4] } end
  end
  table.sort(spans, function(a, b) return a[1] < b[1] end)

  local out, pos = {}, 0
  for _, span in ipairs(spans) do
    local from, to, hl = span[1], math.min(span[2], #line), span[3]
    if from >= pos and from < #line then
      if from > pos then out[#out + 1] = { line:sub(pos + 1, from) } end
      out[#out + 1] = { line:sub(from + 1, to), hl = hl }
      pos = to
    end
  end
  if pos < #line then out[#out + 1] = { line:sub(pos + 1) } end
  if #out == 0 then out = { { line } } end
  return out
end

--- This month's calendar, with the days that already have a note marked.
---@return table[]
function M.calendar_section()
  local t = require("knapp.date").parts()
  local lines, marks = require("knapp.calendar").grid(t.year, t.month)
  local items = { { title = "Calendar", padding = 1 } }
  for i, line in ipairs(lines) do
    items[#items + 1] = { text = segments(line, marks, i - 1) }
  end
  items[#items].padding = 1
  items[#items + 1] = {
    text = { { "  open calendar", hl = "SnacksDashboardDesc" } },
    action = function() require("knapp.calendar").open() end,
    key = "C",
    padding = 1,
  }
  return items
end

--- Unfinished tasks from the configured todo file.
---@return table[]
function M.todo_section()
  local todo = require("knapp.todo")
  local opts = config.opts.dashboard
  local title = ("Todo (%s)"):format(todo.rel())
  local items = { { title = title, padding = 1 } }

  if not todo.path() then
    items[#items + 1] = {
      text = { { "  no " .. todo.rel() .. " in the vault", hl = "SnacksDashboardDesc" } },
    }
    return items
  end

  local open, done = {}, 0
  for _, task in ipairs(todo.items()) do
    if task.done then
      done = done + 1
    else
      open[#open + 1] = task
    end
  end

  if #open == 0 then items[#items + 1] = { text = { { "  nothing left", hl = "SnacksDashboardDesc" } } } end
  for i, task in ipairs(open) do
    if i > opts.todo_limit then
      items[#items + 1] = {
        text = { { ("  … %d more"):format(#open - opts.todo_limit), hl = "SnacksDashboardDesc" } },
      }
      break
    end
    items[#items + 1] = {
      text = {
        { "  " .. ("  "):rep(math.min(task.indent, 6) / 2) .. "󰄱 ", hl = "SnacksDashboardIcon" },
        { task.text },
      },
      action = function() todo.open(task.lnum) end,
    }
  end
  if done > 0 then
    items[#items].padding = 1
    items[#items + 1] = { text = { { ("  %d done"):format(done), hl = "SnacksDashboardDesc" } } }
  end
  return items
end

--- The dashboard's sections, in two panes.
---@return table[]
function M.sections()
  local opts = config.opts.dashboard
  local vault_pane = { pane = 1, { title = "Vault", padding = 1 } }
  local function entry(item) vault_pane[#vault_pane + 1] = item end
  if config.opts.journal.enabled then
    entry({ icon = " ", key = "d", desc = "Today's note", action = function() require("knapp.journal").daily() end })
    entry({ icon = " ", key = "w", desc = "This week", action = function() require("knapp.journal").weekly() end })
    entry({
      icon = " ",
      key = "z",
      desc = "New fleeting note",
      action = function() require("knapp.journal").zettel() end,
    })
  end
  entry({ icon = " ", key = "n", desc = "New note", action = function() require("knapp.palette").new_note() end })
  entry({ icon = " ", key = "f", desc = "Find notes", action = function() require("knapp.palette").find_notes() end })
  entry({ icon = " ", key = "g", desc = "Grep vault", action = function() require("knapp.palette").grep_vault() end })
  entry({ icon = " ", key = "q", desc = "Quit", action = ":qa" })
  vault_pane.padding = 1

  local sections = {
    { section = "header" },
    vault_pane,
    {
      pane = 1,
      title = "Recent notes",
      padding = 1,
      section = "recent_files",
      cwd = config.opts.vault,
      limit = opts.recent_limit,
    },
  }
  if config.opts.calendar.enabled then sections[#sections + 1] = { pane = 2, M.calendar_section() } end
  sections[#sections + 1] = { pane = 2, M.todo_section() }
  -- snacks' `startup` section hard-requires `lazy.stats`, so it breaks the
  -- whole dashboard under any other plugin manager, vim.pack included
  if package.loaded["lazy"] then sections[#sections + 1] = { section = "startup" } end
  return sections
end

--- Open the dashboard.
---@return boolean opened
function M.open()
  local s = snacks()
  if not s then
    vim.notify("knapp: the dashboard needs snacks.nvim", vim.log.levels.WARN, { title = "knapp" })
    return false
  end
  s.dashboard.open({ sections = M.sections() })
  return true
end

--- Should the dashboard open for this session?
---
--- Only when Nvim was started with no file to edit and the working directory
--- is inside the vault, so opening Nvim anywhere else is untouched.
---@return boolean
function M.should_open()
  local opts = config.opts.dashboard
  if not opts.enabled or not opts.auto then return false end
  -- without snacks the auto-open path stays silent; only an explicit
  -- :Knapp dashboard warns about the missing dependency
  if not snacks() then return false end
  if vim.fn.argc() > 0 then return false end
  -- something already put a real buffer on screen
  if vim.api.nvim_buf_get_name(0) ~= "" or vim.bo.filetype ~= "" then return false end
  return config.in_vault(vim.uv.cwd() or "")
end

---@param group integer augroup id
function M.setup(group)
  if not config.opts.dashboard.enabled then return end
  -- a lazy-loaded setup() runs after VimEnter has already fired, and a
  -- `once` autocmd for a past event never runs (same situation as the
  -- global keymaps in init.lua)
  if vim.v.vim_did_enter == 1 then
    vim.schedule(function()
      if M.should_open() then M.open() end
    end)
    return
  end
  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    once = true,
    nested = true,
    callback = function()
      if M.should_open() then M.open() end
    end,
  })
end

return M
