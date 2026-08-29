-- Loaded by busted before any spec (see .busted `helper`).
--
-- Puts the plugin on 'runtimepath' so anything that goes through Neovim's own
-- loading (ftplugin, :checkhealth, doc tags) sees it, and makes sure specs
-- never write to the developer's real cache directory.
local repo = vim.uv.cwd()
vim.opt.runtimepath:prepend(repo)

-- Start every run from a clean scratch root, so a previous run that was
-- interrupted cannot leave files behind for this one to trip over.
local root = vim.fs.joinpath(vim.uv.os_tmpdir(), ("knapp-test-%d"):format(vim.uv.os_getpid()))
vim.fn.delete(root, "rf")

-- A spec that forgets to pass `cache` would otherwise clobber the cache of the
-- developer's own vault.
local config = require("knapp.config")
config.defaults.cache = vim.fs.joinpath(vim.uv.os_tmpdir(), ("knapp-test-%d"):format(vim.uv.os_getpid()), "cache")

-- Keymaps are defined with <leader>, which is resolved when the mapping is
-- created. Pin it so specs can assert on concrete left-hand sides.
vim.g.mapleader = " "

-- Keep failures readable: no swap files, no shada, no user config leaking in.
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"

-- The plugin reports through vim.notify, which would otherwise interleave with
-- busted's own output. Specs that care about a message read them back with
-- helpers.notifications().
local helpers = require("helpers")
vim.notify = function(msg, level, opts)
  helpers.captured[#helpers.captured + 1] = { msg = msg, level = level, opts = opts }
end
