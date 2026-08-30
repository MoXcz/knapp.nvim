-- knapp.nvim - use an Obsidian vault from Neovim.
-- Keymaps and commands are buffer-local: they only exist inside the vault.
local config = require("knapp.config")
local util = require("knapp.util")

local M = {}

--- Window-local view options plus the readable-width padding.
local function apply_view()
  local view = require("knapp.view")
  local win = vim.api.nvim_get_current_win()
  if not view.is_note_win(win) then return end
  view.apply_options(win)
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(win) then view.pad(win) end
  end)
end

local function attach(bufnr)
  if vim.b[bufnr].knapp_attached then return end
  vim.b[bufnr].knapp_attached = true

  local wrap = config.opts.wrap
  if wrap.enabled and wrap.display_line_motions then
    local function motion(key)
      return function() return vim.v.count == 0 and ("g" .. key) or key end
    end
    for lhs, key in pairs({ j = "j", k = "k", ["<Down>"] = "j", ["<Up>"] = "k" }) do
      vim.keymap.set({ "n", "x" }, lhs, motion(key), {
        buffer = bufnr,
        expr = true,
        silent = true,
        desc = "knapp: move by display line",
      })
    end
  end

  require("knapp.keys").attach(bufnr)
end

--- Oldest Neovim this plugin is tested against. `vim.pack` in the install
--- snippet needs 0.12, but nothing in the plugin itself does.
local MIN_NVIM = "nvim-0.11"

function M.setup(opts)
  if vim.fn.has(MIN_NVIM) == 0 then
    vim.notify(
      ("knapp.nvim requires Neovim %s or newer"):format(MIN_NVIM:sub(6)),
      vim.log.levels.ERROR,
      { title = "knapp" }
    )
    return
  end
  config.setup(opts)
  local index = require("knapp.index")
  local keys = require("knapp.keys")
  local group = vim.api.nvim_create_augroup("knapp", { clear = true })
  keys.define_plugs()

  -- Defer the global defaults to VimEnter so that a user's own
  -- `<Plug>(Knapp...)` binding wins regardless of whether it is written before
  -- or after setup(). hasmapto() can only see bindings that already exist, and
  -- with a plugin manager the ordering is not the user's to control.
  if vim.v.vim_did_enter == 1 then
    keys.attach_global()
  else
    vim.api.nvim_create_autocmd("VimEnter", {
      group = group,
      once = true,
      callback = function() keys.attach_global() end,
    })
  end

  require("knapp.links").setup(group)

  if config.opts.fix_sessionoptions then vim.opt.sessionoptions:remove("blank") end

  -- keep scratch windows out of a session written on the way out (:restart)
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      pcall(function() require("knapp.index").flush_cache() end)
      pcall(function() require("knapp.view").clear() end)
      pcall(function() require("knapp.pane").close() end)
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "markdown",
    callback = function(ev)
      local name = vim.api.nvim_buf_get_name(ev.buf)
      if not config.in_vault(name) then return end
      attach(ev.buf)
      apply_view()
      vim.schedule(function() index.ensure() end)
    end,
  })

  -- the same note in a second window needs the view options too
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    pattern = "*.md",
    callback = function(ev)
      if config.in_vault(vim.api.nvim_buf_get_name(ev.buf)) then apply_view() end
    end,
  })

  -- Dragging a split boundary emits WinResized continuously, and each event
  -- would otherwise walk every window in the tab and resize two of them.
  local refresh_view = util.debounce(20, function() require("knapp.view").refresh() end)
  vim.api.nvim_create_autocmd({ "WinResized", "WinNew", "WinClosed", "TabEnter" }, {
    group = group,
    callback = refresh_view,
  })

  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function() require("knapp.view").leave_pad() end,
  })

  -- A single note switch fires both BufEnter and BufWinEnter, and each one
  -- would rebuild the pane. Collapse the pair, and read the current buffer
  -- when the work actually runs rather than when the event fired.
  if config.opts.backlinks.enabled then
    local refresh_pane = util.debounce(25, function()
      -- re-read the flag here, not just at setup: a debounced call outlives
      -- the autocommand that scheduled it
      if not config.opts.backlinks.enabled then return end
      local pane = require("knapp.pane")
      if pane.is_open() then
        pane.update()
      elseif config.opts.backlinks.auto then
        pane.open(false)
      end
    end)
    vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
      group = group,
      pattern = "*.md",
      callback = function(ev)
        if not config.in_vault(vim.api.nvim_buf_get_name(ev.buf)) then return end
        if vim.api.nvim_win_get_config(0).relative ~= "" then return end
        refresh_pane()
      end,
    })
  end

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*.md",
    callback = function(ev)
      local name = vim.api.nvim_buf_get_name(ev.buf)
      if not config.in_vault(name) or not index.state.built then return end
      index.update(config.rel(name))
      index.schedule_save()
      if config.opts.backlinks.enabled then require("knapp.pane").update(true) end
    end,
  })

  local subcommands = {
    palette = function() require("knapp.palette").open() end,
    rename = function() require("knapp.actions").rename() end,
    move = function() require("knapp.actions").move() end,
    merge = function() require("knapp.actions").merge() end,
    backlinks = function() require("knapp.actions").backlinks() end,
    follow = function() require("knapp.actions").follow() end,
    new = function() require("knapp.palette").new_note() end,
    find = function() require("knapp.palette").find_notes() end,
    grep = function() require("knapp.palette").grep_vault() end,
    index = function() require("knapp.actions").reindex() end,
    daily = function(args) require("knapp.journal").daily(tonumber(args[2]) or 0) end,
    weekly = function(args) require("knapp.journal").weekly(tonumber(args[2]) or 0) end,
    zettel = function() require("knapp.journal").zettel() end,
    calendar = function() require("knapp.calendar").open() end,
    template = function() require("knapp.template").insert() end,
    pane = function() require("knapp.pane").toggle() end,
    width = function() require("knapp.view").toggle() end,
    missing = function() require("knapp.links").show_missing() end,
  }

  vim.api.nvim_create_user_command("Knapp", function(cmd)
    local sub = cmd.fargs[1] or "palette"
    local fn = subcommands[sub]
    if not fn then
      vim.notify("unknown subcommand: " .. sub, vim.log.levels.ERROR, { title = "knapp" })
      return
    end
    fn(cmd.fargs)
  end, {
    nargs = "*",
    complete = function(lead)
      return vim.tbl_filter(function(k) return vim.startswith(k, lead) end, vim.tbl_keys(subcommands))
    end,
  })
end

return M
