-- Highlight links by whether their target exists.
--
-- Obsidian dims a link that points nowhere; this does the same with extmarks,
-- so a typo in a note name is visible at a glance instead of at `gf` time.
local config = require("knapp.config")
local index = require("knapp.index")
local link = require("knapp.link")
local util = require("knapp.util")

local M = {}

local ns = vim.api.nvim_create_namespace("knapp_links")

-- resolve_file() falls back to uv.fs_stat for anything the index cannot
-- resolve -- attachments, and every missing link, at two stats each. A note
-- with many of those pays that on every debounced repaint while typing.
-- Memoized per (source, target); dropped whenever `index.generation` moves,
-- which is whenever what resolves can change. The generation check is
-- synchronous where the `KnappIndexChanged` autocmd is scheduled, so a
-- refresh right after an index update never reads a stale cache.
--
-- Only positive answers are cached: a missing target can start existing at
-- any moment without the generation moving (an attachment written from Nvim
-- bumps nothing, since only *.md writes update the index), and a cached
-- "missing" would keep the link dimmed indefinitely. Re-stating the few
-- genuinely missing targets per repaint is cheap; re-resolving every good
-- link was the cost worth saving.
local resolved, resolved_gen = {}, -1

local function target_exists(target, from)
  if resolved_gen ~= index.generation then
    resolved, resolved_gen = {}, index.generation
  end
  local key = from .. "\0" .. target
  if resolved[key] then return true end
  local hit = index.resolve_file(target, from) ~= nil
  if hit then resolved[key] = true end
  return hit
end

local function hl_setup()
  -- `default = true` so a colorscheme that defines these wins
  vim.api.nvim_set_hl(0, "KnappLink", { link = "@markup.link.label.markdown_inline", default = true })
  vim.api.nvim_set_hl(0, "KnappLinkMissing", { link = "DiagnosticUnnecessary", default = true })
end

--- Repaint `bufnr`.
---
--- The whole buffer is scanned rather than only the visible lines: a note is
--- small, this is debounced, and a decoration provider would have to re-resolve
--- every link on every redraw instead of once per edit.
---@param bufnr integer
function M.refresh(bufnr)
  if not config.opts.links.enabled then return end
  if not vim.api.nvim_buf_is_loaded(bufnr) then return end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if not config.in_vault(name) or not util.is_md(name) then return end

  -- while the cold build runs in the background, resolving would drain it
  -- synchronously; the KnappIndexChanged repaint covers this buffer once the
  -- build lands
  if not index.try_ensure() then return end
  local from = config.rel(name)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = table.concat(lines, "\n")

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  for _, m in ipairs(link.scan_lines(text)) do
    -- embeds and attachments resolve to files the index does not track, so ask
    -- the same resolver `gf` uses rather than the note index alone. An
    -- anchor-only [[#heading]] has no target and points at this note itself;
    -- without the guard it would "exist" only because resolve_file("") stats
    -- the vault root.
    local exists = m.target == "" or target_exists(m.target, from)
    local line = lines[m.lnum] or ""
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, m.lnum - 1, m.col - 1, {
      end_row = m.lnum - 1,
      end_col = math.min(m.col - 1 + (m.e - m.s + 1), #line),
      hl_group = exists and "KnappLink" or "KnappLinkMissing",
      priority = 200,
    })
  end
end

--- Every link in the current note that points nowhere, as quickfix items.
---@return table[]
function M.missing(bufnr)
  bufnr = bufnr or 0
  local name = vim.api.nvim_buf_get_name(bufnr)
  if not config.in_vault(name) or not util.is_md(name) then return {} end
  index.ensure()
  local from = config.rel(name)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local out = {}
  for _, m in ipairs(link.scan_lines(table.concat(lines, "\n"))) do
    -- anchor-only [[#heading]] points at this note itself; never missing
    if m.target ~= "" and not target_exists(m.target, from) then
      out[#out + 1] = {
        filename = name,
        lnum = m.lnum,
        col = m.col,
        text = ("missing: %s"):format(m.target),
      }
    end
  end
  return out
end

--- Put every link in this note that points nowhere in the quickfix list.
function M.show_missing()
  local items = M.missing(0)
  if #items == 0 then
    vim.notify("no missing links in this note", vim.log.levels.INFO, { title = "knapp" })
    return
  end
  vim.fn.setqflist({}, " ", { title = "knapp: missing links", items = items })
  vim.cmd.copen()
end

--- Install the autocommands that keep the highlights current.
---@param group integer augroup id
function M.setup(group)
  if not config.opts.links.enabled then return end
  hl_setup()

  local pending = {}
  local refresh = util.debounce(config.opts.links.debounce, function()
    local bufs = pending
    pending = {}
    for bufnr in pairs(bufs) do
      M.refresh(bufnr)
    end
  end)

  local function queue(ev)
    pending[ev.buf] = true
    refresh()
  end

  -- TextChanged covers edits; BufWritePost covers a link that started
  -- resolving because the note it points at was just created elsewhere.
  vim.api.nvim_create_autocmd({ "BufWinEnter", "TextChanged", "TextChangedI", "InsertLeave" }, {
    group = group,
    pattern = util.md_patterns,
    callback = queue,
  })

  -- A note created or renamed anywhere changes what resolves in every open
  -- note, so repaint them all rather than just the current one.
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "KnappIndexChanged",
    callback = function()
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then pending[bufnr] = true end
      end
      refresh()
    end,
  })

  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = hl_setup })
end

return M
