-- Month calendar in a floating window: jump to daily and weekly notes and see
-- at a glance which days already have one.
local date = require("knapp.date")
local journal = require("knapp.journal")
local ocfg = require("knapp.obsidian_cfg")

local M = {}

local ns = vim.api.nvim_create_namespace("knapp_calendar")

--- Live calendar float. Nil whenever it is closed.
---@class knapp.CalendarState
---@field buf integer
---@field win integer
---@field year integer
---@field month integer
---@field cells { line: integer, col_start: integer, col_end: integer, day: integer }[]
---@field weeks table<integer, integer> display line -> a timestamp inside that week

---@type knapp.CalendarState?
local state = nil

local function hl_setup()
  local function def(name, link)
    if vim.fn.hlexists(name) == 0 or true then vim.api.nvim_set_hl(0, name, { link = link, default = true }) end
  end
  def("KnappCalHeader", "Title")
  def("KnappCalWeekday", "Comment")
  def("KnappCalWeek", "Comment")
  def("KnappCalToday", "Special")
  def("KnappCalHasNote", "String")
end

local WEEKDAYS_MON = { "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" }
local WEEKDAYS_SUN = { "Su", "Mo", "Tu", "We", "Th", "Fr", "Sa" }

--- Column (1-7) of a weekday within the grid.
local function column_of(time, first_day)
  local wday = os.date("*t", time).wday -- 1 = Sunday
  if first_day == "sunday" then return wday end
  return (wday + 5) % 7 + 1
end

local function build(year, month)
  local first_day = ocfg.get().weekly.week_start
  local days_in_month = os.date("*t", date.of(year, month + 1, 0)).day
  local dailies = journal.month_dailies(year, month)
  local today = os.date("*t")
  local weekdays = first_day == "sunday" and WEEKDAYS_SUN or WEEKDAYS_MON

  local lines = {
    ("  %s"):format(date.format("MMMM YYYY", date.of(year, month, 1))),
    "Wk  " .. table.concat(weekdays, " "),
  }
  local cells, weeks, marks = {}, {}, {}
  local cols = {}
  local function flush(week_time)
    local text = { ("%2s "):format(date.format("WW", week_time)) }
    for c = 1, 7 do
      text[#text + 1] = " " .. (cols[c] and ("%2d"):format(cols[c].day) or "  ")
    end
    lines[#lines + 1] = table.concat(text)
    weeks[#lines - 1] = week_time
    for c = 1, 7 do
      if cols[c] then
        local col_start = 3 + (c - 1) * 3 + 1
        cells[#cells + 1] = {
          line = #lines - 1,
          col_start = col_start,
          col_end = col_start + 2,
          day = cols[c].day,
        }
        local hl
        if cols[c].day == today.day and month == today.month and year == today.year then
          hl = "KnappCalToday"
        elseif dailies[cols[c].day] then
          hl = "KnappCalHasNote"
        end
        if hl then marks[#marks + 1] = { #lines - 1, col_start, col_start + 2, hl } end
      end
    end
    marks[#marks + 1] = { #lines - 1, 0, 3, "KnappCalWeek" }
    cols = {}
  end

  local week_time
  for day = 1, days_in_month do
    local time = date.of(year, month, day)
    local col = column_of(time, first_day)
    if col == 1 or not week_time then week_time = time end
    cols[col] = { day = day, time = time }
    if col == 7 or day == days_in_month then
      flush(week_time)
      week_time = nil
    end
  end
  marks[#marks + 1] = { 0, 0, -1, "KnappCalHeader" }
  marks[#marks + 1] = { 1, 0, -1, "KnappCalWeekday" }
  return lines, cells, weeks, marks
end

local function render()
  if not state then return end
  local lines, cells, weeks, marks = build(state.year, state.month)
  state.cells, state.weeks = cells, weeks
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    pcall(
      vim.api.nvim_buf_set_extmark,
      state.buf,
      ns,
      m[1],
      m[2],
      { end_col = m[3] < 0 and nil or m[3], end_row = m[3] < 0 and m[1] + 1 or nil, hl_group = m[4] }
    )
  end
  vim.api.nvim_win_set_height(state.win, #lines)
end

local function day_under_cursor()
  if not state then return nil end
  local row, col = unpack(vim.api.nvim_win_get_cursor(state.win))
  for _, cell in ipairs(state.cells) do
    if cell.line == row - 1 and col >= cell.col_start - 1 and col < cell.col_end then return cell.day end
  end
  return nil
end

local function close()
  if state and vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_close(state.win, true) end
  state = nil
end

local function goto_today()
  if not state then return end
  local t = os.date("*t")
  state.year, state.month = t.year, t.month
  render()
  for _, cell in ipairs(state.cells) do
    if cell.day == t.day then
      vim.api.nvim_win_set_cursor(state.win, { cell.line + 1, cell.col_start })
      return
    end
  end
end

local function shift_month(n)
  if not state then return end
  local t = os.date("*t", date.of(state.year, state.month + n, 1))
  state.year, state.month = t.year, t.month
  render()
  vim.api.nvim_win_set_cursor(state.win, { math.min(3, vim.api.nvim_buf_line_count(state.buf)), 4 })
end

--- Open the calendar. `<CR>` opens the daily note under the cursor, `W` the
--- weekly note of that row.
function M.open()
  hl_setup()
  if state and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "knapp-calendar"
  local t = os.date("*t")
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = 27,
    height = 10,
    row = math.max(1, math.floor((vim.o.lines - 12) / 2)),
    col = math.max(1, math.floor((vim.o.columns - 27) / 2)),
    style = "minimal",
    border = "rounded",
    title = " calendar ",
    title_pos = "center",
  })
  vim.wo[win].cursorline = false
  state = { buf = buf, win = win, year = t.year, month = t.month, cells = {}, weeks = {} }
  render()
  goto_today()

  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = "knapp: " .. desc })
  end
  map("q", close, "close")
  map("<Esc>", close, "close")
  map("]", function() shift_month(1) end, "next month")
  map("[", function() shift_month(-1) end, "previous month")
  map("<C-n>", function() shift_month(1) end, "next month")
  map("<C-p>", function() shift_month(-1) end, "previous month")
  map("t", goto_today, "today")
  map("R", render, "refresh")
  map("<CR>", function()
    local day = day_under_cursor()
    local row = vim.api.nvim_win_get_cursor(state.win)[1] - 1
    local year, month = state.year, state.month
    local week_time = state.weeks[row]
    close()
    if day then
      local time = date.of(year, month, day)
      journal.open(
        journal.daily_path(time),
        ocfg.get().daily.template,
        { time = time, title = vim.fs.basename(journal.daily_path(time)):sub(1, -4) }
      )
    elseif week_time then
      local rel = journal.weekly_path(week_time)
      journal.open(
        rel,
        ocfg.get().weekly.template,
        { time = date.week_start(week_time, ocfg.get().weekly.week_start), title = vim.fs.basename(rel):sub(1, -4) }
      )
    end
  end, "open note under cursor")
  map("W", function()
    local row = vim.api.nvim_win_get_cursor(state.win)[1] - 1
    local week_time = state.weeks[row]
    if not week_time then return end
    close()
    local rel = journal.weekly_path(week_time)
    journal.open(
      rel,
      ocfg.get().weekly.template,
      { time = date.week_start(week_time, ocfg.get().weekly.week_start), title = vim.fs.basename(rel):sub(1, -4) }
    )
  end, "open weekly note")
end

return M
