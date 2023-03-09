.PHONY: test clean

UNAME := $(shell uname)
ifeq ($(UNAME),Darwin)
	NVIM_RELEASE := "https://github.com/neovim/neovim/releases/download/stable/nvim-macos.tar.gz"
else
	NVIM_RELEASE := "https://github.com/neovim/neovim/releases/download/stable/nvim-linux64.tar.gz"
endif

.EXPORT_ALL_VARIABLES:

XDG_CONFIG_HOME = ./tests/nvim/config
XDG_DATA_HOME = ./tests/nvim/share
XDG_STATE_HOME = ./tests/nvim/state

test: _neovim deps/plenary.nvim deps/nvim-treesitter deps/nvim-treesitter/parser/java.so deps/neotest
	bash ./scripts/test

_neovim:
	mkdir -p _neovim
	curl -sL $(NVIM_RELEASE) | tar xzf - --strip-components=1 -C "${PWD}/_neovim"

deps/plenary.nvim:
	mkdir -p deps
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim.git $@

deps/nvim-treesitter:
	mkdir -p deps
	git clone --depth 1 https://github.com/nvim-treesitter/nvim-treesitter.git $@

deps/nvim-treesitter/parser/java.so: deps/nvim-treesitter
	nvim --headless -u tests/nvim/config/minimal_init.vim -c "TSInstallSync java | quit"

deps/neotest:
	mkdir -p deps
	git clone --depth 1 https://github.com/nvim-neotest/neotest $@

clean:
	rm -rf deps/ _neovim/
