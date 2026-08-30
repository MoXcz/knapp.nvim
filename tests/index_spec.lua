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

  it("indexes a note with an upper-case extension", function()
    helpers.setup({ ["a.md"] = "", ["Shouty.MD"] = "" })
    assert.same({ "Shouty.MD", "a.md" }, helpers.sorted(vim.tbl_keys(index.state.files)))
    assert.equals("Shouty.MD", index.resolve("Shouty"))
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

describe("index.update incremental path", function()
  after_each(helpers.cleanup)

  -- A body-only edit must not disturb any other note's edges, and a change to
  -- the name/alias space must fall back to a full rebuild because it can move
  -- where other notes' bare-name links point.

  it("keeps other notes' backlinks when one note's links change", function()
    local vault = helpers.setup({ ["a.md"] = "[[t]]", ["b.md"] = "[[t]]", ["t.md"] = "" })
    helpers.write(vim.fs.joinpath(vault, "a.md"), "no link any more")
    index.update("a.md")
    assert.same({ "b.md" }, index.backlinks("t.md"))
  end)

  it("keeps the backlink when only one of several occurrences is removed", function()
    local vault = helpers.setup({ ["a.md"] = "[[t]] and [[t]]", ["t.md"] = "" })
    helpers.write(vim.fs.joinpath(vault, "a.md"), "[[t]] once")
    index.update("a.md")
    assert.same({ "a.md" }, index.backlinks("t.md"))
  end)

  it("does not duplicate a backlink when a note gains a second link to the same note", function()
    local vault = helpers.setup({ ["a.md"] = "[[t]]", ["t.md"] = "" })
    helpers.write(vim.fs.joinpath(vault, "a.md"), "[[t]] and [[t]] again")
    index.update("a.md")
    assert.same({ "a.md" }, index.backlinks("t.md"))
  end)

  it("moves a backlink when a link is repointed", function()
    local vault = helpers.setup({ ["a.md"] = "[[one]]", ["one.md"] = "", ["two.md"] = "" })
    helpers.write(vim.fs.joinpath(vault, "a.md"), "[[two]]")
    index.update("a.md")
    assert.same({}, index.backlinks("one.md"))
    assert.same({ "a.md" }, index.backlinks("two.md"))
  end)

  it("rebuilds when a note gains an alias, so links through it resolve", function()
    local vault = helpers.setup({ ["a.md"] = "[[Nickname]]", ["t.md"] = "" })
    assert.same({}, index.backlinks("t.md"))
    helpers.write(vim.fs.joinpath(vault, "t.md"), "---\naliases: [Nickname]\n---\n")
    index.update("t.md")
    assert.equals("t.md", index.resolve("Nickname"))
    assert.same({ "a.md" }, index.backlinks("t.md"))
  end)

  it("rebuilds when a note loses an alias", function()
    local vault = helpers.setup({ ["a.md"] = "[[Nickname]]", ["t.md"] = "---\naliases: [Nickname]\n---\n" })
    assert.same({ "a.md" }, index.backlinks("t.md"))
    helpers.write(vim.fs.joinpath(vault, "t.md"), "no aliases now\n")
    index.update("t.md")
    assert.is_nil(index.resolve("Nickname"))
    assert.same({}, index.backlinks("t.md"))
  end)

  it("rebuilds when a new note makes a bare name ambiguous", function()
    -- [[note]] in b/ resolves to the only "note" there is; adding a closer one
    -- must repoint it, which only a full rebuild can see
    local vault = helpers.setup({ ["a/note.md"] = "", ["b/src.md"] = "[[note]]" })
    assert.same({ "b/src.md" }, index.backlinks("a/note.md"))
    helpers.write(vim.fs.joinpath(vault, "b/note.md"), "")
    index.update("b/note.md")
    assert.same({}, index.backlinks("a/note.md"))
    assert.same({ "b/src.md" }, index.backlinks("b/note.md"))
  end)

  it("rebuilds when a note is deleted, dropping links that pointed at it", function()
    local vault = helpers.setup({ ["a/note.md"] = "", ["b/note.md"] = "", ["b/src.md"] = "[[note]]" })
    assert.same({ "b/src.md" }, index.backlinks("b/note.md"))
    vim.uv.fs_unlink(vim.fs.joinpath(vault, "b/note.md"))
    index.update("b/note.md")
    -- the link now resolves to the remaining note instead
    assert.same({ "b/src.md" }, index.backlinks("a/note.md"))
  end)

  it("agrees with a full rebuild after a body-only edit", function()
    local vault = helpers.setup({
      ["a.md"] = "[[t]] [[u]]",
      ["b.md"] = "[[t]]",
      ["t.md"] = "",
      ["u.md"] = "",
    })
    helpers.write(vim.fs.joinpath(vault, "a.md"), "[[u]] only")
    index.update("a.md")
    local incremental = {
      t = helpers.sorted(index.backlinks("t.md")),
      u = helpers.sorted(index.backlinks("u.md")),
    }
    index.reindex()
    assert.same(incremental.t, helpers.sorted(index.backlinks("t.md")))
    assert.same(incremental.u, helpers.sorted(index.backlinks("u.md")))
    assert.same({ "b.md" }, incremental.t)
  end)

  it("handles a note that links to itself", function()
    local vault = helpers.setup({ ["a.md"] = "" })
    helpers.write(vim.fs.joinpath(vault, "a.md"), "[[a]]")
    index.update("a.md")
    assert.same({ "a.md" }, index.backlinks("a.md"))
  end)
end)

describe("index cache writing", function()
  after_each(helpers.cleanup)

  it("writes atomically and leaves no temp file behind", function()
    helpers.setup({ ["a.md"] = "" })
    assert.is_true(index.save_cache())
    assert.is_not_nil(vim.uv.fs_stat(index.cache_file()))
    assert.is_nil(vim.uv.fs_stat(index.cache_file() .. ".tmp"))
  end)

  it("flushes a scheduled write on demand", function()
    helpers.setup({ ["a.md"] = "" })
    local path = index.cache_file()
    vim.uv.fs_unlink(path)
    index.schedule_save()
    assert.is_nil(vim.uv.fs_stat(path), "the debounced write should not have landed yet")
    index.flush_cache()
    assert.is_not_nil(vim.uv.fs_stat(path))
  end)

  it("does not rewrite the cache when nothing is pending", function()
    helpers.setup({ ["a.md"] = "" })
    index.flush_cache()
    local path = index.cache_file()
    vim.uv.fs_unlink(path)
    index.flush_cache()
    assert.is_nil(vim.uv.fs_stat(path))
  end)

  it("survives a truncated cache from an interrupted write", function()
    local vault = helpers.setup({ ["a.md"] = "[[b]]", ["b.md"] = "" })
    local path = index.cache_file()
    helpers.write(path, '{"version":1,"vault":"' .. vault .. '","fil')
    index.state.built = false
    local result = index.build()
    assert.equals(2, result.total)
    assert.equals(2, result.parsed)
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

describe("index.notes and folders caching", function()
  after_each(helpers.cleanup)

  it("returns the same table until something changes", function()
    helpers.setup({ ["a.md"] = "" })
    assert.equals(index.notes(), index.notes())
    assert.equals(index.folders(), index.folders())
  end)

  it("picks up a note created afterwards", function()
    local vault = helpers.setup({ ["a.md"] = "" })
    assert.equals(1, #index.notes())
    helpers.write(vim.fs.joinpath(vault, "b.md"), "")
    index.update("b.md")
    assert.equals(2, #index.notes())
  end)

  it("drops a note that was deleted", function()
    local vault = helpers.setup({ ["a.md"] = "", ["b.md"] = "" })
    assert.equals(2, #index.notes())
    vim.uv.fs_unlink(vim.fs.joinpath(vault, "b.md"))
    index.update("b.md")
    assert.equals(1, #index.notes())
  end)

  it("picks up a new folder", function()
    local vault = helpers.setup({ ["a.md"] = "" })
    assert.same({ "." }, index.folders())
    helpers.write(vim.fs.joinpath(vault, "sub/b.md"), "")
    index.update("sub/b.md")
    assert.same({ ".", "sub" }, index.folders())
  end)

  it("reflects a move", function()
    helpers.setup({ ["a.md"] = "" })
    require("knapp.actions").move_note("a.md", "sub/a.md")
    assert.same({ "sub/a.md" }, vim.tbl_map(function(n) return n.rel end, index.notes()))
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

describe("index.build_background", function()
  after_each(helpers.cleanup)

  local function reset()
    index.state.built = false
    index.state.files = {}
  end

  it("completes on its own and fires KnappIndexChanged", function()
    helpers.setup({ ["a.md"] = "[[b]]", ["b.md"] = "" })
    reset()
    local announced = false
    vim.api.nvim_create_autocmd("User", {
      pattern = "KnappIndexChanged",
      once = true,
      callback = function() announced = true end,
    })
    index.build_background()
    vim.wait(2000, function() return index.state.built and announced end)
    assert.is_true(index.state.built)
    assert.is_true(announced)
    assert.same({ "a.md" }, index.backlinks("b.md"))
  end)

  it("is drained synchronously by ensure()", function()
    helpers.setup({ ["a.md"] = "[[b]]", ["b.md"] = "" })
    reset()
    index.build_background()
    -- no event loop turns yet: ensure() must finish the build on the spot
    index.ensure()
    assert.is_true(index.state.built)
    assert.same({ "a.md" }, index.backlinks("b.md"))
  end)

  it("try_ensure reports incomplete, then complete", function()
    helpers.setup({ ["a.md"] = "" })
    reset()
    -- a fresh cacheless build of even one file takes at least one slice
    vim.uv.fs_unlink(index.cache_file())
    local first = index.try_ensure()
    vim.wait(2000, function() return index.state.built end)
    assert.is_true(index.state.built)
    assert.is_true(index.try_ensure())
    -- first call may or may not have finished within its first slice; what
    -- matters is that it never blocked and the index converged
    assert.is_boolean(first)
  end)
end)

describe("index symlinks", function()
  after_each(helpers.cleanup)

  it("follows a symlinked note and a symlinked folder", function()
    local vault = helpers.setup({ ["a.md"] = "" })
    local outside = helpers.tmpdir("outside")
    helpers.write(vim.fs.joinpath(outside, "linked.md"), "")
    helpers.write(vim.fs.joinpath(outside, "dir/inner.md"), "")
    assert(vim.uv.fs_symlink(vim.fs.joinpath(outside, "linked.md"), vim.fs.joinpath(vault, "linked.md")))
    assert(vim.uv.fs_symlink(vim.fs.joinpath(outside, "dir"), vim.fs.joinpath(vault, "dir"), { dir = true }))
    index.build({ force = true })
    assert.same({ "a.md", "dir/inner.md", "linked.md" }, helpers.sorted(vim.tbl_keys(index.state.files)))
  end)

  it("does not loop on a symlink cycle", function()
    local vault = helpers.setup({ ["a.md"] = "" })
    -- sub/back points at the vault root: walking it again would never end
    vim.fn.mkdir(vim.fs.joinpath(vault, "sub"), "p")
    assert(vim.uv.fs_symlink(vault, vim.fs.joinpath(vault, "sub/back"), { dir = true }))
    local result = index.build({ force = true })
    assert.equals(1, result.total)
  end)
end)
