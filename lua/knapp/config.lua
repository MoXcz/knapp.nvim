local M = {}

M.defaults = {
  -- Vault root, required. Everything else is derived from
  -- <vault>/.obsidian/*.json, so Obsidian stays the source of truth.
  vault = nil,
  -- Directories skipped by the indexer (relative to vault root)
  ignore = { ".obsidian", ".trash", ".git", ".stfolder" },
  keys = {
    -- Bind the documented defaults. Turning this off leaves every action
    -- reachable as a <Plug> mapping; see :h knapp-keymaps.
    enabled = true,
    -- The journal keymaps below exist outside the vault too, since a daily
    -- note is usually opened from an unrelated buffer. Set false to keep
    -- knapp entirely inside the vault.
    global = true,
    prefix = "<leader>o",
    palette = "<C-p>",
    -- Insert-mode <C-b>/<C-l> for bold/link. <C-i> is left alone: terminals
    -- send it as <Tab> unless the kitty keyboard protocol is active.
    insert = true,
    -- Opt-in: <C-i> italics + <C-k> jumplist-forward. Needs kitty keyboard
    -- protocol, otherwise it breaks <Tab>.
    swap_ci = false,
  },
  -- Soft wrap, so nothing runs off the right edge. The file is never
  -- rewritten: `width` narrows the window and feeds 'textwidth' (gq/gw).
  wrap = {
    enabled = true,
    width = 120,
    -- narrow the note window to `width` with a padding window, so the soft
    -- wrap actually happens at that column instead of at the window edge
    pad = true,
    -- skip the padding when it would leave less than this much slack
    min_pad = 4,
    -- j/k walk display lines instead of jumping over a wrapped paragraph
    display_line_motions = true,
    -- Commands to fall through to when a window motion runs off the far side
    -- of the padding window. Ignored unless the command exists, so the
    -- vim-tmux-navigator defaults are inert without it.
    nav_commands = {
      h = "TmuxNavigateLeft",
      l = "TmuxNavigateRight",
      j = "TmuxNavigateDown",
      k = "TmuxNavigateUp",
    },
  },
  backlinks = {
    enabled = true,
    -- open the pane as soon as a note is opened
    auto = true,
    -- "bottom" | "top" | "left" | "right"
    position = "right",
    width = 40, -- used by "left"/"right"
    height = 10, -- used by "top"/"bottom"
  },
  journal = {
    -- Fleeting notes are named "<timestamp><separator><title>".
    zettel_separator = " - ",
  },
  links = {
    -- Highlight links by whether their target exists, so a link that points
    -- nowhere is visible without following it.
    enabled = true,
    -- Repaint at most this often while typing, in milliseconds.
    debounce = 150,
  },
  -- The padding and backlinks windows hold scratch buffers. 'sessionoptions'
  -- ships with "blank", which stores them in sessions, so :mksession and
  -- :restart come back with stray empty windows. Drop "blank" to avoid it.
  --
  -- This edits a global option, which a plugin should not do lightly. There is
  -- no alternative: Nvim has no pre-session autocommand (only SessionLoadPost),
  -- and :restart runs :mksession before quitting, so closing the windows on
  -- VimLeavePre -- which knapp also does -- happens too late. Set false to
  -- keep 'sessionoptions' untouched and live with the stray windows.
  fix_sessionoptions = true,
  cache = vim.fs.joinpath(vim.fn.stdpath("cache"), "knapp"),
}

M.opts = vim.deepcopy(M.defaults)

local function is(kind)
  return function(v) return type(v) == kind end
end
local function positive(v) return type(v) == "number" and v > 0 end

--- One schema, used by setup() to fall back to defaults and by health to list
--- everything wrong at once. Keeping two copies in step by hand is exactly the
--- kind of drift this project has already been bitten by.
--- Named separately: inside a tuple alias, `fun(v: any): boolean, string`
--- parses as a function returning two values rather than as two elements.
---@alias knapp.ConfigCheck fun(v: any): boolean

--- A field path, a predicate, and how to describe what was expected.
---@alias knapp.ConfigRule [string, knapp.ConfigCheck, string]

---@type knapp.ConfigRule[]
M.schema = {
  { "ignore", function(v) return vim.islist(v) end, "a list of directory names" },
  { "cache", is("string"), "a string" },
  { "fix_sessionoptions", is("boolean"), "a boolean" },

  { "keys.enabled", is("boolean"), "a boolean" },
  { "keys.global", is("boolean"), "a boolean" },
  { "keys.prefix", is("string"), "a string" },
  { "keys.insert", is("boolean"), "a boolean" },
  { "keys.swap_ci", is("boolean"), "a boolean" },

  { "wrap.enabled", is("boolean"), "a boolean" },
  { "wrap.width", positive, "a positive number" },
  { "wrap.pad", is("boolean"), "a boolean" },
  { "wrap.min_pad", function(v) return type(v) == "number" and v >= 0 end, "a non-negative number" },
  { "wrap.display_line_motions", is("boolean"), "a boolean" },
  { "wrap.nav_commands", is("table"), "a table of direction -> command name" },

  { "backlinks.enabled", is("boolean"), "a boolean" },
  { "backlinks.auto", is("boolean"), "a boolean" },
  {
    "backlinks.position",
    function(v) return vim.tbl_contains({ "top", "bottom", "left", "right" }, v) end,
    '"top", "bottom", "left" or "right"',
  },
  { "backlinks.width", positive, "a positive number" },
  { "backlinks.height", positive, "a positive number" },

  { "journal.zettel_separator", is("string"), "a string" },

  { "links.enabled", is("boolean"), "a boolean" },
  { "links.debounce", positive, "a positive number" },
}

--- Read a dotted path out of a table.
local function get(tbl, path)
  local value = tbl
  for key in path:gmatch("[^.]+") do
    if type(value) ~= "table" then return nil end
    value = value[key]
  end
  return value
end

--- Write a dotted path into a table.
local function set(tbl, path, new)
  local keys = vim.split(path, ".", { plain = true })
  local node = tbl
  for i = 1, #keys - 1 do
    node = node[keys[i]]
    if type(node) ~= "table" then return end
  end
  node[keys[#keys]] = new
end

--- Check `opts` against |knapp.config.schema|.
---@param opts table merged options
---@return string[] problems one line per invalid field, empty when all is well
function M.validate(opts)
  local problems = {}
  for _, rule in ipairs(M.schema) do
    local path, ok_fn, expected = rule[1], rule[2], rule[3]
    local value = get(opts, path)
    if not ok_fn(value) then
      problems[#problems + 1] = ("%s = %s (expected %s)"):format(path, vim.inspect(value), expected)
    end
  end
  return problems
end

--- Unknown keys in `opts`, as dotted paths. `tbl_deep_extend` keeps them
--- silently, so a typo would otherwise just never take effect.
---@return string[]
function M.unknown_keys(opts)
  local out = {}
  local function walk(user, default, prefix)
    if type(user) ~= "table" or type(default) ~= "table" then return end
    for key, value in pairs(user) do
      local path = prefix == "" and tostring(key) or (prefix .. "." .. tostring(key))
      -- `vault` has no default, so it cannot be found by walking the defaults
      if default[key] == nil and not (prefix == "" and key == "vault") then
        out[#out + 1] = path
      else
        walk(value, default[key], path)
      end
    end
  end
  walk(opts, M.defaults, "")
  return out
end

function M.setup(opts)
  -- tbl_deep_extend does not mutate its first argument, so the defaults do not
  -- need copying before being merged over.
  M.opts = vim.tbl_deep_extend("force", M.defaults, opts or {})
  if not M.opts.vault or M.opts.vault == "" then
    error("knapp.nvim: `vault` is required, e.g. require('knapp').setup({ vault = '~/notes' })")
  end

  -- A bad value would otherwise surface much later and far from its cause --
  -- `wrap.width = "120"` fails inside nvim_win_set_width. Report every problem
  -- at once and fall back to the default for each, so one typo in a config
  -- does not take the whole plugin down. :checkhealth repeats the detail.
  local problems = M.validate(M.opts)
  if #problems > 0 then
    for _, path in ipairs(problems) do
      set(M.opts, path:match("^[^ ]+"), get(M.defaults, path:match("^[^ ]+")))
    end
    vim.notify(
      "knapp.nvim: ignoring invalid options, using defaults instead:\n  " .. table.concat(problems, "\n  "),
      vim.log.levels.ERROR,
      { title = "knapp" }
    )
  end

  M.opts.vault = vim.fs.normalize(vim.fn.expand(M.opts.vault))
  if vim.fn.isdirectory(M.opts.vault) == 0 then
    vim.notify(("knapp.nvim: vault %s does not exist"):format(M.opts.vault), vim.log.levels.WARN)
  end
  return M.opts
end

--- Is `path` inside the vault?
function M.in_vault(path)
  if not path or path == "" then return false end
  path = vim.fs.normalize(path)
  return path == M.opts.vault or vim.startswith(path, M.opts.vault .. "/")
end

--- Absolute path -> vault-relative path
function M.rel(path)
  path = vim.fs.normalize(path)
  if path == M.opts.vault then return "" end
  return (path:sub(#M.opts.vault + 2))
end

--- Vault-relative path -> absolute path
function M.abs(rel) return vim.fs.joinpath(M.opts.vault, rel) end

return M
