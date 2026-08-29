local helpers = require("helpers")
local util = require("knapp.util")

describe("util.read_file", function()
  it("returns the contents", function()
    local dir = helpers.tmpdir("read")
    local path = vim.fs.joinpath(dir, "a.txt")
    helpers.write(path, "body\n")
    assert.equals("body\n", util.read_file(path))
  end)

  it("returns nil and a reason for a missing file", function()
    local text, reason = util.read_file(vim.fs.joinpath(helpers.tmpdir("read"), "nope.txt"))
    assert.is_nil(text)
    assert.matches("No such file", reason)
  end)
end)

describe("util.write_file", function()
  it("writes and reports success", function()
    local path = vim.fs.joinpath(helpers.tmpdir("write"), "a.txt")
    assert.is_true(util.write_file(path, "body\n"))
    assert.equals("body\n", util.read_file(path))
  end)

  it("returns false and a reason when the path is not writable", function()
    local ok, reason = util.write_file(vim.fs.joinpath(helpers.tmpdir("write"), "missing-dir", "a.txt"), "x")
    assert.is_false(ok)
    assert.matches("No such file", reason)
  end)
end)

describe("util.debounce", function()
  it("collapses a burst into one call", function()
    local calls = 0
    local bump = util.debounce(10, function() calls = calls + 1 end)
    bump()
    bump()
    bump()
    assert.equals(0, calls, "should not have fired synchronously")
    vim.wait(200, function() return calls > 0 end)
    assert.equals(1, calls)
  end)

  it("passes the arguments from the last call", function()
    local seen
    local record = util.debounce(10, function(a, b) seen = { a, b } end)
    record("first", 1)
    record("last", 2)
    vim.wait(200, function() return seen ~= nil end)
    assert.same({ "last", 2 }, seen)
  end)

  it("preserves nil arguments", function()
    local argc
    local record = util.debounce(10, function(...) argc = select("#", ...) end)
    record(nil, nil)
    vim.wait(200, function() return argc ~= nil end)
    assert.equals(2, argc)
  end)

  it("fires again after the first burst settles", function()
    local calls = 0
    local bump = util.debounce(10, function() calls = calls + 1 end)
    bump()
    vim.wait(200, function() return calls == 1 end)
    bump()
    vim.wait(200, function() return calls == 2 end)
    assert.equals(2, calls)
  end)
end)

describe("backlink scan cache", function()
  local actions = require("knapp.actions")

  --- Run `fn`, returning how many times a file was read from disk.
  local function count_reads(fn)
    local real = util.read_file
    local reads = 0
    util.read_file = function(...)
      reads = reads + 1
      return real(...)
    end
    local ok, err = pcall(fn)
    util.read_file = real
    assert.is_true(ok, tostring(err))
    return reads
  end

  after_each(helpers.cleanup)

  it("does not re-read an unchanged source", function()
    helpers.setup({ ["a.md"] = "[[t]]", ["b.md"] = "[[t]]", ["t.md"] = "" })
    assert.equals(2, count_reads(function() actions.backlink_items("t.md") end))
    assert.equals(0, count_reads(function() actions.backlink_items("t.md") end))
  end)

  it("re-reads a source whose size changed", function()
    local vault = helpers.setup({ ["a.md"] = "[[t]]", ["t.md"] = "" })
    assert.equals(1, #actions.backlink_items("t.md"))
    helpers.write(vim.fs.joinpath(vault, "a.md"), "[[t]] and [[t]] again")
    assert.equals(2, #actions.backlink_items("t.md"))
  end)

  it("re-reads a source edited in place within the same second", function()
    -- same byte length, so only the sub-second mtime distinguishes them
    local vault = helpers.setup({ ["a.md"] = "[[t]] xxxxx", ["t.md"] = "" })
    assert.equals(1, #actions.backlink_items("t.md"))
    helpers.write(vim.fs.joinpath(vault, "a.md"), "xxxxx [[t]]")
    local items = actions.backlink_items("t.md")
    assert.equals(1, #items)
    assert.equals(7, items[1].col)
  end)

  it("forgets a source that was deleted", function()
    local vault = helpers.setup({ ["a.md"] = "[[t]]", ["t.md"] = "" })
    actions.backlink_items("t.md")
    vim.uv.fs_unlink(vim.fs.joinpath(vault, "a.md"))
    assert.same({}, actions.backlink_items("t.md"))
  end)
end)

describe("util.is_md", function()
  it("accepts markdown regardless of case", function()
    assert.is_true(util.is_md("note.md"))
    assert.is_true(util.is_md("NOTE.MD"))
    assert.is_true(util.is_md("folder/Note.Md"))
  end)

  it("rejects anything else", function()
    assert.is_false(util.is_md("note.txt"))
    assert.is_false(util.is_md("md"))
    assert.is_false(util.is_md(""))
    assert.is_false(util.is_md(nil))
  end)
end)
