local date = require("knapp.date")

-- Fixed points, all at midday so a DST shift cannot move them across a day.
local WED = date.of(2024, 3, 13) -- Wednesday 13 March 2024
local SUN = date.of(2024, 3, 17) -- Sunday
local MON = date.of(2024, 3, 11) -- Monday

describe("date.format", function()
  it("formats the year, month and day", function()
    assert.equals("2024-03-13", date.format("YYYY-MM-DD", WED))
    assert.equals("24", date.format("YY", WED))
  end)

  it("formats month and weekday names", function()
    assert.equals("March", date.format("MMMM", WED))
    assert.equals("Mar", date.format("MMM", WED))
    assert.equals("Wednesday", date.format("dddd", WED))
    assert.equals("Wed", date.format("ddd", WED))
  end)

  it("formats unpadded tokens", function()
    assert.equals("2024-3-13", date.format("Y-M-D", WED))
    assert.equals("3", date.format("M", date.of(2024, 3, 1)))
  end)

  it("takes the longest matching token first", function()
    -- "MMMM" must not be read as four "M"s
    assert.equals("March", date.format("MMMM", WED))
    assert.equals("2024", date.format("YYYY", WED))
  end)

  it("treats [bracketed] text as literal", function()
    assert.equals("2024-W11", date.format("gggg-[W]WW", WED))
    assert.equals("YYYY", date.format("[YYYY]", WED))
  end)

  it("leaves an unclosed bracket alone", function() assert.equals("[2024", date.format("[YYYY", WED)) end)

  it(
    "passes through characters that are not tokens",
    function() assert.equals("2024/03/13", date.format("YYYY/MM/DD", WED)) end
  )

  it("formats the ISO week", function()
    assert.equals("11", date.format("WW", WED))
    assert.equals("11", date.format("W", WED))
  end)

  it("defaults to now when given no time", function() assert.equals(os.date("%Y"), date.format("YYYY")) end)
end)

describe("date.week_start", function()
  it("walks back to Monday by default", function()
    assert.equals("2024-03-11", date.format("YYYY-MM-DD", date.week_start(WED)))
    assert.equals("2024-03-11", date.format("YYYY-MM-DD", date.week_start(SUN)))
  end)

  it(
    "leaves a Monday alone",
    function() assert.equals("2024-03-11", date.format("YYYY-MM-DD", date.week_start(MON))) end
  )

  it("walks back to Sunday when asked", function()
    assert.equals("2024-03-10", date.format("YYYY-MM-DD", date.week_start(WED, "sunday")))
    assert.equals("2024-03-17", date.format("YYYY-MM-DD", date.week_start(SUN, "sunday")))
  end)

  it("crosses a month boundary", function()
    -- Sunday 3 March 2024 belongs to the week starting Monday 26 February
    assert.equals("2024-02-26", date.format("YYYY-MM-DD", date.week_start(date.of(2024, 3, 3))))
  end)

  it("crosses a year boundary", function()
    -- Wednesday 1 January 2025 belongs to the week starting Monday 30 December 2024
    assert.equals("2024-12-30", date.format("YYYY-MM-DD", date.week_start(date.of(2025, 1, 1))))
  end)
end)

describe("date.shift", function()
  it("shifts days", function()
    assert.equals("2024-03-14", date.format("YYYY-MM-DD", date.shift(WED, 1, "d")))
    assert.equals("2024-03-12", date.format("YYYY-MM-DD", date.shift(WED, -1, "d")))
  end)

  it("shifts weeks", function() assert.equals("2024-03-20", date.format("YYYY-MM-DD", date.shift(WED, 1, "w"))) end)

  it("shifts months and years", function()
    assert.equals("2024-04-13", date.format("YYYY-MM-DD", date.shift(WED, 1, "M")))
    assert.equals("2025-03-13", date.format("YYYY-MM-DD", date.shift(WED, 1, "y")))
  end)

  it(
    "normalises across a month end",
    function() assert.equals("2024-04-01", date.format("YYYY-MM-DD", date.shift(date.of(2024, 3, 31), 1, "d"))) end
  )

  it(
    "handles a leap day",
    function() assert.equals("2024-02-29", date.format("YYYY-MM-DD", date.shift(date.of(2024, 2, 28), 1, "d"))) end
  )

  it("is a no-op for an unknown unit", function() assert.equals(WED, date.shift(WED, 5, "q")) end)
end)

describe("date.parse_offset", function()
  it("parses a signed offset", function()
    assert.same({ 6, "d" }, { date.parse_offset("+6d") })
    assert.same({ -2, "w" }, { date.parse_offset("-2w") })
    assert.same({ 1, "M" }, { date.parse_offset("+1M") })
    assert.same({ 3, "y" }, { date.parse_offset("+3y") })
  end)

  it("returns nil for anything else", function()
    assert.is_nil(date.parse_offset(""))
    assert.is_nil(date.parse_offset("6d"))
    assert.is_nil(date.parse_offset("+6"))
    assert.is_nil(date.parse_offset("+6x"))
  end)
end)

describe("date.of", function()
  it("builds a midday timestamp", function() assert.equals("12", os.date("%H", date.of(2024, 3, 13))) end)

  it("normalises an out-of-range day into the previous month", function()
    -- day 0 of month N+1 is the last day of month N; used by the calendar
    assert.equals("2024-02-29", date.format("YYYY-MM-DD", date.of(2024, 3, 0)))
  end)
end)
