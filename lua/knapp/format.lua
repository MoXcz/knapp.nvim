-- Inline formatting: bold, italics, code and wikilinks, with toggle-off.
local M = {}

local function get_text(sr, sc, er, ec) return table.concat(vim.api.nvim_buf_get_text(0, sr, sc, er, ec, {}), "\n") end

--- Charwise visual selection as 0-based (start_row, start_col, end_row, end_col_exclusive).
local function visual_region()
  local s = vim.fn.getpos("v")
  local e = vim.fn.getpos(".")
  local sr, sc, er, ec = s[2] - 1, s[3] - 1, e[2] - 1, e[3] - 1
  if sr > er or (sr == er and sc > ec) then
    sr, sc, er, ec = er, ec, sr, sc
  end
  local last = vim.api.nvim_buf_get_lines(0, er, er + 1, false)[1] or ""
  -- include the character under the cursor, honouring multibyte
  local nchar = vim.str_utf_end(last, ec + 1) + 1
  return sr, sc, er, math.min(ec + nchar, #last)
end

--- Word under the cursor as a 0-based region, or nil.
local function word_region()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local line = vim.api.nvim_get_current_line()
  if line == "" then return nil end
  local init = 1
  while true do
    local s, e = line:find("[%w_'’-]+", init)
    if not s then return nil end
    if col + 1 <= e then
      if col + 1 < s then return nil end
      return row, s - 1, row, e
    end
    init = e + 1
  end
end

--- Wrap (or unwrap) a region with `open`/`close`.
local function toggle(sr, sc, er, ec, open, close)
  local inner = get_text(sr, sc, er, ec)
  if #inner >= #open + #close and inner:sub(1, #open) == open and inner:sub(-#close) == close then
    vim.api.nvim_buf_set_text(0, sr, sc, er, ec, vim.split(inner:sub(#open + 1, -#close - 1), "\n"))
    return
  end
  local before_start = math.max(sc - #open, 0)
  local before = get_text(sr, before_start, sr, sc)
  local line_end = #(vim.api.nvim_buf_get_lines(0, er, er + 1, false)[1] or "")
  local after = get_text(er, ec, er, math.min(ec + #close, line_end))
  if before == open and after == close then
    vim.api.nvim_buf_set_text(0, er, ec, er, ec + #close, { "" })
    vim.api.nvim_buf_set_text(0, sr, before_start, sr, sc, { "" })
    return
  end
  vim.api.nvim_buf_set_text(0, er, ec, er, ec, { close })
  vim.api.nvim_buf_set_text(0, sr, sc, sr, sc, { open })
end

--- Wrap the visual selection, or the word under the cursor.
function M.surround(open, close)
  close = close or open
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    local sr, sc, er, ec = visual_region()
    vim.cmd("normal! \27")
    toggle(sr, sc, er, ec, open, close)
    vim.api.nvim_win_set_cursor(0, { er + 1, ec + #open })
  else
    local sr, sc, er, ec = word_region()
    if not sr then
      -- nothing to wrap: drop the pair in and land in the middle
      local row, col = unpack(vim.api.nvim_win_get_cursor(0))
      vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, { open .. close })
      vim.api.nvim_win_set_cursor(0, { row, col + #open })
      vim.cmd("startinsert")
      return
    end
    toggle(sr, sc, er, ec, open, close)
  end
end

--- Insert-mode pair: types both halves and leaves the cursor inside.
function M.insert_pair(open, close)
  close = close or open
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, { open .. close })
  vim.api.nvim_win_set_cursor(0, { row, col + #open })
end

M.pairs = {
  bold = { "**", "**" },
  italic = { "*", "*" },
  code = { "`", "`" },
  link = { "[[", "]]" },
  highlight = { "==", "==" },
  strike = { "~~", "~~" },
  math = { "$", "$" },
}

--- Action factory used by the keymaps and the palette.
function M.action(kind)
  local pair = M.pairs[kind]
  return function() M.surround(pair[1], pair[2]) end
end

return M
