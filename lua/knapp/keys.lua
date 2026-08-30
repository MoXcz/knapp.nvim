-- Keymaps, as data.
--
-- Every action gets a <Plug> mapping, always, whether or not the user wants
-- knapp's default bindings. That is what `:help lua-plugin-keymaps` asks for:
-- one line in a user's config rebinds anything, binding it does not error when
-- the plugin is absent, and `hasmapto()` lets the defaults step aside for a
-- user who has already bound the action themselves.
local config = require("knapp.config")

local M = {}

--- `lhs` is either `key` (literal), `suffix` (appended to `keys.prefix`), or
--- `palette` (taken from `keys.palette`, so it stays configurable).
---@class knapp.Action
---@field plug string suffix of the <Plug> name
---@field modes string|string[]
---@field desc string
---@field fn function
---@field key string?
---@field suffix string?
---@field palette boolean?
---@field group string? only bound when the matching `keys.<group>` is set
---@field feature string? only bound when `<feature>.enabled` is not false

--- Actions available inside a vault note.
---@type knapp.Action[]
M.buffer = {
  {
    plug = "Follow",
    modes = "n",
    key = "gf",
    desc = "follow link",
    fn = function() require("knapp.actions").follow() end,
  },
  {
    plug = "Palette",
    modes = "n",
    palette = true,
    desc = "command palette",
    fn = function() require("knapp.palette").open() end,
  },

  {
    plug = "Bold",
    modes = { "n", "x" },
    suffix = "b",
    desc = "bold",
    fn = function() require("knapp.format").action("bold")() end,
  },
  {
    plug = "Italic",
    modes = { "n", "x" },
    suffix = "i",
    desc = "italics",
    fn = function() require("knapp.format").action("italic")() end,
  },
  {
    plug = "Code",
    modes = { "n", "x" },
    suffix = "c",
    desc = "code",
    fn = function() require("knapp.format").action("code")() end,
  },
  {
    plug = "Link",
    modes = { "n", "x" },
    suffix = "l",
    desc = "wikilink",
    fn = function() require("knapp.format").action("link")() end,
  },
  {
    plug = "Highlight",
    modes = { "n", "x" },
    suffix = "h",
    desc = "highlight",
    fn = function() require("knapp.format").action("highlight")() end,
  },

  {
    plug = "Rename",
    modes = "n",
    suffix = "r",
    desc = "rename note",
    fn = function() require("knapp.actions").rename() end,
  },
  {
    plug = "Move",
    modes = "n",
    suffix = "m",
    desc = "move note",
    fn = function() require("knapp.actions").move() end,
  },
  {
    plug = "Merge",
    modes = "n",
    suffix = "M",
    desc = "merge note",
    fn = function() require("knapp.actions").merge() end,
  },
  {
    plug = "BacklinksPane",
    modes = "n",
    suffix = "B",
    desc = "toggle backlinks pane",
    fn = function() require("knapp.pane").toggle() end,
  },
  {
    plug = "MissingLinks",
    modes = "n",
    suffix = "x",
    desc = "missing links in quickfix",
    fn = function() require("knapp.links").show_missing() end,
  },
  {
    plug = "BacklinksQf",
    modes = "n",
    suffix = "Q",
    desc = "backlinks in quickfix",
    fn = function() require("knapp.actions").backlinks() end,
  },
  {
    plug = "NewNote",
    modes = "n",
    suffix = "n",
    desc = "new note",
    fn = function() require("knapp.palette").new_note() end,
  },
  {
    plug = "FindNotes",
    modes = "n",
    suffix = "f",
    desc = "find notes",
    fn = function() require("knapp.palette").find_notes() end,
  },
  {
    plug = "GrepVault",
    modes = "n",
    suffix = "g",
    desc = "grep vault",
    fn = function() require("knapp.palette").grep_vault() end,
  },
  {
    plug = "Reindex",
    modes = "n",
    suffix = "R",
    desc = "rebuild index",
    fn = function() require("knapp.actions").reindex() end,
  },
  {
    plug = "ToggleWidth",
    modes = "n",
    suffix = "W",
    desc = "toggle readable width",
    fn = function() require("knapp.view").toggle() end,
  },
  {
    plug = "InsertTemplate",
    modes = "n",
    suffix = "t",
    desc = "insert template",
    fn = function() require("knapp.template").insert() end,
  },

  -- Insert-mode pairs. `<C-i>` is left out of this group: terminals send it as
  -- <Tab> unless the kitty keyboard protocol is active.
  {
    plug = "InsertBold",
    modes = "i",
    key = "<C-b>",
    desc = "bold",
    group = "insert",
    fn = function() require("knapp.format").insert_pair("**", "**") end,
  },
  {
    plug = "InsertLink",
    modes = "i",
    key = "<C-l>",
    desc = "wikilink",
    group = "insert",
    fn = function() require("knapp.format").insert_pair("[[", "]]") end,
  },
  {
    plug = "Bold",
    modes = "x",
    key = "<C-b>",
    desc = "bold",
    group = "insert",
    fn = function() require("knapp.format").action("bold")() end,
  },
  {
    plug = "Link",
    modes = "x",
    key = "<C-l>",
    desc = "wikilink",
    group = "insert",
    fn = function() require("knapp.format").action("link")() end,
  },

  {
    plug = "InsertItalic",
    modes = "i",
    key = "<C-i>",
    desc = "italics",
    group = "swap_ci",
    fn = function() require("knapp.format").insert_pair("*", "*") end,
  },
  {
    plug = "Italic",
    modes = "x",
    key = "<C-i>",
    desc = "italics",
    group = "swap_ci",
    fn = function() require("knapp.format").action("italic")() end,
  },
}

