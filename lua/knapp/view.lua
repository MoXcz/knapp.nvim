-- Readable line length. Neovim soft-wraps at the window edge and has no
-- "wrap at column N" option, so the note window is narrowed to that width and
-- the leftover space is filled with an inert padding window.
local config = require("knapp.config")

local M = {}

local pads = {} -- note window -> padding window
local busy = false -- re-entrancy guard for refresh()
local navigating = false -- re-entrancy guard for leave_pad()

local function valid(win) return win and vim.api.nvim_win_is_valid(win) end

--- A normal (non-float) window showing a vault note.
function M.is_note_win(win)
  if not valid(win) then return false end
  if vim.api.nvim_win_get_config(win).relative ~= "" then return false end
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= "" then return false end
  local name = vim.api.nvim_buf_get_name(buf)
  return config.in_vault(name) and name:sub(-3) == ".md"
end

function M.is_pad(win)
  if not valid(win) then return false end
  local buf = vim.api.nvim_win_get_buf(win)
  return vim.b[buf].knapp_pad == true
end

local function drop_pad(note_win)
  local pad = pads[note_win]
  pads[note_win] = nil
  if valid(pad) then pcall(vim.api.nvim_win_close, pad, true) end
end

local function make_pad(note_win, width)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.b[buf].knapp_pad = true
  local pad = vim.api.nvim_open_win(buf, false, {
    split = "right",
    win = note_win,
    width = width,
  })
  vim.wo[pad].number = false
  vim.wo[pad].relativenumber = false
  vim.wo[pad].signcolumn = "no"
  vim.wo[pad].statuscolumn = ""
  vim.wo[pad].cursorline = false
  vim.wo[pad].list = false
  vim.wo[pad].fillchars = "eob: "
  vim.wo[pad].winhighlight = "Normal:KnappPad,EndOfBuffer:KnappPad"
  vim.api.nvim_set_hl(0, "KnappPad", { link = "Normal", default = true })
  pads[note_win] = pad
  return pad
end

--- Window-local options for a note window.
function M.apply_options(win)
  local w = config.opts.wrap
  if not w.enabled then return end
  vim.api.nvim_win_call(win, function()
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.breakindent = true
    vim.opt_local.textwidth = w.width
    vim.opt_local.showbreak = "  "
  end)
end

--- Narrow `win` to wrap.width, padding the leftover space. No-op when the
--- window is already that narrow (vertical splits keep their full space).
function M.pad(win)
  local w = config.opts.wrap
  win = (win == nil or win == 0) and vim.api.nvim_get_current_win() or win
  if not w.enabled or not w.pad then return end
  if not M.is_note_win(win) then
    drop_pad(win)
    return
  end
  local pad = pads[win]
  if pad and not valid(pad) then
    pads[win] = nil
    pad = nil
  end
  -- space the note window could occupy if the pad went away (+1 separator)
  local available = vim.api.nvim_win_get_width(win) + (pad and (vim.api.nvim_win_get_width(pad) + 1) or 0)
  if available <= w.width + w.min_pad then
    drop_pad(win)
    return
  end
  -- size the pad, not the note: the note keeps whatever is left over, which
  -- is exactly `width`
  local pad_width = available - w.width - 1
  if pad then
    vim.api.nvim_win_set_width(pad, pad_width)
  else
    pad = make_pad(win, pad_width)
  end
  if vim.api.nvim_win_get_width(win) ~= w.width then vim.api.nvim_win_set_width(win, w.width) end
end

--- Re-pad every note window in the current tab.
function M.refresh()
  if busy then return end
  busy = true
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if M.is_note_win(win) then
      M.pad(win)
    elseif pads[win] then
      drop_pad(win)
    end
  end
  for note_win in pairs(pads) do
    if not valid(note_win) or not M.is_note_win(note_win) then drop_pad(note_win) end
  end
  busy = false
end

--- Close every padding window (used when the feature is toggled off).
function M.clear()
  for note_win in pairs(pads) do
    drop_pad(note_win)
  end
  pads = {}
end

function M.toggle()
  local w = config.opts.wrap
  w.pad = not w.pad
  if w.pad then
    M.refresh()
  else
    M.clear()
  end
  vim.notify("readable width " .. (w.pad and "on" or "off"), vim.log.levels.INFO, { title = "knapp" })
end

--- Direction the cursor was travelling when it landed in the pad.
local function travel_direction(from, to)
  if not valid(from) then return "l" end
  local fr, fc = unpack(vim.api.nvim_win_get_position(from))
  local tr, tc = unpack(vim.api.nvim_win_get_position(to))
  if fc ~= tc then return fc < tc and "l" or "h" end
  if fr ~= tr then return fr < tr and "j" or "k" end
  return "l"
end

--- The pad is a layout trick, not a place to be: keep going in whatever
--- direction the cursor was moving, so <C-w>l / <C-l> skip straight over it.
function M.leave_pad()
  local cur = vim.api.nvim_get_current_win()
  if navigating or not M.is_pad(cur) then return end
  navigating = true
  local prev = vim.fn.win_getid(vim.fn.winnr("#"))
  local dir = travel_direction(prev, cur)
  vim.cmd("wincmd " .. dir)
  if vim.api.nvim_get_current_win() ~= cur then
    navigating = false
    return
  end
  -- nothing on the far side of the pad: step back, then let a tmux navigator
  -- take the movement across to the next tmux pane
  if valid(prev) and prev ~= cur then
    vim.api.nvim_set_current_win(prev)
  else
    vim.cmd("wincmd p")
  end
  navigating = false
  -- Nothing on the far side of the pad inside Nvim: let a configured navigator
  -- carry the motion out of Nvim entirely (tmux, wezterm, ...).
  local cmd = (config.opts.wrap.nav_commands or {})[dir]
  if cmd and cmd ~= "" and vim.fn.exists(":" .. cmd) == 2 then vim.cmd(cmd) end
end

return M
