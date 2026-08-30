-- A blink.cmp source: `[[` completes note names from the vault, the way
-- Obsidian's own link autocomplete does.
--
-- Register it from your blink config:
--
--   sources = {
--     default = { "lsp", "path", "buffer", "knapp" },
--     providers = {
--       knapp = { name = "knapp", module = "knapp.blink" },
--     },
--   }
--
-- blink has no per-source keyword setting, and its default keyword stops at a
-- space, so `[[my no|` would only ever be matched against "no". The query is
-- therefore parsed out of the line here, and `filterText` carries the whole
-- name and path so blink's own fuzzy pass still finds the right notes.
local config = require("knapp.config")

---@class knapp.BlinkSource
---@field opts table
local source = {}

---@param opts table? from `sources.providers.knapp.opts`
function source.new(opts) return setmetatable({ opts = opts or {} }, { __index = source }) end

--- Only inside a vault note.
function source:enabled() return config.opts.vault ~= nil and config.in_vault(vim.api.nvim_buf_get_name(0)) end

function source:get_trigger_characters() return { "[" } end

--- The text between the nearest unclosed `[[` and the cursor.
---
--- Returns the query and the 0-based column the query starts at, or nil when
--- the cursor is not inside a wikilink.
---@param line string
---@param col integer 0-based cursor column
---@return string? query
---@return integer? start_col 0-based column at which the query begins
local function wikilink_query(line, col)
  local before = line:sub(1, col)
  local open = before:match(".*()%[%[")
  if not open then return nil end
  local query = before:sub(open + 2)
  -- `]]` between the brackets and the cursor means that link is already closed
  if query:find("]]", 1, true) then return nil end
  -- an alias or an anchor is not a note name; leave those alone
  if query:find("[|#]") then return nil end
  return query, open + 1
end

function source:get_completions(ctx, callback)
  local line = ctx.line
  local col = ctx.cursor[2]
  local query, start_col = wikilink_query(line, col)
  if not query then
    callback({ items = {}, is_incomplete_backward = false, is_incomplete_forward = false })
    return
  end

  local index = require("knapp.index")
  index.ensure()

  -- Obsidian closes the brackets for you; only add them when they are not
  -- already sitting after the cursor (`format.insert_pair` puts them there).
  local closing = line:sub(col + 1, col + 2) == "]]" and "" or "]]"
  local row = ctx.cursor[1] - 1

  -- vim.lsp.protocol rather than blink.cmp.types: the same enum, with no
  -- dependency on blink being loaded, which also keeps this testable.
  local kind = vim.lsp.protocol.CompletionItemKind.File
  local items = {}
  for _, note in ipairs(index.notes()) do
    -- A bare name is what Obsidian writes when it is unambiguous; the path is
    -- what disambiguates. Uniqueness is the test, not `resolve()`: with two
    -- notes named "dup", resolve() answers with whichever is closest to the
    -- link, so one of them would get a bare name that does not point back at
    -- it from anywhere else.
    local candidates = index.state.by_name[note.name:lower()]
    local unique = candidates ~= nil and #candidates == 1
    local target = unique and note.name or note.rel:sub(1, -4)
    items[#items + 1] = {
      label = note.name,
      kind = kind,
      detail = note.dir == "." and "" or note.dir,
      -- matched against blink's keyword, which stops at the last space, so
      -- include the path too and let the fuzzy pass do the rest
      filterText = note.name .. " " .. note.rel,
      textEdit = {
        newText = target .. closing,
        range = {
          start = { line = row, character = start_col },
          ["end"] = { line = row, character = col },
        },
      },
      insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
    }
  end

  -- Items are built fresh each call rather than cached and deep-copied: blink
  -- mutates what it is given, and a copy of the whole vault costs the same as
  -- building it.
  callback({
    items = items,
    is_incomplete_backward = true,
    is_incomplete_forward = true,
  })
end

--- Exposed for tests; not part of the blink API.
source._wikilink_query = wikilink_query

return source
