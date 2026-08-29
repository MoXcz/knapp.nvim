local helpers = require("helpers")
local journal = require("knapp.journal")
local date = require("knapp.date")
local ocfg = require("knapp.obsidian_cfg")

describe("journal.daily_path", function()
  after_each(helpers.cleanup)

  it("uses the folder and format from daily-notes.json", function()
    helpers.setup({}, { ["daily-notes.json"] = { folder = "Journal/Daily", format = "YYYY-MM-DD dddd" } })
    assert.equals("Journal/Daily/2024-03-13 Wednesday.md", journal.daily_path(date.of(2024, 3, 13)))
  end)

  it("falls back to YYYY-MM-DD at the vault root", function()
    helpers.setup({}, { ["app.json"] = {} })
    assert.equals("2024-03-13.md", journal.daily_path(date.of(2024, 3, 13)))
  end)
end)

describe("journal.weekly_path", function()
  after_each(helpers.cleanup)

  -- Obsidian's Calendar plugin defaults to gggg-[W]ww. `gggg` is the ISO
  -- week-numbering year, which diverges from the calendar year around New
  -- Year; knapp used to fall back to YYYY-[W]WW and name those notes wrongly.
  it("defaults to the Calendar plugin's gggg-[W]ww", function()
    helpers.setup({}, { ["app.json"] = {} })
    assert.equals("gggg-[W]ww", ocfg.get().weekly.format)
  end)

  it("names the week of 2024-12-30 as 2025-W01, not 2024-W01", function()
    helpers.setup({}, { ["app.json"] = {} })
    -- Monday 30 December 2024 is the first ISO week of 2025
    assert.equals("2025-W01.md", journal.weekly_path(date.of(2024, 12, 30)))
    -- every day of that week resolves to the same note
    assert.equals("2025-W01.md", journal.weekly_path(date.of(2025, 1, 3)))
  end)

  it("uses the folder and format configured in the Calendar plugin", function()
    helpers.setup({}, {
      ["plugins/calendar/data.json"] = { weeklyNoteFolder = "Weekly", weeklyNoteFormat = "YYYY-[W]WW" },
    })
    assert.equals("Weekly/2024-W11.md", journal.weekly_path(date.of(2024, 3, 13)))
  end)

  it("ignores an empty configured format", function()
    helpers.setup({}, { ["plugins/calendar/data.json"] = { weeklyNoteFormat = "" } })
    assert.equals("gggg-[W]ww", ocfg.get().weekly.format)
  end)

  it("anchors the week to Monday by default", function()
    helpers.setup({}, { ["plugins/calendar/data.json"] = { weeklyNoteFormat = "YYYY-MM-DD" } })
    -- Wednesday and the following Sunday are in the same week
    assert.equals("2024-03-11.md", journal.weekly_path(date.of(2024, 3, 13)))
    assert.equals("2024-03-11.md", journal.weekly_path(date.of(2024, 3, 17)))
  end)

  it("honours weekStart = sunday", function()
    helpers.setup({}, {
      ["plugins/calendar/data.json"] = { weeklyNoteFormat = "YYYY-MM-DD", weekStart = "sunday" },
    })
    assert.equals("2024-03-10.md", journal.weekly_path(date.of(2024, 3, 13)))
  end)
end)

describe("journal.open", function()
  after_each(helpers.cleanup)

  it("creates a missing note from its template", function()
    local vault = helpers.setup({
      ["Templates/Daily.md"] = "# {{title}}\n\n{{date:YYYY-MM-DD}}\n",
    }, {
      ["templates.json"] = { folder = "Templates" },
      ["daily-notes.json"] = { folder = "", format = "YYYY-MM-DD", template = "Daily" },
    })
    local time = date.of(2024, 3, 13)
    journal.open("2024-03-13.md", "Daily", { time = time, title = "2024-03-13" })
    assert.equals("# 2024-03-13\n\n2024-03-13\n", helpers.read(vault, "2024-03-13.md"))
  end)

  it("does not overwrite a note that already exists", function()
    local vault = helpers.setup({ ["2024-03-13.md"] = "my own notes\n" }, { ["app.json"] = {} })
    journal.open("2024-03-13.md", nil, {})
    assert.equals("my own notes\n", helpers.read(vault, "2024-03-13.md"))
  end)

  it("adds a newly created note to the index", function()
    helpers.setup({}, { ["app.json"] = {} })
    journal.open("2024-03-13.md", nil, {})
    assert.equals("2024-03-13.md", require("knapp.index").resolve("2024-03-13"))
  end)
end)

describe("journal.month_dailies", function()
  after_each(helpers.cleanup)

  it("reports only the days that already have a note", function()
    helpers.setup({
      ["2024-03-01.md"] = "",
      ["2024-03-15.md"] = "",
      ["2024-04-02.md"] = "",
    }, { ["daily-notes.json"] = { folder = "", format = "YYYY-MM-DD" } })
    local found = journal.month_dailies(2024, 3)
    assert.same({ "2024-03-01.md", "2024-03-15.md" }, { found[1], found[15] })
    assert.is_nil(found[2])
    assert.is_nil(found[31])
  end)
end)
