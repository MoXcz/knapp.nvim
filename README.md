# knapp.nvim

> [!WARNING]
> This plugin was made with extensive use of AI for my specific use-case for a
> Neovim-Obsidian setup, so if you wish to work with it please bear that in mind.

Work an [Obsidian](https://obsidian.md) vault from within Neovim: a link index that keeps backlinks
correct when notes move, Obsidian-compatible daily/weekly/zettel notes,
a command palette, and a readable-width live-preview view.

[Knapping](https://en.wikipedia.org/wiki/Knapping) is the craft of shaping obsidian by striking flakes off it. That is
roughly what this does to a vault.

Requires Neovim 0.11+ and a vault created by Obsidian: every folder, filename
format and template comes from `<vault>/.obsidian/*.json`, so Obsidian stays the
single source of truth and nothing is configured twice.

## Install

With `vim.pack` (Neovim 0.12+):

```lua
vim.pack.add({
  { src = "https://github.com/MoXcz/knapp.nvim", version = vim.version.range("^0.1") },
})

require("knapp").setup({
  vault = "~/notes", -- required
})
```

> Omit `version` to track `main`.

With lazy.nvim:

```lua
{ "MoXcz/knapp.nvim", opts = { vault = "~/notes" } }
```

`snacks.nvim` is optional; when present its picker backs the palette, note
finder and vault grep. Everything falls back to `vim.ui.select`.

Run `:checkhealth knapp` after setup. Nearly everything knapp does is derived
from `<vault>/.obsidian/*.json`, so when a note lands in the wrong folder the
report names the file that is missing or malformed.

## What it does

**Link index.** One pass over the vault builds name -> file and file ->
backlinks maps, cached and mtime-checked (~450ms cold, ~85ms warm on 3.6k
notes). Understands `[[note]]`, `[[note|alias]]`, `[[note#heading]]`,
`[[note#^block]]`, `![[embed]]` and `[text](note%20name.md)`, resolves bare
names the way Obsidian does (closest file wins), reads `aliases:` frontmatter,
and ignores links inside fenced blocks and inline code.

This also means that renaming, moving or merging notes also rewrites all links
that pointes to it. Bare-name links stay bare while the name is unambiguous,
path-style links get repathed, and links that went through an alias are left
alone because the alias still resolves. Notes with unsaved changes are never
touched silently - they are reported instead.

**Merge.** Appends the whole note to another, repoints the backlinks and moves
the original to the vault's `.trash`.

**Journal.** Daily, weekly and zettel-prefixed notes using the folders, date
formats and templates from Obsidian's own settings, including a moment-style
formatter (`YYYY-[W]ww`, `Y-MM-DD dddd`, ...) and template placeholders
(`{{title}}`, `{{date:FMT}}`, `{{date+6d:FMT}}`).

**Calendar.** A month grid marking the days that already have a note. `<CR>`
opens that day, `W` opens the week.

**Backlinks pane.** Opens with the note, refreshes as you move between notes,
one row per linking note with an occurrence count.

**Readable width.** Neovim soft-wraps at the window edge and has no wrap-at-
column option, so the note window is narrowed to `wrap.width` and the leftover
space is filled with an inert padding window that window motions skip over.

## Keymaps

Buffer-local inside the vault, all under `keys.prefix` (default `<leader>o`):

| Key                         | Action                                                                      |
| --------------------------- | --------------------------------------------------------------------------- |
| `gf`                        | follow link, jump to `#heading` / `#^block`, offer to create a missing note |
| `<C-p>`                     | command palette                                                             |
| `<prefix>b` `i` `c` `l` `h` | bold, italics, code, wikilink, highlight (toggles)                          |
| `<prefix>r` `m` `M`         | rename, move, merge                                                         |
| `<prefix>B` `Q`             | backlinks pane, backlinks in quickfix                                       |
| `<prefix>n` `f` `g` `t`     | new note, find notes, grep vault, insert template                           |
| `<prefix>R` `W`             | rebuild index, toggle readable width                                        |

Global, since a journal note is often opened from outside the vault:
`<prefix>d` today, `<prefix>y` yesterday, `<prefix>w` this week, `<prefix>z`
new fleeting note, `<prefix>C` calendar.

Insert mode gets `<C-b>` bold and `<C-l>` wikilink. `<C-i>` italics is opt-in
(`keys.swap_ci`): terminals send `<C-i>` as `<Tab>`, so it only works under the
kitty keyboard protocol, and it also maps `<C-k>` to jumplist-forward.

`:Knapp <subcommand>` covers the same ground with completion: `palette`,
`rename`, `move`, `merge`, `backlinks`, `follow`, `new`, `find`, `grep`,
`index`, `daily [offset]`, `weekly [offset]`, `zettel`, `calendar`,
`template`, `pane`, `width`.

## Configuration

Defaults:

```lua
require("knapp").setup({
  vault = nil, -- required
  ignore = { ".obsidian", ".trash", ".git", ".stfolder" },
  keys = {
    enabled = true,
    prefix = "<leader>o",
    palette = "<C-p>",
    insert = true,   -- insert-mode <C-b> / <C-l>
    swap_ci = false, -- <C-i> italics + <C-k> jump forward (kitty only)
  },
  wrap = {
    enabled = true,
    width = 120,
    pad = true,                  -- false: wrap at the window edge
    min_pad = 4,
    display_line_motions = true, -- j/k walk display lines
  },
  backlinks = {
    auto = true,
    position = "bottom", -- "bottom" | "top" | "left" | "right"
    width = 40,          -- "left"/"right"
    height = 10,         -- "top"/"bottom"
  },
  -- 'sessionoptions' contains "blank", which stores the plugin's scratch
  -- windows in sessions and brings them back empty after :restart
  fix_sessionoptions = true,
  cache = vim.fn.stdpath("cache") .. "/knapp",
})
```

## Development

```sh
make deps    # install busted into ./.luarocks (nothing touches your home dir)
make tools   # download selene into ./.tools
make test    # run the suite
make bench   # time the index against a synthetic vault
make lint    # stylua --check and selene
make help    # everything else
```

Specs run inside Neovim via `nvim -l`, so they get the real `vim` API with no
stubbing. `make test BUSTED_ARGS=tests/link_spec.lua` runs one file.

`:checkhealth knapp` reports the config, the `.obsidian` files knapp reads, and
the index state.

## Rendering

knapp does not render markdown, images or math itself. It pairs with
[render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim)
for live preview and `snacks.image` for images and LaTeX. snacks already
resolves Obsidian's `![[embed]]` syntax; point it at the vault index so bare
filenames resolve from anywhere:

```lua
image = {
  enabled = true,
  resolve = function(file, src)
    local ok, config = pcall(require, "knapp.config")
    if not ok or not config.in_vault(file) then return nil end
    local index = require("knapp.index")
    index.ensure()
    return index.resolve_file(require("knapp.link").decode(src), config.rel(file))
  end,
}
```
