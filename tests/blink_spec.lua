local helpers = require("helpers")
local blink = require("knapp.blink")

local q = blink._wikilink_query

describe("blink source: wikilink query", function()
  it("finds the text between [[ and the cursor", function()
    local query, col = q("see [[my no", 11)
    assert.equals("my no", query)
    assert.equals(6, col) -- 0-based column of "m", the first character of the query
  end)

  it("handles an empty query right after the brackets", function() assert.equals("", (q("see [[", 6))) end)

  it("takes the nearest opening brackets", function() assert.equals("second", (q("[[first]] and [[second", 22))) end)

  it("returns nil outside a link", function()
    assert.is_nil(q("no brackets here", 8))
    assert.is_nil(q("[[closed]] after", 16))
  end)

  it("returns nil once the cursor is past the closing brackets", function() assert.is_nil(q("[[done]]", 8)) end)

  it("leaves an alias or an anchor alone", function()
    assert.is_nil(q("[[note|al", 9))
    assert.is_nil(q("[[note#hea", 10))
  end)

  it("ignores brackets after the cursor", function() assert.equals("ab", (q("[[ab]]", 4))) end)
end)

describe("blink source: completions", function()
  after_each(helpers.cleanup)

  --- Drive get_completions synchronously.
  local function complete(line, col, row)
    local src = blink.new({})
    local got
    src:get_completions({ line = line, cursor = { row or 1, col }, bufnr = 0 }, function(r) got = r end)
    return got.items
  end

  local function labels(items)
    local out = vim.tbl_map(function(i) return i.label end, items)
    table.sort(out)
    return out
  end

  it("offers every note in the vault", function()
    helpers.setup({ ["one.md"] = "", ["folder/two.md"] = "" })
    assert.same({ "one", "two" }, labels(complete("[[", 2)))
  end)

  it("offers nothing outside a wikilink", function()
    helpers.setup({ ["one.md"] = "" })
    assert.same({}, complete("plain text", 5))
  end)

  it("replaces from after the brackets to the cursor", function()
    helpers.setup({ ["one.md"] = "" })
    local edit = complete("see [[on", 8)[1].textEdit
    assert.equals("one]]", edit.newText)
    assert.equals(6, edit.range.start.character)
    assert.equals(8, edit.range["end"].character)
  end)

  it("does not add a second pair of closing brackets", function()
    helpers.setup({ ["one.md"] = "" })
    assert.equals("one", complete("[[on]]", 4)[1].textEdit.newText)
  end)

  it("inserts a bare name when it is unambiguous", function()
    helpers.setup({ ["folder/one.md"] = "" })
    assert.equals("one]]", complete("[[", 2)[1].textEdit.newText)
  end)

  it("inserts a path when the bare name would be ambiguous", function()
    helpers.setup({ ["a/dup.md"] = "", ["b/dup.md"] = "" })
    local inserted = vim.tbl_map(function(i) return i.textEdit.newText end, complete("[[", 2))
    table.sort(inserted)
    assert.same({ "a/dup]]", "b/dup]]" }, inserted)
  end)

  it("matches on the path as well as the name", function()
    helpers.setup({ ["folder/one.md"] = "" })
    assert.matches("folder/one%.md", complete("[[", 2)[1].filterText)
  end)

  it("reports the folder as detail", function()
    helpers.setup({ ["folder/one.md"] = "", ["root.md"] = "" })
    local by_label = {}
    for _, item in ipairs(complete("[[", 2)) do
      by_label[item.label] = item.detail
    end
    assert.equals("folder", by_label.one)
    assert.equals("", by_label.root)
  end)
end)

describe("blink source: enabled", function()
  after_each(helpers.cleanup)

  it("is on inside a vault note", function()
    local vault = helpers.setup({ ["a.md"] = "" })
    vim.cmd.edit(vim.fs.joinpath(vault, "a.md"))
    assert.is_true(blink.new({}):enabled())
  end)

  it("is off outside the vault", function()
    helpers.setup({ ["a.md"] = "" })
    vim.cmd.edit(vim.fs.joinpath(helpers.tmpdir("outside"), "n.md"))
    assert.is_false(blink.new({}):enabled())
  end)
end)
