-- Vault index: name -> file, and file -> backlinks.
-- Built once per session from a cached, mtime-checked scan.
local config = require("knapp.config")
local link = require("knapp.link")
local util = require("knapp.util")

local uv = vim.uv
local M = {}

-- 2: entries carry lname/laliases, precomputed at parse time
local CACHE_VERSION = 2

M.state = {
  built = false,
  files = {}, -- rel -> { mtime, name, aliases = {}, targets = { "Note A", ... } }
  by_name = {}, -- lowercased name or alias -> { rel, ... }
  by_path = {}, -- lowercased vault-relative path without .md -> rel
  backlinks = {}, -- rel -> { src_rel, ... }
}

--- Path of this vault's cache file. Named after a hash of the vault path:
--- one shared file meant two Nvim instances on two vaults thrashing each
--- other's cache on every save.
function M.cache_file()
  return vim.fs.joinpath(config.opts.cache, ("index-%s.json"):format(vim.fn.sha256(config.opts.vault):sub(1, 12)))
end

local function ignored(name)
  for _, ig in ipairs(config.opts.ignore) do
    if name == ig then return true end
  end
  return false
end

--- Every markdown file in the vault: { rel = mtime }
local function walk()
  local out = {}
  local stack = { "" }
  -- seed with the root, or a symlink pointing back at the vault re-walks it
  local seen_dirs = { [uv.fs_realpath(config.abs("")) or config.abs("")] = true }
  while #stack > 0 do
    local dir = table.remove(stack)
    local handle = uv.fs_scandir(config.abs(dir))
    if handle then
      while true do
        local name, kind = uv.fs_scandir_next(handle)
        if not name then break end
        local rel = dir == "" and name or (dir .. "/" .. name)
        if kind == "link" then
          -- a symlinked note or folder is part of the vault; stat follows it
          local st = uv.fs_stat(config.abs(rel))
          kind = st and st.type or "link"
        end
        if kind == "directory" then
          if not ignored(name) and not ignored(rel) then
            -- a symlink can point back into the vault: never walk the same
            -- real directory twice, or a cycle walks forever
            local real = uv.fs_realpath(config.abs(rel))
            if real and not seen_dirs[real] then
              seen_dirs[real] = true
              stack[#stack + 1] = rel
            end
          end
        elseif util.is_md(name) then
          local st = uv.fs_stat(config.abs(rel))
          out[rel] = st and st.mtime.sec or 0
        end
      end
    end
  end
  return out
end

--- Aliases declared in the YAML frontmatter, if any.
local function parse_aliases(text)
  local fm = text:match("^%-%-%-\n(.-)\n%-%-%-")
  if not fm then return {} end
  local out = {}
  local inline = fm:match("\naliases:%s*%[(.-)%]") or fm:match("^aliases:%s*%[(.-)%]")
  if inline then
    for item in inline:gmatch("[^,]+") do
      out[#out + 1] = vim.trim(item):gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
    end
    return out
  end
  local in_block = false
  for line in (fm .. "\n"):gmatch("(.-)\n") do
    if line:match("^aliases:%s*$") then
      in_block = true
    elseif in_block then
      local item = line:match("^%s*%-%s*(.+)$")
      if item then
        out[#out + 1] = (vim.trim(item):gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1"))
      else
        in_block = false
      end
    end
  end
  return out
end

--- Parse one file into an index entry.
local function parse(rel, mtime)
  local text = util.read_file(config.abs(rel))
  if not text then return nil end
  local targets = {}
  for _, m in ipairs(link.scan(text)) do
    if m.target ~= "" then targets[#targets + 1] = m.target end
  end
  local name = vim.fs.basename(rel):sub(1, -4)
  local aliases = parse_aliases(text)
  -- lowered forms are stored (and cached) rather than recomputed: reindex()
  -- lowers every name and alias in the vault, on every rebuild
  local laliases = {}
  for i, alias in ipairs(aliases) do
    laliases[i] = alias:lower()
  end
  return {
    mtime = mtime,
    name = name,
    lname = name:lower(),
    aliases = aliases,
    laliases = laliases,
    targets = targets,
  }
end

--- `key` must already be lowercased; entries store their lowered forms.
local function add_name(map, key, rel)
  local list = map[key]
  if list then
    list[#list + 1] = rel
  else
    map[key] = { rel }
  end
end

-- notes() and folders() derive a sorted list from every file in the vault.
-- Rebuilding that per call showed up as 9.8ms of the 13.9ms a `[[` completion
-- took on a 3.6k-note vault, and it is also on the path of every palette and
-- picker call. Cached until something changes the file set.
local derived = { notes = nil, folders = nil }

--- Bumped whenever the file set or any note's links change, so callers that
--- cache anything derived from resolution (see links.lua) can tell their
--- cache is stale synchronously -- the `KnappIndexChanged` autocmd is
--- scheduled and arrives too late for a caller that reads right after an
--- update.
M.generation = 0

local function invalidate()
  derived.notes, derived.folders = nil, nil
  M.generation = M.generation + 1
end

--- Tell anything that renders links that what resolves may have changed.
--- Scheduled because reindex() runs from inside autocommands and file writes.
local function announce()
  vim.schedule(function() vim.api.nvim_exec_autocmds("User", { pattern = "KnappIndexChanged" }) end)
end

--- Rebuild by_name/by_path/backlinks from state.files.
function M.reindex()
  invalidate()
  local st = M.state
  st.by_name, st.by_path, st.backlinks = {}, {}, {}
  for rel, entry in pairs(st.files) do
    add_name(st.by_name, entry.lname, rel)
    for _, alias in ipairs(entry.laliases or {}) do
      add_name(st.by_name, alias, rel)
    end
    st.by_path[rel:sub(1, -4):lower()] = rel
  end
  -- Dedupe through a set rather than scanning the list that is being built:
  -- a hub note with n backlinks costs n^2/2 string comparisons that way.
  local seen = {}
  for rel, entry in pairs(st.files) do
    for _, target in ipairs(entry.targets) do
      local dest = M.resolve(target, rel)
      if dest then
        local set = seen[dest]
        if not set then
          set, seen[dest], st.backlinks[dest] = {}, {}, {}
          set = seen[dest]
        end
        if not set[rel] then
          set[rel] = true
          st.backlinks[dest][#st.backlinks[dest] + 1] = rel
        end
      end
    end
  end
end

--- Resolve a link target to a vault-relative path, Obsidian-style:
--- a path wins over a bare name, and a bare name prefers the closest file.
---@param target string link target as written in the note, without anchor
---@param from_rel string? vault-relative path of the linking note; breaks ties
---@return string? rel vault-relative path, or nil when nothing matches
function M.resolve(target, from_rel)
  if target == "" then return nil end
  local st = M.state
  local key = target:gsub("%.md$", ""):lower()
  if st.by_path[key] then return st.by_path[key] end
  local candidates = st.by_name[vim.fs.basename(key)]
  if not candidates or #candidates == 0 then return nil end
  if #candidates == 1 then return candidates[1] end
  local from_dir = from_rel and vim.fs.dirname(from_rel) or "."
  local best, best_score
  for _, rel in ipairs(candidates) do
    local score = (vim.fs.dirname(rel) == from_dir) and 0 or (1 + select(2, rel:gsub("/", "")))
    if not best_score or score < best_score then
      best, best_score = rel, score
    end
  end
  return best
end

--- Resolve to an absolute path, falling back to a literal file in the vault
--- (attachments, PDFs, images - anything the index does not track).
---
--- Public API (see the README): third-party snippets resolve embeds with it.
---@param target string link target as written in the note
---@param from_rel string? vault-relative path of the linking note; breaks ties
---@return string? abs absolute path, or nil when nothing matches
function M.resolve_file(target, from_rel)
  local rel = M.resolve(target, from_rel)
  if rel then return config.abs(rel) end
  local direct = config.abs(target)
  if uv.fs_stat(direct) then return direct end
  local att = require("knapp.obsidian_cfg").get().attachment_folder
  if att ~= "" then
    local guess = config.abs(vim.fs.joinpath(att, target))
    if uv.fs_stat(guess) then return guess end
  end
  return nil
end

local function load_cache()
  local text = util.read_file(M.cache_file())
  if not text then return nil end
  local ok, data = pcall(vim.json.decode, text)
  if not ok or type(data) ~= "table" or data.version ~= CACHE_VERSION then return nil end
  if data.vault ~= config.opts.vault then return nil end
  return data.files
end

local dirty = false
local save_timer = nil
local SAVE_DEBOUNCE_MS = 2000

--- Write the cache now, atomically.
---
--- Writing in place would leave a truncated file behind if Nvim died
--- mid-write, and a truncated cache is not merely slow to load: it decodes as
--- nothing and forces a cold rebuild. Write a sibling and rename over the
--- target, which is atomic on POSIX.
function M.save_cache()
  vim.fn.mkdir(config.opts.cache, "p")
  local path = M.cache_file()
  local tmp = path .. ".tmp"
  local fd = io.open(tmp, "w")
  if not fd then return false end
  local ok = pcall(
    function()
      fd:write(vim.json.encode({
        version = CACHE_VERSION,
        vault = config.opts.vault,
        files = M.state.files,
      }))
    end
  )
  fd:close()
  if not ok or not uv.fs_rename(tmp, path) then
    os.remove(tmp)
    return false
  end
  dirty = false
  return true
end

--- Mark the cache stale and write it a little later.
---
--- Encoding the whole index costs roughly as much as parsing several notes, so
--- doing it on every `:w` is wasted work when writes come in bursts. Losing a
--- scheduled write is harmless: cached entries are validated against each
--- file's mtime on load, so a stale cache is slower to warm, never wrong.
function M.schedule_save()
  dirty = true
  if not save_timer then save_timer = uv.new_timer() end
  save_timer:stop()
  save_timer:start(
    SAVE_DEBOUNCE_MS,
    0,
    vim.schedule_wrap(function()
      if dirty then M.save_cache() end
    end)
  )
end

--- Write any pending cache immediately. Called on the way out.
function M.flush_cache()
  if save_timer then
    save_timer:stop()
    save_timer:close()
    save_timer = nil
  end
  if dirty then M.save_cache() end
end

--- Walk the vault and split it against the cache: entries whose mtime is
--- unchanged are reused as-is, the rest are queued for parsing.
local function plan_build(opts)
  local cached = (not opts.force) and load_cache() or nil
  local found = walk()
  local files, queue = {}, {}
  for rel, mtime in pairs(found) do
    local old = cached and cached[rel]
    if old and old.mtime == mtime then
      files[rel] = old
    else
      queue[#queue + 1] = { rel, mtime }
    end
  end
  return { files = files, queue = queue, i = 1 }
end

local function finish_build(run)
  M.state.files = run.files
  M.reindex()
  M.state.built = true
  announce()
  M.save_cache()
  return { total = vim.tbl_count(run.files), parsed = #run.queue }
end

--- In-progress background build, or nil. ensure() drains it synchronously.
local pending = nil

--- Build the index now, synchronously.
function M.build(opts)
  pending = nil -- a full build supersedes any background one
  local run = plan_build(opts or {})
  while run.i <= #run.queue do
    local item = run.queue[run.i]
    run.files[item[1]] = parse(item[1], item[2])
    run.i = run.i + 1
  end
  return finish_build(run)
end

--- How long one slice of a background build may hold the main loop.
local BUILD_SLICE_MS = 5

--- Build the index without freezing the editor: parse in time-boxed slices,
--- yielding to the main loop between them. The cold build on a large vault
--- takes long enough to feel as a hang when the first note opens; nothing in
--- it needs to be synchronous. Anything that requires a complete index in the
--- meantime calls ensure(), which finishes the remaining work on the spot.
function M.build_background()
  if M.state.built or pending then return end
  pending = plan_build({})
  local run = pending
  local function step()
    if pending ~= run then return end -- drained by ensure() or superseded
    local deadline = uv.hrtime() + BUILD_SLICE_MS * 1e6
    while run.i <= #run.queue do
      local item = run.queue[run.i]
      run.files[item[1]] = parse(item[1], item[2])
      run.i = run.i + 1
      if uv.hrtime() >= deadline then
        vim.schedule(step)
        return
      end
    end
    pending = nil
    finish_build(run)
  end
  step()
end

function M.ensure()
  if M.state.built then return end
  if pending then
    local run = pending
    pending = nil
    while run.i <= #run.queue do
      local item = run.queue[run.i]
      run.files[item[1]] = parse(item[1], item[2])
      run.i = run.i + 1
    end
    finish_build(run)
  else
    M.build()
  end
end

--- Non-blocking ensure(): kick off a background build when none has started
--- and report whether the index is complete. For callers that can degrade
--- and repaint later, from the `KnappIndexChanged` autocmd the finished
--- build fires.
function M.try_ensure()
  if not M.state.built then M.build_background() end
  return M.state.built
end

local function reparse(rel)
  invalidate()
  local st = uv.fs_stat(config.abs(rel))
  if st then
    M.state.files[rel] = parse(rel, st.mtime.sec)
  else
    M.state.files[rel] = nil
  end
end

--- The keys an entry contributes to `by_name`: its basename and its aliases,
--- lowercased. Returned as a set.
local function name_keys(entry)
  local keys = {}
  if not entry then return keys end
  keys[entry.lname] = true
  for _, alias in ipairs(entry.laliases or {}) do
    keys[alias] = true
  end
  return keys
end

--- Would swapping `old` for `new` change how *other* notes' links resolve?
---
--- `resolve()` reads `by_path` and `by_name`. A note only contributes to those
--- through its path, its basename and its aliases, so as long as none of those
--- changed, every other note's links still resolve exactly where they did --
--- and only this note's own outgoing edges need touching. A body-only edit,
--- which is what almost every `:w` is, takes that path.
local function resolution_space_changed(old, new)
  if (old == nil) ~= (new == nil) then return true end
  if old == nil then return false end
  if old.name ~= new.name then return true end
  return not vim.deep_equal(name_keys(old), name_keys(new))
end

--- Every distinct note `entry` links to, as a set of vault-relative paths.
local function outgoing(rel, entry)
  local dests = {}
  if not entry then return dests end
  for _, target in ipairs(entry.targets) do
    local dest = M.resolve(target, rel)
    if dest then dests[dest] = true end
  end
  return dests
end

local function remove_backlink(dest, rel)
  local list = M.state.backlinks[dest]
  if not list then return end
  for i = #list, 1, -1 do
    if list[i] == rel then table.remove(list, i) end
  end
  if #list == 0 then M.state.backlinks[dest] = nil end
end

local function add_backlink(dest, rel)
  local list = M.state.backlinks[dest]
  if not list then
    M.state.backlinks[dest] = { rel }
    return
  end
  if not vim.tbl_contains(list, rel) then list[#list + 1] = rel end
end

--- Reparse a single file after a write, rename or delete.
---
--- Rebuilding every derived map here would make each `:w` cost a full pass
--- over the vault. Instead, retract the note's old outgoing edges and add its
--- new ones, and fall back to a full `reindex()` only when the note's name,
--- aliases or existence changed -- the cases that can move where *other*
--- notes' bare-name links point.
function M.update(rel)
  M.ensure()
  local old = M.state.files[rel]
  local old_dests = old and outgoing(rel, old) or {}
  reparse(rel)
  local new = M.state.files[rel]

  if resolution_space_changed(old, new) then
    M.reindex()
    announce()
    return
  end

  announce()
  local new_dests = outgoing(rel, new)
  for dest in pairs(old_dests) do
    if not new_dests[dest] then remove_backlink(dest, rel) end
  end
  for dest in pairs(new_dests) do
    if not old_dests[dest] then add_backlink(dest, rel) end
  end
end

--- Reparse several files, rebuilding the derived maps once at the end.
--- Every file whose links were rewritten must go through here, otherwise the
--- index keeps resolving the old link targets and backlinks disappear.
function M.update_many(rels)
  M.ensure()
  local seen = {}
  for _, rel in ipairs(rels) do
    if rel and not seen[rel] then
      seen[rel] = true
      reparse(rel)
    end
  end
  M.reindex()
  announce()
end

function M.backlinks(rel)
  M.ensure()
  return M.state.backlinks[rel] or {}
end

--- Every note as { rel, name, dir }, sorted by path.
---
--- The returned table is shared and cached; treat it as read-only.
---@return { rel: string, name: string, dir: string }[]
function M.notes()
  M.ensure()
  if derived.notes then return derived.notes end
  local out = {}
  for rel, entry in pairs(M.state.files) do
    out[#out + 1] = { rel = rel, name = entry.name, dir = vim.fs.dirname(rel) }
  end
  table.sort(out, function(a, b) return a.rel < b.rel end)
  derived.notes = out
  return out
end

--- Every directory that holds notes, plus the vault root.
---
--- The returned table is shared and cached; treat it as read-only.
---@return string[]
function M.folders()
  M.ensure()
  if derived.folders then return derived.folders end
  local seen = { ["."] = true }
  local out = { "." }
  for rel in pairs(M.state.files) do
    local dir = vim.fs.dirname(rel)
    while dir and dir ~= "." and not seen[dir] do
      seen[dir] = true
      out[#out + 1] = dir
      dir = vim.fs.dirname(dir)
    end
  end
  table.sort(out)
  derived.folders = out
  return out
end

return M
