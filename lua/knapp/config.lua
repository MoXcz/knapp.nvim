local M = {}

M.defaults = {
  -- Vault root, required. Everything else is derived from
  -- <vault>/.obsidian/*.json, so Obsidian stays the source of truth.
  vault = nil,
  -- Directories skipped by the indexer (relative to vault root)
  ignore = { ".obsidian", ".trash", ".git", ".stfolder" },
  keys = {
    enabled = true,
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
  },
  backlinks = {
    -- open the pane as soon as a note is opened
    auto = true,
    -- "bottom" | "top" | "left" | "right"
    position = "right",
    width = 40, -- used by "left"/"right"
    height = 10, -- used by "top"/"bottom"
  },
  -- The padding and backlinks windows hold scratch buffers. 'sessionoptions'
  -- ships with "blank", which stores them in sessions, so :mksession and
  -- :restart come back with stray empty windows. Drop "blank" to avoid it.
  fix_sessionoptions = true,
  cache = vim.fs.joinpath(vim.fn.stdpath("cache"), "knapp"),
}

M.opts = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  if not M.opts.vault or M.opts.vault == "" then
    error("knapp.nvim: `vault` is required, e.g. require('knapp').setup({ vault = '~/notes' })")
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
