-- Moment.js-style date formatting, limited to the tokens Obsidian actually
-- writes into its settings and templates.
local M = {}

-- WW/ww format the ISO week number (%V) and gg/gggg the ISO week-numbering
-- year (%G), which is correct moment.js behaviour -- but a "YYYY-[W]WW"
-- format mixes the calendar year into an ISO week name, and the two disagree
-- in the days around New Year where %Y ~= %G.
local tokens = {
  { "YYYY", function(t) return os.date("%Y", t) end },
  { "gggg", function(t) return os.date("%G", t) end },
  { "MMMM", function(t) return os.date("%B", t) end },
  { "dddd", function(t) return os.date("%A", t) end },
  { "DDDD", function(t) return os.date("%j", t) end },
  { "MMM", function(t) return os.date("%b", t) end },
  { "ddd", function(t) return os.date("%a", t) end },
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

-- The scanner wants the longest token that matches at the current position.
-- Walking the list compared up to 30 prefixes per character; a hash per token
-- length makes it one lookup per length instead, longest first.
local by_len, max_len = {}, 0
for _, tok in ipairs(tokens) do
  local n = #tok[1]
  by_len[n] = by_len[n] or {}
  by_len[n][tok[1]] = tok[2]
  if n > max_len then max_len = n end
end

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
      for n = max_len, 1, -1 do
        local map = by_len[n]
        local fn = map and map[fmt:sub(i, i + n - 1)]
        if fn then
          out[#out + 1] = fn(time)
          i = i + n
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

--- Broken-down time. The stdlib annotation types every field as
--- `integer|string`, because `os.date` can be asked for either; `*t` only ever
--- returns numbers, and saying so keeps arithmetic on these fields checkable.
--- Extends `osdateparam` so the result can be handed straight back to
--- `os.time`.
---@class knapp.DateParts : osdateparam
---@field year integer
---@field month integer
---@field day integer
---@field hour integer
---@field min integer
---@field sec integer
---@field wday integer 1 = Sunday
---@field yday integer
---@field isdst boolean

--- `os.date("*t")`, with the fields typed as the numbers they are.
---@param time integer?
---@return knapp.DateParts
function M.parts(time)
  return os.date("*t", time or os.time()) --[[@as knapp.DateParts]]
end

--- Shift a timestamp by `n` units ("d", "w", "M", "y").
function M.shift(time, n, unit)
  local t = M.parts(time)
  if unit == "d" then
    t.day = t.day + n
  elseif unit == "w" then
    t.day = t.day + n * 7
  elseif unit == "M" then
    t.month = t.month + n
  elseif unit == "y" then
    t.year = t.year + n
  end
  -- os.time wants the stdlib's own osdateparam; knapp.DateParts is the same
  -- shape with the fields narrowed to integers
  return os.time(t --[[@as osdateparam]])
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
  local t = M.parts(time)
  local wday = t.wday -- 1 = Sunday
  local offset
  if first_day == "sunday" then
    offset = wday - 1
  else
    offset = (wday + 5) % 7 -- Monday = 0
  end
  t.day = t.day - offset
  t.hour, t.min, t.sec = 12, 0, 0
  -- os.time wants the stdlib's own osdateparam; knapp.DateParts is the same
  -- shape with the fields narrowed to integers
  return os.time(t --[[@as osdateparam]])
end

--- Midday timestamp for a Y/M/D, safe against DST edges.
function M.of(year, month, day) return os.time({ year = year, month = month, day = day, hour = 12, min = 0, sec = 0 }) end

return M
