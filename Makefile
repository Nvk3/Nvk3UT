.PHONY: bootstrap lint format:check format:fix quality:check

STYLUA ?= stylua
LUACHECK ?= luacheck
PROJECT_ROOT := $(CURDIR)

bootstrap:
./scripts/ensure-quality.sh --bootstrap-only

lint:
$(LUACHECK) $(PROJECT_ROOT)

format:check:
$(STYLUA) --config-path $(PROJECT_ROOT)/stylua.toml --check $(PROJECT_ROOT)

format:fix:
$(STYLUA) --config-path $(PROJECT_ROOT)/stylua.toml $(PROJECT_ROOT)

quality:check: format:check lint
