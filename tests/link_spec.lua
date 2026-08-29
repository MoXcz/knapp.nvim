local link = require("knapp.link")

describe("link.scan", function()
  local function targets(text)
    return vim.tbl_map(function(m) return m.target end, link.scan(text))
  end

  it("finds a bare wikilink", function() assert.same({ "note" }, targets("see [[note]] here")) end)

  it("splits an alias", function()
    local m = link.scan("[[note|the alias]]")[1]
    assert.equals("note", m.target)
    assert.equals("the alias", m.alias)
  end)

  it("splits a heading anchor", function()
    local m = link.scan("[[note#Some Heading]]")[1]
    assert.equals("note", m.target)
    assert.equals("#Some Heading", m.anchor)
  end)

  it("splits a block anchor", function()
    local m = link.scan("[[note#^block-id]]")[1]
    assert.equals("note", m.target)
    assert.equals("#^block-id", m.anchor)
  end)

  it("splits an anchor and an alias together", function()
    local m = link.scan("[[note#Heading|shown]]")[1]
    assert.equals("note", m.target)
    assert.equals("#Heading", m.anchor)
    assert.equals("shown", m.alias)
  end)

  it("marks embeds", function()
    assert.is_true(link.scan("![[image.png]]")[1].embed)
    assert.is_false(link.scan("[[image.png]]")[1].embed)
  end)

  it("finds markdown links and decodes them", function()
    local m = link.scan("[label](note%20name.md)")[1]
    assert.equals("md", m.kind)
    assert.equals("note name.md", m.target)
    assert.equals("label", m.text)
  end)

  it("strips a markdown link title", function() assert.same({ "note.md" }, targets('[label](note.md "a title")')) end)

  it(
    "ignores external markdown links",
    function() assert.same({}, targets("[site](https://example.com) [anchor](#local)")) end
  )

  it("keeps byte offsets pointing at the source text", function()
    local text = "xx [[note]] yy"
    local m = link.scan(text)[1]
    assert.equals("[[note]]", text:sub(m.s, m.e))
  end)

  it("returns matches sorted by position", function()
    local ms = link.scan("[a](a.md) then [[b]] then [c](c.md)")
    assert.same({ "a.md", "b", "c.md" }, vim.tbl_map(function(m) return m.target end, ms))
  end)

  it(
    "does not report a wikilink twice as a markdown link",
    function() assert.same({ "note" }, targets("![[note]]")) end
  )
end)

describe("link.scan code masking", function()
  local function targets(text)
    return vim.tbl_map(function(m) return m.target end, link.scan(text))
  end

  it(
    "ignores links inside a backtick fence",
    function() assert.same({ "real" }, targets("[[real]]\n```lua\n[[fake]]\n```\n")) end
  )

  it(
    "ignores links inside a tilde fence",
    function() assert.same({ "real" }, targets("[[real]]\n~~~\n[[fake]]\n~~~\n")) end
  )

  it(
    "ignores links inside an inline code span",
    function() assert.same({ "real" }, targets("`[[fake]]` and [[real]]")) end
  )

  it(
    "does not let a longer fence be closed by a shorter one",
    function() assert.same({}, targets("````\n[[fake]]\n```\nstill fenced [[also fake]]\n````\n")) end
  )

  it("resumes after a fence closes", function() assert.same({ "after" }, targets("```\n[[fake]]\n```\n[[after]]")) end)

  it("is unaffected by the no-code fast path", function() assert.same({ "a", "b" }, targets("[[a]] and [[b]]")) end)
end)

