local helpers = require("helpers")
local index = require("knapp.index")

describe("index.build", function()
  after_each(helpers.cleanup)

  it("finds every markdown file, at any depth", function()
    helpers.setup({
      ["a.md"] = "",
      ["folder/b.md"] = "",
      ["folder/deep/c.md"] = "",
      ["not-a-note.txt"] = "",
    })
    assert.same({ "a.md", "folder/b.md", "folder/deep/c.md" }, helpers.sorted(vim.tbl_keys(index.state.files)))
  end)

  it("skips ignored directories", function()
    helpers.setup({
      ["a.md"] = "",
      [".obsidian/plugin.md"] = "",
      [".trash/deleted.md"] = "",
      [".git/COMMIT_EDITMSG.md"] = "",
    })
    assert.same({ "a.md" }, vim.tbl_keys(index.state.files))
  end)

  it("reports how many files it parsed", function()
    helpers.setup({ ["a.md"] = "", ["b.md"] = "" })
    local result = index.build({ force = true })
    assert.equals(2, result.total)
    assert.equals(2, result.parsed)
  end)

  it("reuses cached entries whose mtime is unchanged", function()
    helpers.setup({ ["a.md"] = "", ["b.md"] = "" })
    index.save_cache()
    index.state.built = false
    local result = index.build()
    assert.equals(2, result.total)
    assert.equals(0, result.parsed)
  end)
end)

describe("index.resolve", function()
  after_each(helpers.cleanup)

  it("resolves a bare name", function()
    helpers.setup({ ["note.md"] = "", ["folder/other.md"] = "" })
    assert.equals("note.md", index.resolve("note"))
    assert.equals("folder/other.md", index.resolve("other"))
  end)

  it("resolves a vault-relative path", function()
    helpers.setup({ ["folder/note.md"] = "" })
    assert.equals("folder/note.md", index.resolve("folder/note"))
    assert.equals("folder/note.md", index.resolve("folder/note.md"))
  end)

  it("is case-insensitive", function()
    helpers.setup({ ["Note.md"] = "" })
    assert.equals("Note.md", index.resolve("note"))
    assert.equals("Note.md", index.resolve("NOTE"))
  end)

  it("prefers a path over a same-named bare note", function()
    helpers.setup({ ["note.md"] = "", ["folder/note.md"] = "" })
    assert.equals("folder/note.md", index.resolve("folder/note"))
  end)

  it("prefers the file in the same folder as the link source", function()
    helpers.setup({ ["a/note.md"] = "", ["b/note.md"] = "" })
    assert.equals("a/note.md", index.resolve("note", "a/source.md"))
    assert.equals("b/note.md", index.resolve("note", "b/source.md"))
  end)

  it("prefers the shallowest file when none is in the source folder", function()
    helpers.setup({ ["note.md"] = "", ["deep/nested/note.md"] = "" })
    assert.equals("note.md", index.resolve("note", "elsewhere/source.md"))
  end)

  it("returns nil for an unknown or empty target", function()
    helpers.setup({ ["note.md"] = "" })
    assert.is_nil(index.resolve("missing"))
    assert.is_nil(index.resolve(""))
  end)
end)

describe("index aliases", function()
  after_each(helpers.cleanup)

  it("resolves an inline alias list", function()
    helpers.setup({ ["note.md"] = "---\naliases: [First, Second]\n---\n" })
    assert.equals("note.md", index.resolve("First"))
    assert.equals("note.md", index.resolve("second"))
  end)

  it("resolves a block alias list", function()
    helpers.setup({ ["note.md"] = "---\naliases:\n  - First\n  - Second\n---\n" })
    assert.equals("note.md", index.resolve("First"))
    assert.equals("note.md", index.resolve("Second"))
  end)

  it("strips quotes from aliases", function()
    helpers.setup({ ["note.md"] = "---\naliases: [\"Quoted One\", 'Quoted Two']\n---\n" })
    assert.equals("note.md", index.resolve("Quoted One"))
    assert.equals("note.md", index.resolve("Quoted Two"))
  end)

  it("stops the block list at the next key", function()
    helpers.setup({ ["note.md"] = "---\naliases:\n  - First\ntags:\n  - NotAnAlias\n---\n" })
    assert.equals("note.md", index.resolve("First"))
    assert.is_nil(index.resolve("NotAnAlias"))
  end)

  it("ignores a file with no frontmatter", function()
    helpers.setup({ ["note.md"] = "aliases: [Nope]\n" })
    assert.is_nil(index.resolve("Nope"))
  end)
end)

