local helpers = require("helpers")
local template = require("knapp.template")
local date = require("knapp.date")

local WED = date.of(2024, 3, 13)

describe("template.expand", function()
  before_each(
    function()
      helpers.setup({}, {
        ["templates.json"] = { folder = "Templates", dateFormat = "YYYY-MM-DD", timeFormat = "HH:mm" },
      })
    end
  )
  after_each(helpers.cleanup)

  it(
    "expands the title",
    function() assert.equals("# My Note", template.expand("# {{title}}", { title = "My Note" })) end
  )

  it("expands an absent title to nothing", function() assert.equals("# ", template.expand("# {{title}}", {})) end)

  it("expands date and time using the configured formats", function()
    assert.equals("2024-03-13", template.expand("{{date}}", { time = WED }))
    assert.equals("12:00", template.expand("{{time}}", { time = WED }))
  end)

  it(
    "expands an explicit format",
    function() assert.equals("March 13, 2024", template.expand("{{date:MMMM D, YYYY}}", { time = WED })) end
  )

  it("expands a date offset", function()
    assert.equals("2024-03-19", template.expand("{{date+6d:YYYY-MM-DD}}", { time = WED }))
    assert.equals("2024-03-06", template.expand("{{date-1w:YYYY-MM-DD}}", { time = WED }))
  end)

  it("is case-insensitive on the placeholder name", function()
    assert.equals("2024-03-13", template.expand("{{DATE:YYYY-MM-DD}}", { time = WED }))
    assert.equals("x", template.expand("{{TITLE}}", { title = "x" }))
  end)

  it("leaves an unknown placeholder untouched", function()
    assert.equals("{{unknown}}", template.expand("{{unknown}}", {}))
    assert.equals("{{a:b}}", template.expand("{{a:b}}", {}))
  end)

  it(
    "expands several placeholders in one pass",
    function() assert.equals("t 2024-03-13", template.expand("{{title}} {{date}}", { title = "t", time = WED })) end
  )

  it(
    "leaves surrounding text alone",
    function()
      assert.equals("---\ntags: []\n---\n# t\n", template.expand("---\ntags: []\n---\n# {{title}}\n", { title = "t" }))
    end
  )
end)

describe("template.path and render", function()
  local vault

  before_each(
    function()
      vault = helpers.setup({
        ["Templates/Daily.md"] = "# {{title}}\n\n{{date:YYYY-MM-DD}}\n",
        ["Templates/Weekly.md"] = "week\n",
        ["Root Template.md"] = "root\n",
      }, {
        ["templates.json"] = { folder = "Templates", dateFormat = "YYYY-MM-DD", timeFormat = "HH:mm" },
      })
    end
  )
  after_each(helpers.cleanup)

  it(
    "resolves a bare name inside the templates folder",
    function() assert.equals(vim.fs.joinpath(vault, "Templates/Daily.md"), template.path("Daily")) end
  )

  it(
    "resolves a name that already ends in .md",
    function() assert.equals(vim.fs.joinpath(vault, "Templates/Daily.md"), template.path("Daily.md")) end
  )

  it(
    "resolves a vault-relative path outside the templates folder",
    function() assert.equals(vim.fs.joinpath(vault, "Root Template.md"), template.path("Root Template")) end
  )

  it("returns nil for a missing or empty name", function()
    assert.is_nil(template.path("Nope"))
    assert.is_nil(template.path(""))
    assert.is_nil(template.path(nil))
  end)

  it(
    "renders a template with its placeholders expanded",
    function() assert.equals("# T\n\n2024-03-13\n", template.render("Daily", { title = "T", time = WED })) end
  )

  it("renders a missing template as an empty string", function()
    assert.equals("", template.render("Nope", {}))
    assert.equals("", template.render(nil, {}))
  end)

  it(
    "lists the templates folder, sorted, without the extension",
    function() assert.same({ "Daily", "Weekly" }, template.list()) end
  )
end)
