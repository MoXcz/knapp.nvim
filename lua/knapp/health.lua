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

--- Config keys whose default is `nil`, and so cannot be found by walking the
--- defaults table looking for unknown keys.
local KNOWN_NIL_DEFAULTS = { vault = true }

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
local function check_config(opts)
  local problems = {}
  local function expect(path, value, predicate, expected)
    if not predicate(value) then
      problems[#problems + 1] = ("%s = %s (expected %s)"):format(path, vim.inspect(value), expected)
    end
  end
  local function is(kind)
    return function(v) return type(v) == kind end
  end
  local function one_of(list)
    return function(v) return vim.tbl_contains(list, v) end
  end
  local function positive(v)
    return type(v) == "number" and v > 0
  end

  expect("ignore", opts.ignore, function(v) return vim.islist(v) end, "a list of directory names")
  expect("cache", opts.cache, is("string"), "a string")
  expect("fix_sessionoptions", opts.fix_sessionoptions, is("boolean"), "a boolean")

  expect("keys.enabled", opts.keys.enabled, is("boolean"), "a boolean")
  expect("keys.prefix", opts.keys.prefix, is("string"), "a string")
  expect("keys.insert", opts.keys.insert, is("boolean"), "a boolean")
  expect("keys.swap_ci", opts.keys.swap_ci, is("boolean"), "a boolean")

  expect("wrap.enabled", opts.wrap.enabled, is("boolean"), "a boolean")
  expect("wrap.width", opts.wrap.width, positive, "a positive number")
  expect("wrap.pad", opts.wrap.pad, is("boolean"), "a boolean")
  expect("wrap.min_pad", opts.wrap.min_pad, function(v) return type(v) == "number" and v >= 0 end,
    "a non-negative number")
  expect("wrap.display_line_motions", opts.wrap.display_line_motions, is("boolean"), "a boolean")

  expect("backlinks.auto", opts.backlinks.auto, is("boolean"), "a boolean")
  expect("backlinks.position", opts.backlinks.position, one_of({ "top", "bottom", "left", "right" }),
    '"top", "bottom", "left" or "right"')
  expect("backlinks.width", opts.backlinks.width, positive, "a positive number")
  expect("backlinks.height", opts.backlinks.height, positive, "a positive number")

  if #problems == 0 then
    ok("configuration is valid")
  else
    for _, problem in ipairs(problems) do
      error_(problem)
    end
  end

  -- Typos in a config key are silently ignored by tbl_deep_extend, so they are
  -- worth surfacing here where the check costs nothing at startup.
  local defaults = require("knapp.config").defaults
  local unknown = {}
  local function walk(user, default, prefix)
    if type(user) ~= "table" or type(default) ~= "table" then return end
    for key, value in pairs(user) do
      local path = prefix == "" and tostring(key) or (prefix .. "." .. tostring(key))
      if default[key] == nil and not (prefix == "" and KNOWN_NIL_DEFAULTS[key]) then
        unknown[#unknown + 1] = path
      else
        walk(value, default[key], path)
      end
    end
  end
  walk(opts, defaults, "")
  for _, path in ipairs(unknown) do
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
      info(label .. (" - missing, install the Obsidian %q community plugin or accept the defaults")
        :format(file.plugin))
    end
  end
end

local function check_cache(opts)
  local path = vim.fs.joinpath(opts.cache, "index.json")
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

  start("knapp.nvim: index")
  check_cache(opts)
  check_index()

  start("knapp.nvim: optional dependencies")
  check_optional()
end

return M
