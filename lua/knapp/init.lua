-- knapp.nvim - use an Obsidian vault from Neovim.
-- Keymaps and commands are buffer-local: they only exist inside the vault.
local config = require("knapp.config")

local M = {}

local function map(bufnr, mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = "knapp: " .. desc, silent = true })
end

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

  local actions = require("knapp.actions")
  local format = require("knapp.format")
  local palette = require("knapp.palette")
  local keys = config.opts.keys
  if not keys.enabled then return end
  local p = keys.prefix

  if config.opts.wrap.enabled and config.opts.wrap.display_line_motions then
    local function motion(key)
      return function() return vim.v.count == 0 and ("g" .. key) or key end
    end
    for _, key in ipairs({ "j", "k" }) do
      vim.keymap.set(
        { "n", "x" },
        key,
        motion(key),
        { buffer = bufnr, expr = true, silent = true, desc = "knapp: move by display line" }
      )
    end
    vim.keymap.set({ "n", "x" }, "<Down>", motion("j"), { buffer = bufnr, expr = true, silent = true })
    vim.keymap.set({ "n", "x" }, "<Up>", motion("k"), { buffer = bufnr, expr = true, silent = true })
  end

  map(bufnr, "n", "gf", actions.follow, "follow link")
  map(bufnr, "n", keys.palette, palette.open, "command palette")

  map(bufnr, { "n", "x" }, p .. "b", format.action("bold"), "bold")
  map(bufnr, { "n", "x" }, p .. "i", format.action("italic"), "italics")
  map(bufnr, { "n", "x" }, p .. "c", format.action("code"), "code")
  map(bufnr, { "n", "x" }, p .. "l", format.action("link"), "wikilink")
  map(bufnr, { "n", "x" }, p .. "h", format.action("highlight"), "highlight")

  map(bufnr, "n", p .. "r", actions.rename, "rename note")
  map(bufnr, "n", p .. "m", actions.move, "move note")
  map(bufnr, "n", p .. "M", actions.merge, "merge note")
  map(bufnr, "n", p .. "B", function() require("knapp.pane").toggle() end, "toggle backlinks pane")
  map(bufnr, "n", p .. "Q", actions.backlinks, "backlinks in quickfix")
  map(bufnr, "n", p .. "n", palette.new_note, "new note")
  map(bufnr, "n", p .. "f", palette.find_notes, "find notes")
  map(bufnr, "n", p .. "g", palette.grep_vault, "grep vault")
  map(bufnr, "n", p .. "R", actions.reindex, "rebuild index")
  map(bufnr, "n", p .. "W", function() require("knapp.view").toggle() end, "toggle readable width")
  map(bufnr, "n", p .. "t", require("knapp.template").insert, "insert template")

  if keys.insert then
    map(bufnr, "i", "<C-b>", function() format.insert_pair("**", "**") end, "bold")
    map(bufnr, "i", "<C-l>", function() format.insert_pair("[[", "]]") end, "wikilink")
    map(bufnr, "x", "<C-b>", format.action("bold"), "bold")
    map(bufnr, "x", "<C-l>", format.action("link"), "wikilink")
  end

  -- Opt-in: needs the kitty keyboard protocol, otherwise <C-i> is <Tab>.
  if keys.swap_ci then
    map(bufnr, "i", "<C-i>", function() format.insert_pair("*", "*") end, "italics")
    map(bufnr, "x", "<C-i>", format.action("italic"), "italics")
    map(bufnr, "n", "<C-k>", "<C-i>", "jump forward")
  end
end

--- Keymaps that work anywhere, since a journal note is often opened from
--- outside the vault.
local function global_keys()
  local keys = config.opts.keys
  if not keys.enabled then return end
  local p = keys.prefix
  local function set(lhs, rhs, desc) vim.keymap.set("n", p .. lhs, rhs, { desc = "knapp: " .. desc, silent = true }) end
  set("d", function() require("knapp.journal").daily() end, "daily note")
  set("y", function() require("knapp.journal").daily(-1) end, "yesterday's note")
  set("w", function() require("knapp.journal").weekly() end, "weekly note")
  set("z", function() require("knapp.journal").zettel() end, "new fleeting note")
  set("C", function() require("knapp.calendar").open() end, "calendar")
end

function M.setup(opts)
  config.setup(opts)
  local index = require("knapp.index")
  local group = vim.api.nvim_create_augroup("knapp", { clear = true })
  global_keys()

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

  vim.api.nvim_create_autocmd({ "WinResized", "WinNew", "WinClosed", "TabEnter" }, {
    group = group,
    callback = function()
      vim.schedule(function() require("knapp.view").refresh() end)
    end,
  })

  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function() require("knapp.view").leave_pad() end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
    group = group,
    pattern = "*.md",
    callback = function(ev)
      if not config.in_vault(vim.api.nvim_buf_get_name(ev.buf)) then return end
      if vim.api.nvim_win_get_config(0).relative ~= "" then return end
      local pane = require("knapp.pane")
      vim.schedule(function()
        if pane.is_open() then
          pane.update()
        elseif config.opts.backlinks.auto then
          pane.open(false)
        end
      end)
    end,
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*.md",
    callback = function(ev)
      local name = vim.api.nvim_buf_get_name(ev.buf)
      if not config.in_vault(name) or not index.state.built then return end
      index.update(config.rel(name))
      index.schedule_save()
      require("knapp.pane").update(true)
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
