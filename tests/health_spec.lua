local helpers = require("helpers")

--- Run `:checkhealth knapp` and return the report as one string.
local function report()
  vim.cmd("silent checkhealth knapp")
  local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  vim.cmd("bwipeout!")
  return text
end

describe("health", function()
  after_each(helpers.cleanup)

  it("reports that setup() has not been called", function()
    require("knapp.config").opts.vault = nil
    local text = report()
    assert.matches("setup%(%) has not been called", text)
    assert.matches("minimal reproducer config", text)
  end)

  it("reports a healthy vault", function()
    helpers.setup({ ["a.md"] = "[[b]]", ["b.md"] = "" }, {
      ["app.json"] = { newFileFolderPath = "" },
      ["daily-notes.json"] = { folder = "Daily", format = "YYYY-MM-DD" },
      ["templates.json"] = { folder = "Templates" },
    })
    local text = report()
    assert.matches("configuration is valid", text)
    assert.matches("index built: 2 notes", text)
    assert.matches("app%.json", text)
  end)

  it("flags a bad option value", function()
    helpers.setup({}, nil, { backlinks = { position = "rihgt" } })
    assert.matches("backlinks%.position", report())
  end)

  it("flags an unknown option without flagging vault", function()
    helpers.setup({}, nil, { nonsense = true })
    local text = report()
    assert.matches("unknown option `nonsense`", text)
    assert.is_nil(text:match("unknown option `vault`"))
  end)

  it("flags a missing vault directory", function()
    helpers.setup({})
    require("knapp.config").opts.vault = "/definitely/not/here"
    assert.matches("vault does not exist", report())
  end)

  it("flags malformed JSON in .obsidian", function()
    local vault = helpers.setup({}, { ["app.json"] = {} })
    helpers.write(vim.fs.joinpath(vault, ".obsidian/app.json"), "{ not json")
    assert.matches("is not valid JSON", report())
  end)

  it("names the community plugin behind a missing settings file", function()
    helpers.setup({}, { ["app.json"] = {} })
    assert.matches("Zettelkasten Prefixer", report())
  end)

  it("says so when the vault has no .obsidian at all", function()
    helpers.setup({})
    assert.matches("%.obsidian not found", report())
  end)
end)
