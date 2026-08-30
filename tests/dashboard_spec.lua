local helpers = require("helpers")
local dashboard = require("knapp.dashboard")

--- Flatten a section tree to the text of every item that has any.
local function texts(section)
  local out = {}
  local function walk(node)
    if type(node) ~= "table" then return end
    if node.text then
      local line = ""
      if type(node.text) == "string" then
        line = node.text
      else
        for _, seg in ipairs(node.text) do
          line = line .. seg[1]
        end
      end
      out[#out + 1] = line
    end
    if node.title then out[#out + 1] = node.title end
    for _, child in ipairs(node) do
      walk(child)
    end
  end
  walk(section)
  return out
end

describe("dashboard.should_open", function()
  after_each(helpers.cleanup)

  it("is false outside the vault", function()
    helpers.setup({ ["a.md"] = "" })
    local cwd = vim.uv.cwd()
    vim.cmd.cd(helpers.tmpdir("elsewhere"))
    local got = dashboard.should_open()
    vim.cmd.cd(cwd)
    assert.is_false(got)
  end)

  it("is false when disabled", function()
    local vault = helpers.setup({ ["a.md"] = "" }, nil, { dashboard = { enabled = false } })
    local cwd = vim.uv.cwd()
    vim.cmd.cd(vault)
    local got = dashboard.should_open()
    vim.cmd.cd(cwd)
    assert.is_false(got)
  end)

  it("is false when auto is off", function()
    local vault = helpers.setup({ ["a.md"] = "" }, nil, { dashboard = { auto = false } })
    local cwd = vim.uv.cwd()
    vim.cmd.cd(vault)
    local got = dashboard.should_open()
    vim.cmd.cd(cwd)
    assert.is_false(got)
  end)

  it("is false when a file is already open", function()
    local vault = helpers.setup({ ["a.md"] = "" })
    local cwd = vim.uv.cwd()
    vim.cmd.cd(vault)
    vim.cmd.edit(vim.fs.joinpath(vault, "a.md"))
    local got = dashboard.should_open()
    vim.cmd.cd(cwd)
    assert.is_false(got)
  end)
end)

describe("dashboard.todo_section", function()
  after_each(helpers.cleanup)

  it("lists the unfinished tasks", function()
    helpers.setup({ ["TODO.md"] = "- [ ] alpha\n- [x] beta\n- [ ] gamma\n" })
    local lines = table.concat(texts(dashboard.todo_section()), "\n")
    assert.matches("alpha", lines)
    assert.matches("gamma", lines)
    assert.is_nil(lines:match("beta"))
    assert.matches("1 done", lines)
  end)

  it("says so when there is no todo file", function()
    helpers.setup({})
    assert.matches("no TODO%.md in the vault", table.concat(texts(dashboard.todo_section()), "\n"))
  end)

  it("says so when everything is finished", function()
    helpers.setup({ ["TODO.md"] = "- [x] done\n" })
    assert.matches("nothing left", table.concat(texts(dashboard.todo_section()), "\n"))
  end)

  it("caps the list and reports the remainder", function()
    local many = {}
    for i = 1, 12 do
      many[i] = ("- [ ] task %d"):format(i)
    end
    helpers.setup({ ["TODO.md"] = table.concat(many, "\n") }, nil, { dashboard = { todo_limit = 5 } })
    local lines = table.concat(texts(dashboard.todo_section()), "\n")
    assert.matches("task 5", lines)
    assert.is_nil(lines:match("task 6"))
    assert.matches("7 more", lines)
  end)

  it("names the configured file in its title", function()
    helpers.setup({ ["Journal/Tasks.md"] = "- [ ] a\n" }, nil, { dashboard = { todo = "Journal/Tasks.md" } })
    assert.matches("Journal/Tasks%.md", table.concat(texts(dashboard.todo_section()), "\n"))
  end)
end)

describe("dashboard.calendar_section", function()
  after_each(helpers.cleanup)

  it("draws this month", function()
    helpers.setup({}, { ["app.json"] = {} })
    local lines = texts(dashboard.calendar_section())
    assert.matches("Calendar", lines[1])
    assert.matches(require("knapp.date").format("MMMM YYYY"), table.concat(lines, "\n"))
  end)

  it("keeps the weekday header", function()
    helpers.setup({}, { ["app.json"] = {} })
    assert.matches("Mo Tu We Th Fr Sa Su", table.concat(texts(dashboard.calendar_section()), "\n"))
  end)
end)

describe("dashboard.sections", function()
  after_each(helpers.cleanup)

  it("builds without snacks installed", function()
    helpers.setup({ ["TODO.md"] = "- [ ] a\n" }, { ["app.json"] = {} })
    local ok, sections = pcall(dashboard.sections)
    assert.is_true(ok, tostring(sections))
    assert.is_true(#sections > 0)
  end)
end)
