local helpers = require("helpers")
local keys = require("knapp.keys")

--- Does a mapping for `lhs` exist in `mode`, buffer-locally or globally?
---
--- `lhs` is given in Vim notation. <Plug> names survive verbatim in the keymap
--- list while <leader> and <C-x> are stored translated, so both forms are
--- compared rather than picking one and being wrong half the time.
local function mapped(mode, lhs, bufnr)
  local want = vim.api.nvim_replace_termcodes(lhs, true, true, true)
  local maps = bufnr and vim.api.nvim_buf_get_keymap(bufnr, mode) or vim.api.nvim_get_keymap(mode)
  for _, m in ipairs(maps) do
    if m.lhs == lhs or m.lhs == want or vim.api.nvim_replace_termcodes(m.lhs, true, true, true) == want then
      return true
    end
  end
  return false
end

--- Open a note and fire FileType, which is what attaches the buffer-local
--- keymaps. The filetype is set by hand rather than relying on detection,
--- which is not necessarily enabled in a headless test run.
local function open_note(vault, rel)
  vim.cmd.edit(vim.fs.joinpath(vault, rel))
  vim.bo.filetype = "markdown"
  return vim.api.nvim_get_current_buf()
end

describe("<Plug> mappings", function()
  after_each(helpers.cleanup)

  it("are defined for every action", function()
    helpers.setup({ ["a.md"] = "" }, nil, { keys = { enabled = true } })
    for _, list in ipairs({ keys.buffer, keys.global }) do
      for _, action in ipairs(list) do
        local modes = type(action.modes) == "table" and action.modes or { action.modes }
        for _, mode in ipairs(modes) do
          local plug = ("<Plug>(Knapp%s)"):format(action.plug)
          assert.is_true(mapped(mode, plug), plug .. " missing in mode " .. mode)
        end
      end
    end
  end)

  it("exist even when default bindings are turned off", function()
    helpers.setup({ ["a.md"] = "" }, nil, { keys = { enabled = false } })
    assert.is_true(mapped("n", "<Plug>(KnappRename)"))
    assert.is_true(mapped("n", "<Plug>(KnappDaily)"))
  end)
end)

describe("default keymaps", function()
  after_each(helpers.cleanup)

  it("are bound buffer-locally inside the vault", function()
    local vault = helpers.setup({ ["a.md"] = "" }, nil, { keys = { enabled = true } })
    local buf = open_note(vault, "a.md")
    assert.is_true(mapped("n", "gf", buf))
    assert.is_true(mapped("n", "<C-P>", buf))
  end)

  it("are not bound at all when keys.enabled is false", function()
    local vault = helpers.setup({ ["a.md"] = "" }, nil, { keys = { enabled = false } })
    local buf = open_note(vault, "a.md")
    assert.is_false(mapped("n", "gf", buf))
  end)

  it("follow keys.prefix", function()
    local vault = helpers.setup({ ["a.md"] = "" }, nil, { keys = { enabled = true, prefix = "<leader>z" } })
    local buf = open_note(vault, "a.md")
    assert.is_true(mapped("n", "<Space>zr", buf))
  end)

  it("skip an action the user has already bound to its <Plug>", function()
    helpers.setup({ ["a.md"] = "" }, nil, { keys = { enabled = false } })
    -- the user's own binding, made before knapp attaches the buffer
    vim.keymap.set("n", "<leader>rn", "<Plug>(KnappRename)", { desc = "knapp: user rename" })

    local vault = require("knapp.config").opts.vault
    require("knapp.config").opts.keys.enabled = true
    local buf = open_note(vault, "a.md")

    assert.is_false(mapped("n", "<Space>or", buf), "default should have stepped aside for the user's binding")
    -- an action the user did not bind still gets its default
    assert.is_true(mapped("n", "<Space>om", buf))
  end)
end)

describe("keys.global", function()
  after_each(helpers.cleanup)

  it("binds the journal keys outside the vault by default", function()
    helpers.setup({ ["a.md"] = "" }, nil, { keys = { enabled = true } })
    assert.is_true(mapped("n", "<Space>od"))
    assert.is_true(mapped("n", "<Space>oC"))
  end)

  it("binds none of them when false", function()
    helpers.setup({ ["a.md"] = "" }, nil, { keys = { enabled = true, global = false } })
    assert.is_false(mapped("n", "<Space>od"))
    assert.is_false(mapped("n", "<Space>oC"))
    -- still reachable
    assert.is_true(mapped("n", "<Plug>(KnappDaily)"))
  end)
end)

describe("keys.insert and keys.swap_ci", function()
  after_each(helpers.cleanup)

  it("binds the insert-mode pairs by default", function()
    local vault = helpers.setup({ ["a.md"] = "" }, nil, { keys = { enabled = true } })
    local buf = open_note(vault, "a.md")
    assert.is_true(mapped("i", "<C-B>", buf))
    assert.is_true(mapped("i", "<C-L>", buf))
  end)

  it("omits them when keys.insert is false", function()
    local vault = helpers.setup({ ["a.md"] = "" }, nil, { keys = { enabled = true, insert = false } })
    local buf = open_note(vault, "a.md")
    assert.is_false(mapped("i", "<C-B>", buf))
  end)

  it("leaves <C-i> alone unless swap_ci is set", function()
    local vault = helpers.setup({ ["a.md"] = "" }, nil, { keys = { enabled = true } })
    assert.is_false(mapped("i", "<Tab>", open_note(vault, "a.md")))
  end)

  it("binds <C-i> and <C-k> when swap_ci is set", function()
    local vault = helpers.setup({ ["a.md"] = "" }, nil, { keys = { enabled = true, swap_ci = true } })
    local buf = open_note(vault, "a.md")
    assert.is_true(mapped("i", "<Tab>", buf)) -- terminals send <C-i> as <Tab>
    assert.is_true(mapped("n", "<C-K>", buf))
  end)
end)

describe("feature toggles", function()
  after_each(helpers.cleanup)

  it("backlinks.enabled = false leaves the pane closed on note open", function()
    local vault = helpers.setup({ ["a.md"] = "[[b]]", ["b.md"] = "" }, nil, {
      backlinks = { enabled = false, auto = true },
    })
    vim.cmd.edit(vim.fs.joinpath(vault, "b.md"))
    vim.bo.filetype = "markdown"
    vim.cmd("doautocmd BufEnter")
    vim.wait(80)
    assert.is_false(require("knapp.pane").is_open())
  end)

  it("journal.zettel_separator names fleeting notes", function()
    local vault = helpers.setup({}, { ["zk-prefixer.json"] = { format = "YYYY" } }, {
      journal = { zettel_separator = "__" },
    })
    local original = vim.ui.input
    vim.ui.input = function(_, cb) cb("an idea") end
    require("knapp.journal").zettel()
    vim.ui.input = original
    local year = os.date("%Y")
    assert.is_true(helpers.exists(vault, ("%s__an idea.md"):format(year)))
  end)
end)
