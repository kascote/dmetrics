.DEFAULT_GOAL := help

.PHONY: help check self test testf lint lintf format formatf doc build install clean

# Where `make install` puts the binary; override with e.g. `make install PREFIX=/usr/local`.
PREFIX ?= $(HOME)/.local
BIN     = build/dmetrics

# Fixture files under test/**/fixtures are metric inputs; some are deliberately
# unparseable, so a tree-wide `dart format .` fails. Format everything else.
FORMAT_PATHS = lib bin $(shell find test -name '*.dart' -not -path '*/fixtures/*')

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

check: ## Lint, verify formatting, run all tests, check code metrics (what CI runs)
	dart analyze
	dart format --output=none --set-exit-if-changed $(FORMAT_PATHS)
	dart test -r failures-only
	dart run bin/dmetrics.dart analyze lib bin

self: ## Measure dmetrics with itself (stats over lib)
	dart run bin/dmetrics.dart stats lib

test: ## Run all tests
	dart test -r failures-only

testf: ## Run tests in a specific file (usage: make testf FILE=test/report/stats_test.dart)
	dart test -r failures-only $(FILE)

lint: ## Run static analysis
	dart analyze

lintf: ## Run static analysis on a specific file (usage: make lintf FILE=lib/src/report/stats.dart)
	dart analyze $(FILE)

format: ## Format all Dart files except fixtures
	dart format $(FORMAT_PATHS)

formatf: ## Format a specific Dart file (usage: make formatf FILE=lib/src/report/stats.dart)
	dart format $(FILE)

doc: ## Generate documentation
	dart doc

build: ## Compile the dmetrics executable to build/dmetrics
	dart pub get
	mkdir -p build
	dart compile exe -o $(BIN) bin/dmetrics.dart

install: build ## Build, then install the binary to $(PREFIX)/bin (default ~/.local/bin)
	install -d $(PREFIX)/bin
	install -m 755 $(BIN) $(PREFIX)/bin/dmetrics
	@echo 'Installed dmetrics to $(PREFIX)/bin/dmetrics'

clean: ## Remove build output
	rm -rf build
