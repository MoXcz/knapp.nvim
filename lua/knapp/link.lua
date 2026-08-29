-- Parsing and rewriting of Obsidian links.
-- Handles [[note]], [[note|alias]], [[note#heading]], [[note#^block]],
-- ![[embed]] and markdown [text](note%20name.md).
local M = {}

function M.decode(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

function M.encode(s)
  -- Obsidian only percent-encodes what it must; spaces are the common case.
  return (s:gsub("[ %%#%?]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

function M.is_external(target)
  return target:match("^%a[%w+.-]*:") ~= nil or target == "" or target:sub(1, 1) == "#"
end

local function split_target(raw)
  local target, alias = raw, nil
  local pipe = target:find("|", 1, true)
  if pipe then
    alias = target:sub(pipe + 1)
    target = target:sub(1, pipe - 1)
  end
  local anchor = nil
  local hash = target:find("#", 1, true)
  if hash then
    anchor = target:sub(hash)
    target = target:sub(1, hash - 1)
  end
  return vim.trim(target), anchor, alias
end

--- Blank out fenced blocks and inline code spans, preserving byte offsets, so
--- code samples like `func f[P any](s store[P])` are not read as links.
local function mask_code(text)
  local out, pos, fence, len = {}, 1, nil, #text
  while pos <= len do
    local eol = text:find("\n", pos, true)
    local line_end = eol and (eol - 1) or len
    local line = text:sub(pos, line_end)
    local f = line:match("^%s*(```+)") or line:match("^%s*(~~~+)")
    if fence then
      out[#out + 1] = (" "):rep(#line)
      if f and #f >= #fence and f:sub(1, 1) == fence:sub(1, 1) then fence = nil end
    elseif f then
      fence = f
      out[#out + 1] = (" "):rep(#line)
    else
      out[#out + 1] = line:gsub("`+[^`\n]*`+", function(s) return (" "):rep(#s) end)
    end
    out[#out + 1] = eol and "\n" or ""
    pos = line_end + 2
  end
  return table.concat(out)
end

--- Find every link in `text`.
--- Returns a list of matches sorted by position, each:
---   { s, e, kind = "wiki"|"md", embed, target, anchor, alias, text }
--- `s`/`e` are 1-based inclusive byte offsets into `text`.
function M.scan(text)
  local out = {}
  text = mask_code(text)
  -- wikilinks (and embeds)
  local init = 1
  while true do
    local s, e, bang, inner = text:find("(!?)%[%[([^%[%]]-)%]%]", init)
    if not s then break end
    local target, anchor, alias = split_target(inner)
    out[#out + 1] = {
      s = s, e = e, kind = "wiki", embed = bang == "!",
      target = target, anchor = anchor, alias = alias,
    }
    init = e + 1
  end
  -- markdown links (and embeds); skip anything that is really a wikilink
  init = 1
  while true do
    local s, e, bang, label, dest = text:find("(!?)%[([^%[%]]-)%]%(([^%(%)]-)%)", init)
    if not s then break end
    init = e + 1
    local overlaps = false
    for _, m in ipairs(out) do
      if s <= m.e and e >= m.s then overlaps = true break end
    end
    if not overlaps then
      local raw = M.decode(vim.trim(dest))
      -- strip an optional "title" suffix
      raw = raw:gsub('%s+"[^"]*"$', "")
      if not M.is_external(raw) then
        local target, anchor = split_target(raw)
        out[#out + 1] = {
          s = s, e = e, kind = "md", embed = bang == "!",
          target = target, anchor = anchor, text = label,
        }
      end
    end
  end
  table.sort(out, function(a, b) return a.s < b.s end)
  return out
end

--- Rebuild a match's source text with a new target.
function M.render(m, target)
  if m.kind == "wiki" then
    local inner = target .. (m.anchor or "")
    if m.alias then inner = inner .. "|" .. m.alias end
    return (m.embed and "!" or "") .. "[[" .. inner .. "]]"
  end
  local dest = M.encode(target .. (m.anchor or ""))
  return (m.embed and "!" or "") .. "[" .. (m.text or "") .. "](" .. dest .. ")"
end

--- Rewrite every link for which `fn(match)` returns a new target string.
--- Returns the new text and the number of replacements.
function M.rewrite(text, fn)
  local matches = M.scan(text)
  local pieces, last, n = {}, 1, 0
  for _, m in ipairs(matches) do
    local new_target = fn(m)
    if new_target then
      pieces[#pieces + 1] = text:sub(last, m.s - 1)
      pieces[#pieces + 1] = M.render(m, new_target)
      last = m.e + 1
      n = n + 1
    end
  end
  if n == 0 then return text, 0 end
  pieces[#pieces + 1] = text:sub(last)
  return table.concat(pieces), n
end

--- The link under `col` (0-based byte column) on `line`, or nil.
function M.at(line, col)
  for _, m in ipairs(M.scan(line)) do
    if col + 1 >= m.s and col + 1 <= m.e then return m end
  end
  return nil
end

return M
