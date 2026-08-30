local helpers = require("helpers")
local todo = require("knapp.todo")

describe("todo.parse", function()
  it("finds unchecked and checked tasks", function()
    local tasks = todo.parse("- [ ] open\n- [x] closed\n")
    assert.equals(2, #tasks)
    assert.is_false(tasks[1].done)
    assert.is_true(tasks[2].done)
    assert.same({ "open", "closed" }, vim.tbl_map(function(t) return t.text end, tasks))
  end)

  it("records the line number", function()
    local tasks = todo.parse("intro\n\n- [ ] first\ntext\n- [ ] second\n")
    assert.same({ 3, 5 }, vim.tbl_map(function(t) return t.lnum end, tasks))
  end)

  it("accepts any list marker", function() assert.equals(3, #todo.parse("- [ ] a\n* [ ] b\n+ [ ] c\n")) end)

  it("treats any non-space marker as done", function()
    local tasks = todo.parse("- [ ] a\n- [x] b\n- [X] c\n- [/] d\n")
    assert.same({ false, true, true, true }, vim.tbl_map(function(t) return t.done end, tasks))
    assert.equals("/", tasks[4].marker)
  end)

  it("keeps the indent so nesting survives", function()
    local tasks = todo.parse("- [ ] parent\n  - [ ] child\n    - [ ] grandchild\n")
    assert.same({ 0, 2, 4 }, vim.tbl_map(function(t) return t.indent end, tasks))
  end)

  it("ignores tasks inside fenced code blocks", function()
    local tasks = todo.parse("- [ ] real\n```md\n- [ ] fake\n```\n- [ ] also real\n")
    assert.same({ "real", "also real" }, vim.tbl_map(function(t) return t.text end, tasks))
  end)

  it(
    "ignores things that are not tasks",
    function() assert.same({}, todo.parse("- plain bullet\n[ ] no bullet\n# heading\n")) end
  )

  it("handles an empty task", function()
    local tasks = todo.parse("- [ ]\n")
    assert.equals(1, #tasks)
    assert.equals("", tasks[1].text)
  end)

  it("returns nothing for empty input", function() assert.same({}, todo.parse("")) end)
end)

describe("todo file", function()
  after_each(helpers.cleanup)

  it("reads the configured file", function()
    helpers.setup({ ["TODO.md"] = "- [ ] write specs\n- [x] done\n" })
    assert.same({ "write specs", "done" }, vim.tbl_map(function(t) return t.text end, todo.items()))
  end)

  it("adds .md when the config leaves it off", function()
    helpers.setup({ ["Tasks.md"] = "- [ ] a\n" }, nil, { dashboard = { todo = "Tasks" } })
    assert.equals("Tasks.md", todo.rel())
    assert.equals(1, #todo.items())
  end)

  it("honours a path inside a folder", function()
    helpers.setup({ ["Journal/Tasks.md"] = "- [ ] a\n" }, nil, { dashboard = { todo = "Journal/Tasks.md" } })
    assert.equals(1, #todo.items())
  end)

  it("is empty when the file does not exist", function()
    helpers.setup({})
    assert.is_nil(todo.path())
    assert.same({}, todo.items())
  end)
end)
