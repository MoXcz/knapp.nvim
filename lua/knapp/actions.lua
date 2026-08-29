-- Vault actions: follow links, rename/move/merge notes and keep every link
-- pointing at the right file.
local config = require("knapp.config")
local index = require("knapp.index")
local link = require("knapp.link")
local ocfg = require("knapp.obsidian_cfg")

local uv = vim.uv
local M = {}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "knapp" })
end

local function read_file(path)
  local fd = io.open(path, "r")
  if not fd then return nil end
  local text = fd:read("*a")
  fd:close()
  return text
end

--- Write `text` to `path`, going through a loaded buffer when there is one so
--- open windows stay in sync. Returns false if the buffer has unsaved changes.
local function write_file(path, text)
  local bufnr = vim.fn.bufnr(path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    if vim.bo[bufnr].modified then return false end
    local lines = vim.split(text, "\n", { plain = true })
    if lines[#lines] == "" then table.remove(lines) end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_buf_call(bufnr, function() vim.cmd("silent noautocmd write") end)
    return true
  end
  local fd = io.open(path, "w")
  if not fd then return false end
  fd:write(text)
  fd:close()
  return true
end

--- Vault-relative path of the current buffer, or nil.
function M.current()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" or not config.in_vault(path) then return nil end
  local rel = config.rel(path)
  if rel:sub(-3) ~= ".md" then return nil end
  return rel
end

local function require_current()
  local rel = M.current()
  if not rel then notify("not a note inside the vault", vim.log.levels.WARN) end
  return rel
end

--- How many notes would share this basename once `moving` lives at `to_rel`.
local function name_count(name, moving, to_rel)
  local n = 0
  for rel in pairs(index.state.files) do
    if rel ~= moving and vim.fs.basename(rel):sub(1, -4) == name then n = n + 1 end
  end
  if not index.state.files[to_rel] and vim.fs.basename(to_rel):sub(1, -4) == name then n = n + 1 end
  return n
end

--- Point every link that resolves to `old_rel` at `new_rel`.
--- Returns the list of files changed and the list of files skipped.
function M.rewrite_backlinks(old_rel, new_rel)
  index.ensure()
  local sources = vim.deepcopy(index.backlinks(old_rel))
  local new_name = vim.fs.basename(new_rel):sub(1, -4)
  local unique = name_count(new_name, old_rel, new_rel) <= 1
  -- links that go through an alias keep working, so leave them untouched
  local aliases = {}
  for _, a in ipairs((index.state.files[old_rel] or {}).aliases or {}) do aliases[a:lower()] = true end
  local changed, skipped = {}, {}
  for _, src in ipairs(sources) do
    local path = config.abs(src)
    local text = read_file(path)
    if text then
      local new_text, n = link.rewrite(text, function(m)
        if index.resolve(m.target, src) ~= old_rel then return nil end
        if m.kind == "md" then return new_rel end
        -- keep bare-name links bare when the name is still unambiguous
        local was_bare = not m.target:find("/", 1, true)
        if was_bare and aliases[m.target:lower()] then return nil end
        if was_bare and unique then return new_name end
        return new_rel:sub(1, -4)
      end)
      if n > 0 then
        if write_file(path, new_text) then
          changed[#changed + 1] = src
        else
          skipped[#skipped + 1] = src
        end
      end
    end
  end
  return changed, skipped
end

--- Move the note at `rel` to `new_rel`, updating links and open buffers.
function M.move_note(rel, new_rel)
  if rel == new_rel then return true end
  local src, dest = config.abs(rel), config.abs(new_rel)
  if uv.fs_stat(dest) then
    notify(("%s already exists"):format(new_rel), vim.log.levels.ERROR)
    return false
  end
  local bufnr = vim.fn.bufnr(src)
  if bufnr ~= -1 and vim.bo[bufnr].modified then
    notify("save the note first", vim.log.levels.ERROR)
    return false
  end
  local changed, skipped = M.rewrite_backlinks(rel, new_rel)
  vim.fn.mkdir(vim.fs.dirname(dest), "p")
  local ok, err = uv.fs_rename(src, dest)
  if not ok then
    notify("move failed: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    vim.api.nvim_buf_set_name(bufnr, dest)
    vim.api.nvim_buf_call(bufnr, function() vim.cmd("silent noautocmd write!") end)
  end
  -- the rewritten sources must be reparsed too, or the index keeps resolving
  -- the old target and every backlink is lost
  index.update_many(vim.list_extend({ rel, new_rel }, changed))
  index.save_cache()
  vim.cmd("checktime")
  local n = #changed
  local msg = ("%s -> %s (%d file%s relinked)"):format(rel, new_rel, n, n == 1 and "" or "s")
  if #skipped > 0 then
    msg = msg .. ("\nskipped %d file(s) with unsaved changes: %s"):format(#skipped, table.concat(skipped, ", "))
    notify(msg, vim.log.levels.WARN)
  else
    notify(msg)
  end
  return true
end

--- Rename the current note, keeping it in the same folder.
function M.rename()
  local rel = require_current()
  if not rel then return end
  index.ensure()
  local name = vim.fs.basename(rel):sub(1, -4)
  vim.ui.input({ prompt = "Rename note: ", default = name }, function(input)
    if not input or vim.trim(input) == "" or input == name then return end
    input = vim.trim(input):gsub("%.md$", "")
    local dir = vim.fs.dirname(rel)
    local new_rel = dir == "." and (input .. ".md") or (dir .. "/" .. input .. ".md")
    M.move_note(rel, new_rel)
  end)
end

--- Move the current note to another folder.
function M.move()
  local rel = require_current()
  if not rel then return end
  index.ensure()
  local folders = index.folders()
  vim.ui.select(folders, { prompt = "Move note to folder" }, function(dir)
    if not dir then return end
    local base = vim.fs.basename(rel)
    local new_rel = dir == "." and base or (dir .. "/" .. base)
    M.move_note(rel, new_rel)
  end)
end

--- Append the current note to another note, relink, and trash the original.
function M.merge()
  local rel = require_current()
  if not rel then return end
  index.ensure()
  if vim.bo.modified then
    notify("save the note first", vim.log.levels.ERROR)
    return
  end
  local items = {}
  for _, note in ipairs(index.notes()) do
    if note.rel ~= rel then items[#items + 1] = note.rel end
  end
  vim.ui.select(items, { prompt = ("Merge %q into"):format(vim.fs.basename(rel)) }, function(target_rel)
    if not target_rel then return end
    local source_text = read_file(config.abs(rel))
    local target_text = read_file(config.abs(target_rel))
    if not source_text or not target_text then
      notify("could not read one of the notes", vim.log.levels.ERROR)
      return
    end
    if not target_text:match("\n$") then target_text = target_text .. "\n" end
    if not write_file(config.abs(target_rel), target_text .. "\n" .. source_text) then
      notify("target has unsaved changes", vim.log.levels.ERROR)
      return
    end
    local changed, skipped = M.rewrite_backlinks(rel, target_rel)
    M.trash(rel, true)
    index.update_many(vim.list_extend({ rel, target_rel }, changed))
    index.save_cache()
    vim.cmd.edit(vim.fn.fnameescape(config.abs(target_rel)))
    vim.cmd("normal! G")
    local msg = ("merged %s into %s (%d file%s relinked)")
        :format(rel, target_rel, #changed, #changed == 1 and "" or "s")
    notify(#skipped > 0 and (msg .. "\nskipped: " .. table.concat(skipped, ", ")) or msg,
      #skipped > 0 and vim.log.levels.WARN or nil)
  end)
end

--- Move a note into the vault's .trash, like Obsidian does.
function M.trash(rel, quiet)
  local src = config.abs(rel)
  local dest = config.abs(vim.fs.joinpath(".trash", vim.fs.basename(rel)))
  vim.fn.mkdir(vim.fs.dirname(dest), "p")
  local i = 1
  while uv.fs_stat(dest) do
    dest = config.abs(vim.fs.joinpath(".trash", ("%s %d.md"):format(vim.fs.basename(rel):sub(1, -4), i)))
    i = i + 1
  end
  local bufnr = vim.fn.bufnr(src)
  local ok, err = uv.fs_rename(src, dest)
  if not ok then
    notify("trash failed: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
  index.update(rel)
  if not quiet then notify("trashed " .. rel) end
  return true
end

local function jump_to_anchor(anchor)
  if not anchor or anchor == "" then return end
  local body = anchor:sub(2)
  local pattern
  if body:sub(1, 1) == "^" then
    pattern = vim.pesc(body) .. "%s*$"
  else
    pattern = "^#+%s+" .. vim.pesc(body) .. "%s*$"
  end
  for i, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if line:lower():match(pattern:lower()) then
      vim.api.nvim_win_set_cursor(0, { i, 0 })
      vim.cmd("normal! zz")
      return
    end
  end
end

--- Create a note named `name` in Obsidian's configured new-note folder.
function M.create_note(name, open)
  local folder = ocfg.get().new_note_folder
  local rel = name:find("/", 1, true) and name or vim.fs.joinpath(folder, name)
  if rel:sub(-3) ~= ".md" then rel = rel .. ".md" end
  local path = config.abs(rel)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  if not uv.fs_stat(path) then
    local fd = io.open(path, "w")
    if fd then fd:close() end
  end
  if open ~= false then
    vim.cmd("normal! m'")
    vim.cmd.edit(vim.fn.fnameescape(path))
  end
  index.update(rel)
  return rel
end

--- gf replacement: follow the link under the cursor, else fall back to gf.
function M.follow()
  index.ensure()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local m = link.at(line, col)
  if not m then
    local ok = pcall(vim.cmd, "normal! gf")
    if not ok then notify("no link under cursor", vim.log.levels.WARN) end
    return
  end
  local rel = M.current()
  local path = index.resolve_file(m.target, rel)
  if path then
    vim.cmd("normal! m'")
    vim.cmd.edit(vim.fn.fnameescape(path))
    jump_to_anchor(m.anchor)
    return
  end
  local choice = vim.fn.confirm(("%q does not exist. Create it?"):format(m.target), "&Yes\n&No", 1)
  if choice == 1 then M.create_note(m.target) end
end

--- Every link pointing at `rel`, as { rel, name, filename, lnum, col, text }.
function M.backlink_items(rel)
  index.ensure()
  local items = {}
  for _, src in ipairs(index.backlinks(rel)) do
    local path = config.abs(src)
    local text = read_file(path) or ""
    local lnum = 1
    for line in (text .. "\n"):gmatch("(.-)\n") do
      for _, m in ipairs(link.scan(line)) do
        if index.resolve(m.target, src) == rel then
          items[#items + 1] = {
            rel = src,
            name = vim.fs.basename(src):sub(1, -4),
            filename = path,
            lnum = lnum,
            col = m.s,
            text = vim.trim(line),
          }
        end
      end
      lnum = lnum + 1
    end
  end
  table.sort(items, function(a, b)
    if a.name == b.name then return a.lnum < b.lnum end
    return a.name:lower() < b.name:lower()
  end)
  return items
end

--- Backlinks of the current note in the quickfix list.
function M.backlinks()
  local rel = require_current()
  if not rel then return end
  local items = M.backlink_items(rel)
  if #items == 0 then
    notify("no backlinks to " .. rel)
    return
  end
  vim.fn.setqflist({}, " ", { title = "backlinks: " .. rel, items = items })
  vim.cmd.copen()
end

--- Rebuild the index from scratch.
function M.reindex()
  local r = index.build({ force = true })
  notify(("indexed %d notes"):format(r.total))
end

return M
