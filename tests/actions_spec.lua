local helpers = require("helpers")
local actions = require("knapp.actions")
local index = require("knapp.index")

describe("actions.rewrite_backlinks", function()
  after_each(helpers.cleanup)

  it("keeps a bare link bare when the new name is still unambiguous", function()
    local vault = helpers.setup({ ["src.md"] = "see [[old]]", ["old.md"] = "" })
    actions.rewrite_backlinks("old.md", "new.md")
    assert.equals("see [[new]]", helpers.read(vault, "src.md"))
  end)

  it("writes a path when the new name would be ambiguous", function()
    -- a second "new" already exists, so a bare [[new]] could not resolve here
    local vault = helpers.setup({
      ["src.md"] = "see [[old]]",
      ["old.md"] = "",
      ["other/new.md"] = "",
    })
    actions.rewrite_backlinks("old.md", "folder/new.md")
    assert.equals("see [[folder/new]]", helpers.read(vault, "src.md"))
  end)

  it("repaths a link that was already written as a path", function()
    local vault = helpers.setup({ ["src.md"] = "see [[a/old]]", ["a/old.md"] = "" })
    actions.rewrite_backlinks("a/old.md", "b/old.md")
    assert.equals("see [[b/old]]", helpers.read(vault, "src.md"))
  end)

  it("keeps an anchor and an alias", function()
    local vault = helpers.setup({ ["src.md"] = "[[old#Head|shown]]", ["old.md"] = "" })
    actions.rewrite_backlinks("old.md", "new.md")
    assert.equals("[[new#Head|shown]]", helpers.read(vault, "src.md"))
  end)

  it("keeps an embed an embed", function()
    local vault = helpers.setup({ ["src.md"] = "![[old]]", ["old.md"] = "" })
    actions.rewrite_backlinks("old.md", "new.md")
    assert.equals("![[new]]", helpers.read(vault, "src.md"))
  end)

  it("rewrites a markdown link to the full path, percent-encoded", function()
    local vault = helpers.setup({ ["src.md"] = "[label](old.md)", ["old.md"] = "" })
    actions.rewrite_backlinks("old.md", "new name.md")
    assert.equals("[label](new%20name.md)", helpers.read(vault, "src.md"))
  end)

  it("leaves a link that went through an alias alone", function()
    -- the alias still resolves after the rename, so touching it is churn
    local vault = helpers.setup({
      ["src.md"] = "see [[Nickname]]",
      ["old.md"] = "---\naliases: [Nickname]\n---\n",
    })
    actions.rewrite_backlinks("old.md", "new.md")
    assert.equals("see [[Nickname]]", helpers.read(vault, "src.md"))
  end)

  it("does not touch a link inside a fenced code block", function()
    local vault = helpers.setup({
      ["src.md"] = "[[old]]\n```\n[[old]]\n```\n",
      ["old.md"] = "",
    })
    actions.rewrite_backlinks("old.md", "new.md")
    assert.equals("[[new]]\n```\n[[old]]\n```\n", helpers.read(vault, "src.md"))
  end)

  it("reports why a file could not be read, not just that it failed", function()
    local vault = helpers.setup({ ["src.md"] = "[[old]]", ["old.md"] = "" })
    local path = vim.fs.joinpath(vault, "src.md")
    vim.uv.fs_chmod(path, 128) -- write-only: readable by nobody
    -- root ignores the mode bits, so there would be nothing to observe
    if require("knapp.util").read_file(path) then
      vim.uv.fs_chmod(path, 420)
      return pending("cannot make a file unreadable as this user")
    end
    local changed, skipped = actions.rewrite_backlinks("old.md", "new.md")
    vim.uv.fs_chmod(path, 420)
    assert.same({}, changed)
    assert.equals(1, #skipped)
    assert.equals("src.md", skipped[1].rel)
    assert.matches("[Pp]ermission denied", skipped[1].reason)
  end)

  it("reports which files it changed", function()
    helpers.setup({ ["a.md"] = "[[old]]", ["b.md"] = "[[old]]", ["c.md"] = "no link", ["old.md"] = "" })
    local changed, skipped = actions.rewrite_backlinks("old.md", "new.md")
    assert.same({ "a.md", "b.md" }, helpers.sorted(changed))
    assert.same({}, skipped)
  end)

  it("skips a source with unsaved changes instead of clobbering it", function()
    local vault = helpers.setup({ ["src.md"] = "[[old]]", ["old.md"] = "" })
    vim.cmd.edit(vim.fs.joinpath(vault, "src.md"))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "[[old]] edited but not written" })
    local changed, skipped = actions.rewrite_backlinks("old.md", "new.md")
    assert.same({}, changed)
    assert.same({ { rel = "src.md", reason = "unsaved changes" } }, skipped)
    assert.equals("[[old]]", helpers.read(vault, "src.md"))
    -- reported, never silently clobbered
    assert.equals(0, #helpers.notifications())
  end)
end)

