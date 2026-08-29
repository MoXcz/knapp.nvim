-- Test helpers: build throwaway vaults on disk and point knapp at them.
--
-- knapp.config holds process-wide state, so every spec that touches a vault
-- must go through helpers.setup() and helpers.cleanup() to avoid leaking a
-- vault path (or a cache directory) into the next spec.
local M = {}

local root = nil
local counter = 0

local function mkdirp(path) vim.fn.mkdir(path, "p") end

local function write(path, text)
  mkdirp(vim.fs.dirname(path))
  local fd = assert(io.open(path, "w"), "could not write " .. path)
  fd:write(text)
  fd:close()
end

M.write = write

--- Root directory for everything this run creates. Removed by cleanup_all().
function M.root()
  if not root then
    root = vim.fs.joinpath(vim.uv.os_tmpdir(), ("knapp-test-%d"):format(vim.uv.os_getpid()))
    mkdirp(root)
  end
  return root
end

--- A fresh, guaranteed-empty directory.
--- Busted loads each spec file separately, so a module-level counter is not on
--- its own enough to guarantee a name nothing has used: wipe the directory
--- before handing it out, or one spec file's vault leaks into the next one's.
function M.tmpdir(label)
  counter = counter + 1
  local dir = vim.fs.joinpath(M.root(), ("%s-%d"):format(label or "d", counter))
  if vim.uv.fs_stat(dir) then vim.fn.delete(dir, "rf") end
  mkdirp(dir)
  return dir
end

--- Build a vault on disk.
---@param files table<string, string> vault-relative path -> file contents
---@param obsidian table<string, table>? ".obsidian/<name>" -> value to encode as JSON
---@return string vault absolute vault path
function M.vault(files, obsidian)
  local dir = M.tmpdir("vault")
  for rel, text in pairs(files or {}) do
    write(vim.fs.joinpath(dir, rel), text)
  end
  for name, value in pairs(obsidian or {}) do
    write(vim.fs.joinpath(dir, ".obsidian", name), vim.json.encode(value))
  end
  return dir
end

--- Build a vault and point knapp at it, with an isolated cache and no keymaps.
--- Returns the vault path.
function M.setup(files, obsidian, opts)
  local vault = M.vault(files, obsidian)
  require("knapp.obsidian_cfg").reload()
  require("knapp").setup(vim.tbl_deep_extend("force", {
    vault = vault,
    cache = M.tmpdir("cache"),
    keys = { enabled = false },
    wrap = { enabled = false },
    backlinks = { auto = false },
    fix_sessionoptions = false,
  }, opts or {}))
  -- reload() must run again: it memoizes against the config that was live when
  -- it was last called, and setup() has just replaced that config.
  require("knapp.obsidian_cfg").reload()
  local index = require("knapp.index")
  index.state.built = false
  index.build({ force = true })
  return vault
end

--- Reset the module-level state a spec may have dirtied.
function M.cleanup()
  M.captured = {}
  require("knapp.actions").clear_scan_cache()
  local index = require("knapp.index")
  index.state.built = false
  index.state.files, index.state.by_name, index.state.by_path, index.state.backlinks = {}, {}, {}, {}
  require("knapp.obsidian_cfg").reload()
  pcall(vim.api.nvim_clear_autocmds, { group = "knapp" })
  -- wipe every buffer a spec opened, so a later spec does not inherit one
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) ~= "" then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

--- Read a file back from a vault.
function M.read(vault, rel)
  local fd = io.open(vim.fs.joinpath(vault, rel), "r")
  if not fd then return nil end
  local text = fd:read("*a")
  fd:close()
  return text
end

--- Does `rel` exist in `vault`?
function M.exists(vault, rel) return vim.uv.fs_stat(vim.fs.joinpath(vault, rel)) ~= nil end

--- Messages captured from vim.notify. Written by the replacement installed in
--- tests/bootstrap.lua; read through M.notifications().
M.captured = {}

--- Everything vim.notify has been given since the last call, then reset.
function M.notifications()
  local out = M.captured
  M.captured = {}
  return out
end

--- Sorted copy, so specs can assert on a set without depending on table order.
function M.sorted(list)
  local out = vim.deepcopy(list)
  table.sort(out)
  return out
end

return M
