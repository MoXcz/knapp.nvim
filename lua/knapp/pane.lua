-- Backlinks sidebar: what links here, refreshed as you move between notes.
local actions = require("knapp.actions")
local config = require("knapp.config")

local M = {}

local ns = vim.api.nvim_create_namespace("knapp_pane")
local state = nil -- { win, buf, items, rel }

local function hl_setup()
  local function def(name, link)
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end
  def("KnappPaneTitle", "Title")
  def("KnappPaneName", "Identifier")
  def("KnappPanePath", "Comment")
  def("KnappPaneEmpty", "Comment")
end

function M.is_open()
  return state ~= nil and vim.api.nvim_win_is_valid(state.win)
end

function M.close()
  if M.is_open() then
    vim.api.nvim_win_close(state.win, true)
  end
  state = nil
end

--- Is `win` a normal window showing a vault note?
local function is_note_win(win)
  if not vim.api.nvim_win_is_valid(win) then return false end
  if vim.api.nvim_win_get_config(win).relative ~= "" then return false end
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= "" then return false end
  local name = vim.api.nvim_buf_get_name(buf)
  return config.in_vault(name) and name:sub(-3) == ".md"
end

--- One row per linking note, keeping the first occurrence to jump to.
local function group(items)
  local rows, seen = {}, {}
  for _, item in ipairs(items) do
    local row = seen[item.rel]
    if row then
      row.count = row.count + 1
    else
      row = { rel = item.rel, name = item.name, item = item, count = 1 }
      seen[item.rel] = row
      rows[#rows + 1] = row
    end
  end
  return rows
end

local function render(rel, items)
  local rows = group(items)
  local pane_width = vim.api.nvim_win_get_width(state.win)
  local lines, marks = {}, {}
  local title = ("Backlinks (%d in %d note%s)"):format(#items, #rows, #rows == 1 and "" or "s")
  lines[1] = title
  marks[#marks + 1] = { 0, 0, #title, "KnappPaneTitle" }
  lines[2] = ""
  if #rows == 0 then
    lines[3] = "  none"
    marks[#marks + 1] = { 2, 0, -1, "KnappPaneEmpty" }
  else
    local width = 0
    for _, row in ipairs(rows) do width = math.max(width, vim.fn.strdisplaywidth(row.name)) end
    -- keep the name column from eating a wide horizontal pane
    width = math.min(width, math.floor(pane_width * 0.6), 40)
    for i, row in ipairs(rows) do
      local name = row.name
      if vim.fn.strdisplaywidth(name) > width then
        name = vim.fn.strcharpart(name, 0, math.max(1, width - 1)) .. "…"
      end
      local pad = width - vim.fn.strdisplaywidth(name)
      local count = row.count > 1 and (" ×" .. row.count) or ""
      local line = ("  %s%s  %s%s"):format(name, (" "):rep(math.max(pad, 0)), row.rel, count)
      lines[2 + i] = line
      marks[#marks + 1] = { 1 + i, 0, 2 + #name, "KnappPaneName" }
      marks[#marks + 1] = { 1 + i, 2 + #name, -1, "KnappPanePath" }
    end
  end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    pcall(vim.api.nvim_buf_set_extmark, state.buf, ns, m[1], m[2], {
      end_row = m[1], end_col = m[3] < 0 and #(lines[m[1] + 1] or "") or m[3], hl_group = m[4],
    })
  end
  state.rel = rel
  state.rows = rows
end

local function item_under_cursor()
  local row = vim.api.nvim_win_get_cursor(state.win)[1]
  local row_data = state.rows and state.rows[row - 2]
  return row_data and row_data.item
end

local function jump(cmd)
  local item = item_under_cursor()
  if not item then return end
  local target
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= state.win and is_note_win(win) then target = win break end
  end
  if target then
    vim.api.nvim_set_current_win(target)
  else
    vim.cmd("wincmd p")
  end
  vim.cmd(cmd .. " " .. vim.fn.fnameescape(item.filename))
  pcall(vim.api.nvim_win_set_cursor, 0, { item.lnum, math.max(item.col - 1, 0) })
  vim.cmd("normal! zz")
end

local function setup_buf(buf)
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = "knapp: " .. desc })
  end
  map("<CR>", function() jump("edit") end, "open backlink")
  map("o", function() jump("edit") end, "open backlink")
  map("s", function() jump("split") end, "open backlink in split")
  map("v", function() jump("vsplit") end, "open backlink in vsplit")
  map("q", M.close, "close backlinks pane")
  map("R", function() M.update(true) end, "refresh")
end

--- Refresh the pane for the current note. `force` re-reads even if unchanged.
function M.update(force)
  if not M.is_open() then return end
  local win = vim.api.nvim_get_current_win()
  if win == state.win then return end
  local rel = actions.current()
  if not rel then return end
  if not force and rel == state.rel then return end
  render(rel, actions.backlink_items(rel))
end

--- Open the pane for the current note. Keeps focus in the note by default.
function M.open(focus)
  local rel = actions.current()
  if not rel then return end
  hl_setup()
  local opts = config.opts.backlinks
  if M.is_open() then
    if focus then vim.api.nvim_set_current_win(state.win) end
    M.update(true)
    return
  end
  local prev = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "knapp-backlinks"
  local horizontal = opts.position == "top" or opts.position == "bottom"
  local first = opts.position == "top" or opts.position == "left"
  vim.cmd((first and "topleft " or "botright ") .. (horizontal and "split" or "vsplit"))
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  if horizontal then
    vim.api.nvim_win_set_height(win, opts.height)
    vim.wo[win].winfixheight = true
  else
    vim.api.nvim_win_set_width(win, opts.width)
    vim.wo[win].winfixwidth = true
  end
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.wo[win].signcolumn = "no"
  vim.wo[win].list = false
  state = { win = win, buf = buf }
  setup_buf(buf)
  render(rel, actions.backlink_items(rel))
  if not focus then vim.api.nvim_set_current_win(prev) end
end

function M.toggle()
  if M.is_open() then M.close() else M.open(false) end
end

return M