describe("actions.move_note", function()
  after_each(helpers.cleanup)

  it("moves the file and relinks its backlinks", function()
    local vault = helpers.setup({ ["src.md"] = "[[old]]", ["old.md"] = "body\n" })
    assert.is_true(actions.move_note("old.md", "folder/new.md"))
    assert.is_false(helpers.exists(vault, "old.md"))
    assert.equals("body\n", helpers.read(vault, "folder/new.md"))
    assert.equals("[[new]]", helpers.read(vault, "src.md"))
  end)

  it("leaves the index resolving the new location", function()
    helpers.setup({ ["src.md"] = "[[old]]", ["old.md"] = "" })
    actions.move_note("old.md", "folder/new.md")
    assert.is_nil(index.state.files["old.md"])
    assert.equals("folder/new.md", index.resolve("new"))
    -- the rewritten source must be reparsed too, or the backlink is lost
    assert.same({ "src.md" }, index.backlinks("folder/new.md"))
  end)

  it("refuses to overwrite an existing note", function()
    local vault = helpers.setup({ ["old.md"] = "old body\n", ["new.md"] = "new body\n" })
    helpers.notifications()
    assert.is_false(actions.move_note("old.md", "new.md"))
    assert.equals("new body\n", helpers.read(vault, "new.md"))
    assert.is_true(helpers.exists(vault, "old.md"))
    local notes = helpers.notifications()
    assert.equals(1, #notes)
    assert.matches("already exists", notes[1].msg)
    assert.equals(vim.log.levels.ERROR, notes[1].level)
  end)

  it("refuses to move a note with unsaved changes", function()
    local vault = helpers.setup({ ["old.md"] = "" })
    vim.cmd.edit(vim.fs.joinpath(vault, "old.md"))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "edited" })
    assert.is_false(actions.move_note("old.md", "new.md"))
    assert.is_true(helpers.exists(vault, "old.md"))
  end)

  it("is a no-op when the source and destination are the same", function()
    local vault = helpers.setup({ ["a.md"] = "body\n" })
    assert.is_true(actions.move_note("a.md", "a.md"))
    assert.equals("body\n", helpers.read(vault, "a.md"))
  end)

  it("renames the open buffer along with the file", function()
    local vault = helpers.setup({ ["old.md"] = "body\n" })
    vim.cmd.edit(vim.fs.joinpath(vault, "old.md"))
    local buf = vim.api.nvim_get_current_buf()
    actions.move_note("old.md", "new.md")
    assert.equals(vim.fs.joinpath(vault, "new.md"), vim.api.nvim_buf_get_name(buf))
  end)
end)

