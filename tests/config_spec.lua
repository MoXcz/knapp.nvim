local helpers = require("helpers")
local config = require("knapp.config")

describe("config.setup", function()
  after_each(helpers.cleanup)

  it("rejects a missing vault", function()
    assert.has_error(function() config.setup({}) end)
    assert.has_error(function() config.setup({ vault = "" }) end)
  end)

  it("expands and normalises the vault path", function()
    local vault = helpers.vault({})
    config.setup({ vault = vault .. "/" })
    assert.equals(vim.fs.normalize(vault), config.opts.vault)
  end)

  it("merges user options over the defaults", function()
    config.setup({ vault = helpers.vault({}), wrap = { width = 80 } })
    assert.equals(80, config.opts.wrap.width)
    -- untouched sibling keys survive the merge
    assert.equals(true, config.opts.wrap.enabled)
    assert.equals(4, config.opts.wrap.min_pad)
  end)

  it("does not let one setup() leak into the next", function()
    config.setup({ vault = helpers.vault({}), wrap = { width = 80 } })
    config.setup({ vault = helpers.vault({}) })
    assert.equals(120, config.opts.wrap.width)
  end)
end)

describe("config paths", function()
  local vault

  before_each(function()
    vault = helpers.vault({})
    config.setup({ vault = vault })
  end)
  after_each(helpers.cleanup)

  it("recognises paths inside the vault", function()
    assert.is_true(config.in_vault(vault))
    assert.is_true(config.in_vault(vim.fs.joinpath(vault, "note.md")))
    assert.is_true(config.in_vault(vim.fs.joinpath(vault, "deep/folder/note.md")))
  end)

  it("rejects paths outside the vault", function()
    assert.is_false(config.in_vault("/etc/passwd"))
    assert.is_false(config.in_vault(""))
    assert.is_false(config.in_vault(nil))
  end)

  it(
    "does not match a sibling directory with the same prefix",
    function() assert.is_false(config.in_vault(vault .. "-other/note.md")) end
  )

  it("round-trips rel and abs", function()
    local rel = "folder/note.md"
    assert.equals(rel, config.rel(config.abs(rel)))
  end)

  it("maps the vault root to an empty relative path", function() assert.equals("", config.rel(vault)) end)
end)

describe("documented defaults", function()
  -- The README's defaults block drifted from config.defaults once already
  -- (`backlinks.position` was documented as "bottom" while the code used
  -- "right"). Rather than trust proofreading, execute the block and compare.

  --- The `setup{...}` table from the ```lua block under "Defaults:" in README.md.
  local function readme_defaults()
    local readme = assert(require("knapp.util").read_file("README.md"), "README.md not readable")
    local block = readme:match("Defaults:%s*\n```lua\n(.-)```")
    assert.is_not_nil(block, "could not find the defaults block in README.md")

    local captured
    -- the block needs `vim` for the cache default and nothing else
    local env = {
      vim = vim,
      require = function()
        return {
          setup = function(opts) captured = opts end,
        }
      end,
    }

    local chunk = assert(loadstring(block, "README.md defaults"))
    setfenv(chunk, env)
    chunk()
    return captured
  end

  it("match config.defaults", function()
    local documented = readme_defaults()
    local actual = vim.deepcopy(require("knapp.config").defaults)
    -- `vault` has no default; the README shows it as `nil` to mark it required.
    documented.vault, actual.vault = nil, nil
    -- tests/bootstrap.lua redirects the cache away from the real one, so it is
    -- checked separately below rather than against the live default.
    documented.cache, actual.cache = nil, nil
    assert.same(actual, documented)
  end)

  it(
    "document the same cache path config.lua computes",
    function() assert.equals(vim.fs.joinpath(vim.fn.stdpath("cache"), "knapp"), readme_defaults().cache) end
  )
end)
