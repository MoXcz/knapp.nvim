-- Moment.js-style date formatting, limited to the tokens Obsidian actually
-- writes into its settings and templates.
local M = {}

-- longest token first: the scanner takes the first match
local tokens = {
  { "YYYY", function(t) return os.date("%Y", t) end },
  { "gggg", function(t) return os.date("%G", t) end },
  { "MMMM", function(t) return os.date("%B", t) end },
  { "dddd", function(t) return os.date("%A", t) end },
  { "DDDD", function(t) return os.date("%j", t) end },
  { "MMM", function(t) return os.date("%b", t) end },
  { "ddd", function(t) return os.date("%a", t) end },
  { "gggg", function(t) return os.date("%G", t) end },
  { "YY", function(t) return os.date("%y", t) end },
  { "MM", function(t) return os.date("%m", t) end },
  { "DD", function(t) return os.date("%d", t) end },
  { "HH", function(t) return os.date("%H", t) end },
  { "hh", function(t) return os.date("%I", t) end },
  { "mm", function(t) return os.date("%M", t) end },
  { "ss", function(t) return os.date("%S", t) end },
  { "WW", function(t) return os.date("%V", t) end },
  { "ww", function(t) return os.date("%V", t) end },
  {
    "gg",
    function(t)
      return (os.date("%G", t) --[[@as string]]):sub(3)
    end,
  },
  { "Y", function(t) return os.date("%Y", t) end },
  { "M", function(t) return tostring(tonumber(os.date("%m", t))) end },
  { "D", function(t) return tostring(tonumber(os.date("%d", t))) end },
  { "H", function(t) return tostring(tonumber(os.date("%H", t))) end },
  { "h", function(t) return tostring(tonumber(os.date("%I", t))) end },
  { "m", function(t) return tostring(tonumber(os.date("%M", t))) end },
  { "s", function(t) return tostring(tonumber(os.date("%S", t))) end },
  { "W", function(t) return tostring(tonumber(os.date("%V", t))) end },
  { "w", function(t) return tostring(tonumber(os.date("%V", t))) end },
  { "A", function(t) return os.date("%p", t) end },
  {
    "a",
    function(t)
      return (os.date("%p", t) --[[@as string]]):lower()
    end,
  },
}

--- Format `time` (defaults to now) using a moment-style pattern.
--- Text inside [brackets] is literal.
function M.format(fmt, time)
  time = time or os.time()
  local out, i = {}, 1
  while i <= #fmt do
    local c = fmt:sub(i, i)
    if c == "[" then
      local close = fmt:find("]", i + 1, true)
      if close then
        out[#out + 1] = fmt:sub(i + 1, close - 1)
        i = close + 1
      else
        out[#out + 1] = c
        i = i + 1
      end
    else
      local matched = false
      for _, tok in ipairs(tokens) do
        if fmt:sub(i, i + #tok[1] - 1) == tok[1] then
          out[#out + 1] = tok[2](time)
          i = i + #tok[1]
          matched = true
          break
        end
      end
      if not matched then
        out[#out + 1] = c
        i = i + 1
      end
    end
  end
  return table.concat(out)
end

--- Shift a timestamp by `n` units ("d", "w", "M", "y").
function M.shift(time, n, unit)
  local t = os.date("*t", time or os.time()) --[[@as osdate]]
  if unit == "d" then
    t.day = t.day + n
  elseif unit == "w" then
    t.day = t.day + n * 7
  elseif unit == "M" then
    t.month = t.month + n
  elseif unit == "y" then
    t.year = t.year + n
  end
  return os.time(t)
end

--- Parse "+6d" / "-2w" style offsets. Returns nil when there is none.
function M.parse_offset(s)
  local sign, n, unit = s:match("^([+-])(%d+)([dwMy])$")
  if not sign then return nil end
  return tonumber(n) * (sign == "-" and -1 or 1), unit
end

--- Monday of the week containing `time`.
function M.week_start(time, first_day)
  time = time or os.time()
  local t = os.date("*t", time) --[[@as osdate]]
  local wday = t.wday -- 1 = Sunday
  local offset
  if first_day == "sunday" then
    offset = wday - 1
  else
    offset = (wday + 5) % 7 -- Monday = 0
  end
  t.day = t.day - offset
  t.hour, t.min, t.sec = 12, 0, 0
  return os.time(t)
end

--- Midday timestamp for a Y/M/D, safe against DST edges.
function M.of(year, month, day) return os.time({ year = year, month = month, day = day, hour = 12, min = 0, sec = 0 }) end

return M
