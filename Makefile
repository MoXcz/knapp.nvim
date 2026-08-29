# Development tasks. Dependencies land in repo-local .luarocks and .tools
# directories, so nothing is installed into your home directory or your system.

LUA_VERSION := 5.1
TREE        := .luarocks
TOOLS       := .tools
BUSTED      := $(wildcard $(TREE)/lib/luarocks/rocks-$(LUA_VERSION)/busted/*/bin/busted)
LUAROCKS    := luarocks --tree $(TREE) --lua-version $(LUA_VERSION)
SELENE      := $(shell command -v selene 2>/dev/null || echo $(TOOLS)/selene)
SELENE_VER  := 0.31.0

.PHONY: all test bench lint format typecheck deps tools docs clean help

help:
	@echo "make deps       install busted into ./$(TREE)"
	@echo "make tools      download selene into ./$(TOOLS)"
	@echo "make docs       regenerate doc/ from README.md with panvimdoc"
	@echo "make test       run the test suite"
	@echo "make bench      time the index against a synthetic vault"
	@echo "make lint       stylua --check and selene"
	@echo "make format     rewrite files with stylua"
	@echo "make typecheck  lua-language-server against .luarc.json"
	@echo "make clean      remove ./$(TREE), ./$(TOOLS) and generated doc tags"

all: lint test

deps:
	$(LUAROCKS) --lua-dir=/usr install busted

tools:
	@mkdir -p $(TOOLS)
	curl -sL -o /tmp/selene.zip \
		https://github.com/Kampfkarren/selene/releases/download/$(SELENE_VER)/selene-$(SELENE_VER)-linux.zip
	unzip -oq /tmp/selene.zip -d $(TOOLS) && chmod +x $(TOOLS)/selene

# doc/ is generated from README.md; CI does this on every push that touches
# the README (.github/workflows/panvimdoc.yml). This target is for checking the
# result before pushing. Requires pandoc.
docs:
	@test -d $(TOOLS)/panvimdoc || git clone -q --depth 1 https://github.com/kdheepak/panvimdoc.git $(TOOLS)/panvimdoc
	bash $(TOOLS)/panvimdoc/panvimdoc.sh \
		--project-name knapp.nvim --input-file README.md --vim-version "Neovim >= 0.11"
	@awk 'length > 79 { print FILENAME":"NR" is "length" columns" }' doc/*.txt || true

# Specs run inside Neovim so they get the real `vim` API. busted's own
# launcher is a /bin/sh wrapper, so invoke the Lua entrypoint it wraps.
test:
	@test -n "$(BUSTED)" || { echo "busted not installed - run: make deps"; exit 1; }
	@eval "$$($(LUAROCKS) path)" && nvim -l $(BUSTED) $(BUSTED_ARGS)

bench:
	nvim -l scripts/bench.lua

# `cmd || echo` would make this target succeed even when the linter reports
# violations, which is worse than not running it at all: it reads as green.
# A missing tool warns; a tool that finds something fails.
lint:
	@if command -v stylua >/dev/null; then stylua --check lua tests; \
	else echo "stylua not installed, skipping"; fi
	@if test -x "$(SELENE)"; then $(SELENE) lua tests; \
	else echo "selene not installed - run: make tools"; fi

format:
	stylua lua tests

typecheck:
	lua-language-server --check lua --checklevel=Warning --configpath=../.luarc.json

clean:
	rm -rf $(TREE) $(TOOLS) doc/tags
