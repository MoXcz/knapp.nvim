-- :checkhealth knapp
--
-- Most of what this plugin does is derived from JSON files inside the user's
-- vault, written by Obsidian and by third-party Obsidian community plugins.
-- When a note lands in the wrong folder the cause is almost always one of
-- those files being absent or shaped differently than expected, so this report
-- names each one explicitly rather than reporting "it works".
local M = {}

local start = vim.health.start
local ok = vim.health.ok
local info = vim.health.info
local warn = vim.health.warn
local error_ = vim.health.error

local MIN_NVIM = "nvim-0.11"

local MINIMAL_CONFIG = [[
-- minimal.lua - reproduce an issue with:  nvim --clean -u minimal.lua
vim.opt.runtimepath:prepend("/path/to/knapp.nvim")
require("knapp").setup({ vault = "/path/to/vault" })
]]

--- Files knapp reads out of <vault>/.obsidian.
--- `core` files ship with Obsidian itself; `community` ones only exist when
--- the matching community plugin is installed.
local OBSIDIAN_FILES = {
  { name = "app.json", core = true, what = "new-note folder, attachment folder" },
  { name = "daily-notes.json", core = true, what = "daily note folder, format and template" },
  { name = "templates.json", core = true, what = "templates folder, date and time formats" },
  {
    name = "plugins/calendar/data.json",
    plugin = "Calendar",
    what = "weekly note folder, format, template and week start",
  },
  {
    name = "zk-prefixer.json",
    plugin = "Zettelkasten Prefixer",
    what = "fleeting-note folder, timestamp format and template",
  },
}

local function check_nvim()
  local v = vim.version()
  if vim.fn.has(MIN_NVIM) == 1 then
    ok(("Neovim %d.%d.%d (requires %s+)"):format(v.major, v.minor, v.patch, MIN_NVIM:sub(6)))
  else
    error_(("knapp.nvim requires Neovim %s or newer"):format(MIN_NVIM:sub(6)))
  end
end

--- Report every type error in the merged config rather than stopping at the
--- first one: a user fixing a config wants the whole list.
--- Report every configuration problem, not just the first, using the same
--- schema `config.setup()` validates against so the two cannot disagree.
local function check_config(opts)
  local config = require("knapp.config")

  local problems = config.validate(opts)
  if #problems == 0 then
    ok("configuration is valid")
  else
    for _, problem in ipairs(problems) do
      error_(problem)
    end
  end

  for _, path in ipairs(config.unknown_keys(opts)) do
    warn(("unknown option `%s` - a typo? it has no effect"):format(path))
  end
end

local function check_vault(opts)
  local vault = opts.vault
  if vim.fn.isdirectory(vault) == 0 then
    error_(("vault does not exist: %s"):format(vault))
    return false
  end
  ok(("vault: %s"):format(vault))
  return true
end

local function check_obsidian(opts)
  local dir = vim.fs.joinpath(opts.vault, ".obsidian")
  if not vim.uv.fs_stat(dir) then
    warn((".obsidian not found in %s"):format(opts.vault), {
      "This does not look like a vault Obsidian has opened.",
      "knapp falls back to built-in defaults for every folder, format and template.",
    })
    return
  end
  ok(".obsidian found")

  for _, file in ipairs(OBSIDIAN_FILES) do
    local path = vim.fs.joinpath(dir, file.name)
    local exists = vim.uv.fs_stat(path) ~= nil
    local label = (".obsidian/%s - %s"):format(file.name, file.what)
    if exists then
      local fd = io.open(path, "r")
      local text = fd and fd:read("*a") or ""
      if fd then fd:close() end
      if vim.json and select(1, pcall(vim.json.decode, text)) then
        ok(label)
      else
        error_(label .. " - is not valid JSON, knapp falls back to defaults")
      end
    elseif file.core then
      warn(label .. " - missing, using built-in defaults")
    else
      info(label .. (" - missing, install the Obsidian %q community plugin or accept the defaults"):format(file.plugin))
    end
  end
end

local function check_cache()
  local path = require("knapp.index").cache_file()
  local stat = vim.uv.fs_stat(path)
  if not stat then
    info(("no index cache yet (%s)"):format(path))
    return
  end
  ok(("index cache: %s (%.1f KiB)"):format(path, stat.size / 1024))
end

local function check_index()
  local index = require("knapp.index")
  if not index.state.built then
    info("index not built yet - it is built lazily when the first note is opened")
    return
  end
  local notes = vim.tbl_count(index.state.files)
  local linked = vim.tbl_count(index.state.backlinks)
  ok(("index built: %d notes, %d of them linked to"):format(notes, linked))
end

--- knapp edits a global option when `fix_sessionoptions` is set. A plugin doing
--- that should at least say so out loud. See |knapp-config-sessionoptions|.
local function check_sessionoptions(opts)
  if not opts.fix_sessionoptions then
    info("fix_sessionoptions is off - :mksession will capture knapp's scratch windows")
    return
  end
  if vim.tbl_contains(vim.opt.sessionoptions:get(), "blank") then
    warn("fix_sessionoptions is on but 'sessionoptions' still contains \"blank\"", {
      "Something re-added it after setup(). :mksession will capture knapp's scratch windows.",
    })
  else
    info("'sessionoptions' has had \"blank\" removed by knapp (fix_sessionoptions)")
  end
end

local function check_optional()
  if pcall(require, "snacks") then
    ok("snacks.nvim - picker-backed palette, note finder and vault grep")
  else
    info("snacks.nvim not found - palette, find and grep fall back to vim.ui.select")
  end

  if pcall(require, "render-markdown") then
    ok("render-markdown.nvim - live markdown preview")
  else
    info("render-markdown.nvim not found - knapp does not render markdown itself")
  end

  if vim.fn.executable("rg") == 1 then
    ok("rg - available for vault grep")
  else
    info("rg not found - the vim.ui.select grep fallback uses 'grepprg' (" .. vim.o.grepprg .. ")")
  end
end

function M.check()
  start("knapp.nvim")
  check_nvim()

  local loaded, config = pcall(require, "knapp.config")
  if not loaded then
    error_("could not load knapp.config: " .. tostring(config))
    return
  end

  local opts = config.opts
  if not opts.vault or opts.vault == "" then
    error_("setup() has not been called, or `vault` is unset", {
      'require("knapp").setup({ vault = "~/notes" })',
    })
    info("minimal reproducer config:\n" .. MINIMAL_CONFIG)
    return
  end

  check_config(opts)
  if not check_vault(opts) then return end

  start("knapp.nvim: Obsidian settings")
  check_obsidian(opts)

  check_sessionoptions(opts)

  start("knapp.nvim: index")
  check_cache()
  check_index()

  start("knapp.nvim: optional dependencies")
  check_optional()
end

return M