describe("relink reporting", function()
  after_each(helpers.cleanup)

  it("puts files it could not relink into the quickfix list", function()
    local vault = helpers.setup({ ["src.md"] = "[[old]]", ["ok.md"] = "[[old]]", ["old.md"] = "" })
    vim.cmd.edit(vim.fs.joinpath(vault, "src.md"))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "[[old]] edited but not written" })
    vim.fn.setqflist({}, "r")
    helpers.notifications()

    actions.move_note("old.md", "new.md")

    local qf = vim.fn.getqflist({ title = 1, items = 1 })
    assert.equals("knapp: not relinked", qf.title)
    assert.equals(1, #qf.items)
    assert.matches("not relinked: unsaved changes", qf.items[1].text)
    assert.equals(vim.fs.joinpath(vault, "src.md"), vim.api.nvim_buf_get_name(qf.items[1].bufnr))

    local notes = helpers.notifications()
    assert.matches("see :copen", notes[#notes].msg)
    assert.equals(vim.log.levels.WARN, notes[#notes].level)
  end)

  it("does not touch the quickfix list when everything relinked", function()
    helpers.setup({ ["src.md"] = "[[old]]", ["old.md"] = "" })
    vim.fn.setqflist({}, " ", { title = "untouched", items = {} })
    actions.move_note("old.md", "new.md")
    assert.equals("untouched", vim.fn.getqflist({ title = 1 }).title)
  end)
end)

describe("actions.trash", function()
  after_each(helpers.cleanup)

  it("moves the note into .trash", function()
    local vault = helpers.setup({ ["a.md"] = "body\n" })
    assert.is_true(actions.trash("a.md", true))
    assert.is_false(helpers.exists(vault, "a.md"))
    assert.equals("body\n", helpers.read(vault, ".trash/a.md"))
  end)

  it("does not overwrite a note already in .trash", function()
    local vault = helpers.setup({ ["a.md"] = "second\n", [".trash/a.md"] = "first\n" })
    actions.trash("a.md", true)
    assert.equals("first\n", helpers.read(vault, ".trash/a.md"))
    assert.equals("second\n", helpers.read(vault, ".trash/a 1.md"))
  end)

  it("drops the note from the index", function()
    helpers.setup({ ["a.md"] = "" })
    actions.trash("a.md", true)
    assert.is_nil(index.state.files["a.md"])
  end)
end)

describe("actions.create_note", function()
  after_each(helpers.cleanup)

  it("creates the note in Obsidian's new-note folder", function()
    local vault = helpers.setup({}, { ["app.json"] = { newFileFolderPath = "Inbox" } })
    assert.equals("Inbox/idea.md", actions.create_note("idea", false))
    assert.is_true(helpers.exists(vault, "Inbox/idea.md"))
  end)

  it("honours an explicit path instead of the configured folder", function()
    local vault = helpers.setup({}, { ["app.json"] = { newFileFolderPath = "Inbox" } })
    assert.equals("elsewhere/idea.md", actions.create_note("elsewhere/idea", false))
    assert.is_true(helpers.exists(vault, "elsewhere/idea.md"))
  end)

  it("does not truncate a note that already exists", function()
    local vault = helpers.setup({ ["a.md"] = "body\n" })
    actions.create_note("a", false)
    assert.equals("body\n", helpers.read(vault, "a.md"))
  end)

  it("adds the new note to the index", function()
    helpers.setup({})
    actions.create_note("idea", false)
    assert.equals("idea.md", index.resolve("idea"))
  end)
end)

describe("actions.backlink_items", function()
  after_each(helpers.cleanup)

  it("reports one item per occurrence, with its position", function()
    helpers.setup({ ["src.md"] = "first [[t]]\nplain\nsecond [[t]]\n", ["t.md"] = "" })
    local items = actions.backlink_items("t.md")
    assert.equals(2, #items)
    assert.same({ 1, 3 }, vim.tbl_map(function(i) return i.lnum end, items))
    assert.same({ 7, 8 }, vim.tbl_map(function(i) return i.col end, items))
    assert.equals("first [[t]]", items[1].text)
  end)

  it("agrees with the index about fenced code blocks", function()
    helpers.setup({ ["src.md"] = "[[t]]\n```\n[[t]]\n```\n", ["t.md"] = "" })
    assert.equals(1, #actions.backlink_items("t.md"))
    assert.equals(1, #index.backlinks("t.md"))
  end)

  it("sorts by note name then line", function()
    helpers.setup({ ["b.md"] = "[[t]]", ["a.md"] = "x\n[[t]]", ["t.md"] = "" })
    local items = actions.backlink_items("t.md")
    assert.same({ "a", "b" }, vim.tbl_map(function(i) return i.name end, items))
  end)

  it("returns an empty list when nothing links here", function()
    helpers.setup({ ["t.md"] = "" })
    assert.same({}, actions.backlink_items("t.md"))
  end)
end)

describe("actions.current", function()
  after_each(helpers.cleanup)

  it("returns the vault-relative path of the current note", function()
    local vault = helpers.setup({ ["folder/a.md"] = "" })
    vim.cmd.edit(vim.fs.joinpath(vault, "folder/a.md"))
    assert.equals("folder/a.md", actions.current())
  end)

  it("returns nil outside the vault", function()
    helpers.setup({ ["a.md"] = "" })
    vim.cmd.edit(vim.fs.joinpath(helpers.tmpdir("outside"), "a.md"))
    assert.is_nil(actions.current())
  end)

  it("returns nil for a non-markdown file inside the vault", function()
    local vault = helpers.setup({ ["a.txt"] = "" })
    vim.cmd.edit(vim.fs.joinpath(vault, "a.txt"))
    assert.is_nil(actions.current())
  end)
end)

describe("actions.merge", function()
  local select_choice

  before_each(function() select_choice = nil end)
  after_each(helpers.cleanup)

  it("appends the note, relinks and trashes the original", function()
    local vault = helpers.setup({
      ["src.md"] = "[[from]]",
      ["from.md"] = "from body\n",
      ["into.md"] = "into body\n",
    })
    vim.cmd.edit(vim.fs.joinpath(vault, "from.md"))

    local original = vim.ui.select
    vim.ui.select = function(items, _, cb)
      select_choice = items
      cb("into.md")
    end
    local ok, err = pcall(actions.merge)
    vim.ui.select = original
    assert.is_true(ok, tostring(err))

    assert.equals("into body\n\nfrom body\n", helpers.read(vault, "into.md"))
    assert.equals("[[into]]", helpers.read(vault, "src.md"))
    assert.is_false(helpers.exists(vault, "from.md"))
    assert.equals("from body\n", helpers.read(vault, ".trash/from.md"))
    -- the note being merged is never offered as its own destination
    assert.is_false(vim.tbl_contains(select_choice, "from.md"))
  end)
end)