--- Actions bound everywhere, not only inside the vault: a journal note is
--- often opened from an unrelated buffer.
---@type knapp.Action[]
M.global = {
  {
    plug = "Daily",
    modes = "n",
    feature = "journal",
    suffix = "d",
    desc = "daily note",
    fn = function() require("knapp.journal").daily() end,
  },
  {
    plug = "Yesterday",
    modes = "n",
    feature = "journal",
    suffix = "y",
    desc = "yesterday's note",
    fn = function() require("knapp.journal").daily(-1) end,
  },
  {
    plug = "Weekly",
    modes = "n",
    feature = "journal",
    suffix = "w",
    desc = "weekly note",
    fn = function() require("knapp.journal").weekly() end,
  },
  {
    plug = "Zettel",
    modes = "n",
    feature = "journal",
    suffix = "z",
    desc = "new fleeting note",
    fn = function() require("knapp.journal").zettel() end,
  },
  {
    plug = "Calendar",
    modes = "n",
    feature = "calendar",
    suffix = "C",
    desc = "calendar",
    fn = function() require("knapp.calendar").open() end,
  },
}

local function plug_name(action) return ("<Plug>(Knapp%s)"):format(action.plug) end

--- An action's modes, always as a list.
---@param action knapp.Action
---@return string[]
local function modes_of(action)
  local modes = action.modes
  if type(modes) == "string" then return { modes } end
  return modes
end

--- The default left-hand side for an action, or nil when there is none.
local function default_lhs(action)
  local keys = config.opts.keys
  if action.palette then return keys.palette end
  if action.key then return action.key end
  if action.suffix then return keys.prefix .. action.suffix end
  return nil
end

--- Is this action switched off by its `keys.<group>` or `<feature>.enabled` flag?
local function disabled(action)
  if action.group ~= nil and not config.opts.keys[action.group] then return true end
  local feature = action.feature and config.opts[action.feature]
  return feature ~= nil and feature.enabled == false
end

--- Define every <Plug> mapping. Called once, from setup().
---
--- These exist even when `keys.enabled` is false, which is the point: turning
--- off the defaults should leave the actions bindable, not unreachable.
function M.define_plugs()
  local seen = {}
  for _, list in ipairs({ M.buffer, M.global }) do
    for _, action in ipairs(list) do
      -- the same <Plug> can appear for several modes; define each mode once
      for _, mode in ipairs(modes_of(action)) do
        local key = mode .. plug_name(action)
        if not seen[key] then
          seen[key] = true
          vim.keymap.set(mode, plug_name(action), action.fn, { desc = "knapp: " .. action.desc, silent = true })
        end
      end
    end
  end
end

--- Bind an action's default key, unless the user already bound its <Plug>.
local function bind(action, opts)
  local lhs = default_lhs(action)
  if not lhs or lhs == "" or lhs == false then return end
  for _, mode in ipairs(modes_of(action)) do
    -- hasmapto() is why <Plug> is worth the indirection: a user who wrote
    -- `vim.keymap.set("n", "<leader>x", "<Plug>(KnappRename)")` gets their
    -- binding and no surprise second one.
    if vim.fn.hasmapto(plug_name(action), mode) == 0 then
      -- no `remap = true` needed: <Plug> sequences are expanded even under
      -- `noremap`, which is the whole point of them being untypeable
      vim.keymap.set(
        mode,
        lhs,
        plug_name(action),
        { buffer = opts and opts.buf, desc = "knapp: " .. action.desc, silent = true }
      )
    end
  end
end

--- Bind the buffer-local defaults in `bufnr`.
function M.attach(bufnr)
  if not config.opts.keys.enabled then return end
  -- hasmapto() reads the *current* buffer's mappings, so ask from inside it
  vim.api.nvim_buf_call(bufnr, function()
    for _, action in ipairs(M.buffer) do
      if not disabled(action) then bind(action, { buf = bufnr }) end
    end
    if config.opts.keys.swap_ci then
      vim.keymap.set("n", "<C-k>", "<C-i>", { buffer = bufnr, desc = "knapp: jump forward", silent = true })
    end
  end)
end

--- Bind the global defaults. Called once, from setup().
function M.attach_global()
  if not config.opts.keys.enabled or not config.opts.keys.global then return end
  for _, action in ipairs(M.global) do
    if not disabled(action) then bind(action) end
  end
end

return M