describe("link.scan_lines", function()
  local text = table.concat({
    "intro [[one]] here",
    "```lua",
    'local x = "[[fenced]]"',
    "```",
    "tail `[[inline]]` and [[two]]",
  }, "\n")

  it("skips fenced links that a per-line scan would find", function()
    assert.same({ "one", "two" }, vim.tbl_map(function(m) return m.target end, link.scan_lines(text)))
  end)

  it("reports 1-based line numbers", function()
    assert.same({ 1, 5 }, vim.tbl_map(function(m) return m.lnum end, link.scan_lines(text)))
  end)

  it("reports 1-based byte columns within the line", function()
    local ms = link.scan_lines(text)
    local lines = vim.split(text, "\n", { plain = true })
    for _, m in ipairs(ms) do
      assert.equals("[[" .. m.target .. "]]", lines[m.lnum]:sub(m.col, m.col + #m.target + 3))
    end
  end)

  it("handles a single line with no newline", function()
    local m = link.scan_lines("x [[y]]")[1]
    assert.equals(1, m.lnum)
    assert.equals(3, m.col)
  end)

  it("handles consecutive newlines", function()
    local m = link.scan_lines("a\n\n\n[[z]]")[1]
    assert.equals(4, m.lnum)
    assert.equals(1, m.col)
  end)
end)

describe("link.at", function()
  local text = "one [[alpha]] two [[beta]]"

  it("finds the link containing the offset", function()
    assert.equals("alpha", link.at(text, 7).target)
    assert.equals("beta", link.at(text, 20).target)
  end)

  it("matches at both boundaries", function()
    assert.equals("alpha", link.at(text, 5).target)
    assert.equals("alpha", link.at(text, 13).target)
  end)

  it("returns nil between links", function() assert.is_nil(link.at(text, 15)) end)

  it("returns nil inside a fenced block", function()
    local fenced = "```\n[[fake]]\n```"
    assert.is_nil(link.at(fenced, 7))
  end)
end)

describe("link.render", function()
  it("round-trips a plain wikilink", function()
    local m = link.scan("[[note]]")[1]
    assert.equals("[[note]]", link.render(m, "note"))
  end)

  it("keeps the anchor and the alias", function()
    local m = link.scan("[[note#Head|shown]]")[1]
    assert.equals("[[renamed#Head|shown]]", link.render(m, "renamed"))
  end)

  it("keeps the embed marker", function()
    local m = link.scan("![[note]]")[1]
    assert.equals("![[renamed]]", link.render(m, "renamed"))
  end)

  it("re-encodes a markdown target", function()
    local m = link.scan("[label](old.md)")[1]
    assert.equals("[label](new%20name.md)", link.render(m, "new name.md"))
  end)
end)

describe("link.rewrite", function()
  it("returns the text unchanged when nothing matches", function()
    local text = "[[a]] [[b]]"
    local out, n = link.rewrite(text, function() return nil end)
    assert.equals(text, out)
    assert.equals(0, n)
  end)

  it("rewrites only the matches the callback accepts", function()
    local out, n = link.rewrite("[[a]] [[b]]", function(m) return m.target == "a" and "z" or nil end)
    assert.equals("[[z]] [[b]]", out)
    assert.equals(1, n)
  end)

  it("leaves fenced links alone", function()
    local text = "[[a]]\n```\n[[a]]\n```\n"
    local out, n = link.rewrite(text, function() return "z" end)
    assert.equals("[[z]]\n```\n[[a]]\n```\n", out)
    assert.equals(1, n)
  end)

  it("preserves surrounding text exactly", function()
    local out = link.rewrite("before [[a]] after", function() return "z" end)
    assert.equals("before [[z]] after", out)
  end)
end)

describe("link.encode / decode", function()
  it("round-trips a space", function()
    assert.equals("note%20name", link.encode("note name"))
    assert.equals("note name", link.decode("note%20name"))
  end)

  it("encodes the characters that would otherwise change meaning", function()
    assert.equals("a%23b", link.encode("a#b"))
    assert.equals("a%3Fb", link.encode("a?b"))
    assert.equals("a%25b", link.encode("a%b"))
  end)

  it("returns a single value", function()
    assert.equals(1, select("#", link.encode("a b")))
    assert.equals(1, select("#", link.decode("a%20b")))
  end)
end)

describe("link.is_external", function()
  it("treats a scheme as external", function()
    assert.is_true(link.is_external("https://example.com"))
    assert.is_true(link.is_external("mailto:a@b.c"))
  end)

  it("treats a bare anchor and an empty target as external", function()
    assert.is_true(link.is_external("#heading"))
    assert.is_true(link.is_external(""))
  end)

  it("treats a vault path as internal", function() assert.is_false(link.is_external("folder/note.md")) end)
end)