describe("index.backlinks", function()
  after_each(helpers.cleanup)

  it("records who links to a note", function()
    helpers.setup({ ["a.md"] = "[[target]]", ["b.md"] = "[[target]]", ["target.md"] = "" })
    assert.same({ "a.md", "b.md" }, helpers.sorted(index.backlinks("target.md")))
  end)

  it("records a note only once however many times it links", function()
    helpers.setup({ ["a.md"] = "[[target]] and [[target]] again", ["target.md"] = "" })
    assert.same({ "a.md" }, index.backlinks("target.md"))
  end)

  it("follows an alias to the real file", function()
    helpers.setup({ ["a.md"] = "[[Alias]]", ["target.md"] = "---\naliases: [Alias]\n---\n" })
    assert.same({ "a.md" }, index.backlinks("target.md"))
  end)

  it("follows a markdown link", function()
    helpers.setup({ ["a.md"] = "[label](target%20note.md)", ["target note.md"] = "" })
    assert.same({ "a.md" }, index.backlinks("target note.md"))
  end)

  it("ignores links inside fenced code blocks", function()
    helpers.setup({ ["a.md"] = "```\n[[target]]\n```\n", ["target.md"] = "" })
    assert.same({}, index.backlinks("target.md"))
  end)

  it("returns an empty list for a note nothing links to", function()
    helpers.setup({ ["lonely.md"] = "" })
    assert.same({}, index.backlinks("lonely.md"))
  end)
end)

describe("index.update", function()
  after_each(helpers.cleanup)

  it("picks up a new link after a file changes on disk", function()
    local vault = helpers.setup({ ["a.md"] = "nothing", ["target.md"] = "" })
    assert.same({}, index.backlinks("target.md"))
    helpers.write(vim.fs.joinpath(vault, "a.md"), "[[target]]")
    index.update("a.md")
    assert.same({ "a.md" }, index.backlinks("target.md"))
  end)

  it("drops a link that was removed", function()
    local vault = helpers.setup({ ["a.md"] = "[[target]]", ["target.md"] = "" })
    helpers.write(vim.fs.joinpath(vault, "a.md"), "nothing")
    index.update("a.md")
    assert.same({}, index.backlinks("target.md"))
  end)

  it("drops a file that no longer exists", function()
    local vault = helpers.setup({ ["a.md"] = "[[target]]", ["target.md"] = "" })
    vim.uv.fs_unlink(vim.fs.joinpath(vault, "a.md"))
    index.update("a.md")
    assert.is_nil(index.state.files["a.md"])
    assert.same({}, index.backlinks("target.md"))
  end)

  it("updates several files at once", function()
    local vault = helpers.setup({ ["a.md"] = "", ["b.md"] = "", ["target.md"] = "" })
    helpers.write(vim.fs.joinpath(vault, "a.md"), "[[target]]")
    helpers.write(vim.fs.joinpath(vault, "b.md"), "[[target]]")
    index.update_many({ "a.md", "b.md", "a.md" })
    assert.same({ "a.md", "b.md" }, helpers.sorted(index.backlinks("target.md")))
  end)
end)

describe("index.notes and folders", function()
  after_each(helpers.cleanup)

  it("lists every note with its name and folder", function()
    helpers.setup({ ["a.md"] = "", ["folder/b.md"] = "" })
    assert.same({
      { rel = "a.md", name = "a", dir = "." },
      { rel = "folder/b.md", name = "b", dir = "folder" },
    }, index.notes())
  end)

  it("lists every folder holding notes, plus the root, plus intermediates", function()
    helpers.setup({ ["a.md"] = "", ["one/b.md"] = "", ["one/two/c.md"] = "" })
    assert.same({ ".", "one", "one/two" }, index.folders())
  end)
end)

describe("index cache", function()
  after_each(helpers.cleanup)

  it("is rejected when it was written for a different vault", function()
    helpers.setup({ ["a.md"] = "" })
    index.save_cache()
    -- point knapp at a second vault, reusing the first one's cache directory
    local cache = require("knapp.config").opts.cache
    helpers.setup({ ["b.md"] = "" }, nil, { cache = cache })
    assert.same({ "b.md" }, vim.tbl_keys(index.state.files))
  end)
end)
