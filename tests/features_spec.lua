-- journal.enabled / calendar.enabled: switching a feature off removes its
-- subcommand, its palette entries and its global keymaps.
local helpers = require("helpers")

--- Names the palette would offer, captured through vim.ui.select.
local function palette_names()
  local saved = vim.ui.select
  local names
  vim.ui.select = function(items) names = items end
  require("knapp.palette").open()
  vim.ui.select = saved
  return names
end

describe("feature flags", function()
  after_each(helpers.cleanup)

  it("everything is on by default", function()
    helpers.setup({ ["a.md"] = "" })
    local names = table.concat(palette_names(), "\n")
    assert.truthy(names:find("Open today's daily note", 1, true))
    assert.truthy(names:find("Open calendar", 1, true))
  end)

  it("journal.enabled = false refuses the subcommand instead of creating a note", function()
    local vault = helpers.setup({ ["a.md"] = "" }, nil, { journal = { enabled = false } })
    helpers.notifications()
    vim.cmd("Knapp daily")
    local msgs = helpers.notifications()
    assert.equals(1, #msgs)
    assert.truthy(msgs[1].msg:find("journal.enabled", 1, true))
    -- no daily note was created anywhere in the vault
    for name in vim.fs.dir(vault, { depth = 10 }) do
      assert.truthy(name == "a.md" or name:find("^%.obsidian"), "unexpected file: " .. name)
    end
  end)

  it("calendar.enabled = false hides the palette entry, journal entries stay", function()
    helpers.setup({ ["a.md"] = "" }, nil, { calendar = { enabled = false } })
    local names = table.concat(palette_names(), "\n")
    assert.is_nil(names:find("Open calendar", 1, true))
    assert.truthy(names:find("Open today's daily note", 1, true))
  end)

  it("journal.enabled = false skips the global journal keymaps", function()
    helpers.setup({ ["a.md"] = "" }, nil, {
      keys = { enabled = true },
      journal = { enabled = false },
    })
    require("knapp.keys").attach_global()
    local found = {}
    for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
      -- <Plug> mappings stay defined for every action by design; only the
      -- bound default keys are gated by the feature flag
      if type(m.desc) == "string" and m.desc:match("^knapp:") and not m.lhs:find("<Plug>", 1, true) then
        found[#found + 1] = m.desc
      end
    end
    local descs = table.concat(found, "\n")
    assert.is_nil(descs:find("daily note", 1, true))
    assert.is_nil(descs:find("weekly note", 1, true))
    -- the calendar map is a different feature and must survive
    assert.truthy(descs:find("calendar", 1, true))
  end)
end)
