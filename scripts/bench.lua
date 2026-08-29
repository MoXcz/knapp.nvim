#!/usr/bin/env -S nvim -l
-- Synthetic index benchmark:  make bench  (or: nvim -l scripts/bench.lua)
--
-- Builds a throwaway vault, then measures the two costs that used to dominate
-- the write path. Numbers vary by machine; what matters is the ratio.

vim.opt.runtimepath:prepend(vim.uv.cwd())

local NOTES = tonumber(vim.env.BENCH_NOTES) or 3000
-- Fewer hubs means longer backlink lists, which is what the old dedupe scanned
-- linearly on every insert. BENCH_HUBS=1 is the worst case.
local HUBS = tonumber(vim.env.BENCH_HUBS) or 5

local root = vim.fs.joinpath(vim.uv.os_tmpdir(), "knapp-bench")
vim.fn.delete(root, "rf")
local vault = vim.fs.joinpath(root, "vault")

local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local fd = assert(io.open(path, "w"))
  fd:write(text)
  fd:close()
end

for i = 1, HUBS do
  write(vim.fs.joinpath(vault, ("hub %d.md"):format(i)), "# hub\n")
end
for i = 1, NOTES do
  local body = {
    ("# note %d"):format(i),
    "",
    ("Links to [[hub %d]] and [[note %d]]."):format((i % HUBS) + 1, (i % NOTES) + 1),
    "",
    "Some prose that is not a link at all, to give the scanner something to do.",
  }
  write(vim.fs.joinpath(vault, ("folder%d/note %d.md"):format(i % 20, i)), table.concat(body, "\n"))
end

require("knapp").setup({
  vault = vault,
  cache = vim.fs.joinpath(root, "cache"),
  keys = { enabled = false },
})

local index = require("knapp.index")

local function ms(fn, runs)
  runs = runs or 1
  local t = vim.uv.hrtime()
  for _ = 1, runs do
    fn()
  end
  return (vim.uv.hrtime() - t) / 1e6 / runs
end

--- Milliseconds, or microseconds when that would round to zero.
local function fmt(v) return v < 1 and ("%7.0f us"):format(v * 1000) or ("%7.1f ms"):format(v) end

--- The pre-P2 backlink build: dedupe by scanning the list being appended to.
local function old_reindex()
  local st = index.state
  st.by_name, st.by_path, st.backlinks = {}, {}, {}
  for rel, entry in pairs(st.files) do
    local function add(key)
      key = key:lower()
      st.by_name[key] = st.by_name[key] or {}
      table.insert(st.by_name[key], rel)
    end
    add(entry.name)
    for _, alias in ipairs(entry.aliases or {}) do
      add(alias)
    end
    st.by_path[rel:sub(1, -4):lower()] = rel
  end
  for rel, entry in pairs(st.files) do
    for _, target in ipairs(entry.targets) do
      local dest = index.resolve(target, rel)
      if dest then
        st.backlinks[dest] = st.backlinks[dest] or {}
        if not vim.tbl_contains(st.backlinks[dest], rel) then table.insert(st.backlinks[dest], rel) end
      end
    end
  end
end

print(("vault: %d notes, %d hub notes (~%d backlinks each)\n"):format(NOTES + HUBS, HUBS, NOTES / HUBS))

index.state.built = false
print(("cold build                %s"):format(fmt(ms(function() index.build({ force = true }) end))))

local p2_old = ms(old_reindex, 3)
local p2_new = ms(index.reindex, 3)
print(("\nreindex, old dedupe       %s"):format(fmt(p2_old)))
print(("reindex, set dedupe (P2)  %s   %.1fx"):format(fmt(p2_new), p2_old / p2_new))

-- One `:w` on a note whose body changed but whose name and aliases did not.
local target = ("folder1/note %d.md"):format(1)
local old_write = function()
  local st = vim.uv.fs_stat(vim.fs.joinpath(vault, target))
  index.state.files[target].mtime = st and st.mtime.sec or 0
  index.reindex()
end
local w_old = ms(old_write, 3)
local w_new = ms(function() index.update(target) end, 200)
print(("\n:w  old, full reindex     %s"):format(fmt(w_old)))
print((":w  new, edge diff (P1)   %s   %.0fx"):format(fmt(w_new), w_old / w_new))

print(("\ncache encode+write        %s  (was on every :w, now debounced 2s)"):format(fmt(ms(index.save_cache, 3))))

vim.fn.delete(root, "rf")
