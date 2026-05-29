NVIM ?= nvim
STYLUA ?= stylua

.PHONY: test lint format

test:
	$(NVIM) --headless -u NONE --cmd "set rtp^=." -c "lua dofile('tests/packui_native_ui_spec.lua')" -c "qa"

lint:
	$(STYLUA) --check lua tests

format:
	$(STYLUA) lua tests
