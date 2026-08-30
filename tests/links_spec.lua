local helpers = require("helpers")
local links = require("knapp.links")

local ns = vim.api.nvim_get_namespaces()["knapp_links"]

--- Highlight group applied at each link, in buffer order.
local function marks(bufnr)
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })) do
    out[#out + 1] = { row = m[2], col = m[3], hl = m[4].hl_group }
  end
  return out
end

local function open(vault, rel)
  vim.cmd.edit(vim.fs.joinpath(vault, rel))
  local bufnr = vim.api.nvim_get_current_buf()
  links.refresh(bufnr)
  return bufnr
end

describe("links.refresh", function()
  after_each(helpers.cleanup)

  it("marks a link whose target exists", function()
    local vault = helpers.setup({ ["a.md"] = "see [[b]]\n", ["b.md"] = "" })
    local m = marks(open(vault, "a.md"))
    assert.equals(1, #m)
    assert.equals("KnappLink", m[1].hl)
  end)

  it("marks a link whose target does not exist", function()
    local vault = helpers.setup({ ["a.md"] = "see [[nowhere]]\n" })
    local m = marks(open(vault, "a.md"))
    assert.equals(1, #m)
    assert.equals("KnappLinkMissing", m[1].hl)
  end)

  it("distinguishes several links on one line", function()
    local vault = helpers.setup({ ["a.md"] = "[[b]] and [[gone]]\n", ["b.md"] = "" })
    assert.same(
      { "KnappLink", "KnappLinkMissing" },
      vim.tbl_map(function(x) return x.hl end, marks(open(vault, "a.md")))
    )
  end)

  it("covers exactly the link text", function()
    local vault = helpers.setup({ ["a.md"] = "xx [[b]] yy\n", ["b.md"] = "" })
    local bufnr = open(vault, "a.md")
    local m = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })[1]
    assert.equals(3, m[3])
    assert.equals(8, m[4].end_col)
  end)

  it("follows an alias to a real note", function()
    local vault = helpers.setup({
      ["a.md"] = "[[Nickname]]\n",
      ["b.md"] = "---\naliases: [Nickname]\n---\n",
    })
    assert.equals("KnappLink", marks(open(vault, "a.md"))[1].hl)
  end)

  it("resolves an attachment that the note index does not track", function()
    local vault = helpers.setup({ ["a.md"] = "![[pic.png]]\n" })
    helpers.write(vim.fs.joinpath(vault, "pic.png"), "not really a png")
    assert.equals("KnappLink", marks(open(vault, "a.md"))[1].hl)
  end)

  it("ignores links inside fenced code blocks", function()
    local vault = helpers.setup({ ["a.md"] = "```\n[[gone]]\n```\n" })
    assert.same({}, marks(open(vault, "a.md")))
  end)

  it("repaints after the target is created", function()
    local vault = helpers.setup({ ["a.md"] = "[[later]]\n" })
    local bufnr = open(vault, "a.md")
    assert.equals("KnappLinkMissing", marks(bufnr)[1].hl)
    helpers.write(vim.fs.joinpath(vault, "later.md"), "")
    require("knapp.index").update("later.md")
    links.refresh(bufnr)
    assert.equals("KnappLink", marks(bufnr)[1].hl)
  end)

  it("does nothing when disabled", function()
    local vault = helpers.setup({ ["a.md"] = "[[gone]]\n" }, nil, { links = { enabled = false } })
    assert.same({}, marks(open(vault, "a.md")))
  end)

  it("does nothing outside the vault", function()
    helpers.setup({ ["a.md"] = "" })
    local outside = vim.fs.joinpath(helpers.tmpdir("outside"), "n.md")
    helpers.write(outside, "[[gone]]\n")
    vim.cmd.edit(outside)
    local bufnr = vim.api.nvim_get_current_buf()
    links.refresh(bufnr)
    assert.same({}, marks(bufnr))
  end)
end)

describe("links.missing", function()
  after_each(helpers.cleanup)

  it("lists only the links that point nowhere", function()
    local vault = helpers.setup({ ["a.md"] = "[[b]]\nplain\n[[gone]] and [[b]]\n", ["b.md"] = "" })
    local bufnr = open(vault, "a.md")
    local items = links.missing(bufnr)
    assert.equals(1, #items)
    assert.equals(3, items[1].lnum)
    assert.matches("missing: gone", items[1].text)
  end)

  it("is empty when every link resolves", function()
    local vault = helpers.setup({ ["a.md"] = "[[b]]\n", ["b.md"] = "" })
    assert.same({}, links.missing(open(vault, "a.md")))
  end)
end)
