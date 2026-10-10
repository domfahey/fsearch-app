# Developer tasks for FSearch. Run `make help`.
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

# Set LINT_FORMAT=0 to skip the swift-format check in `make lint`.
LINT_FORMAT ?= 1
SWIFT_DIRS := App AppUITests Packages/FSearchKit/Sources Packages/FSearchKit/Tests
FORMAT_CFG := --configuration .swift-format
XCODEBUILD := xcodebuild -project FSearch.xcodeproj -scheme FSearch -configuration Debug \
	-derivedDataPath build -destination 'generic/platform=macOS' CODE_SIGN_IDENTITY=-

.DEFAULT_GOAL := help
.PHONY: help daemon project build test ui coverage bench format lint type check

help: ## List targets
	@echo "FSearch developer tasks:"
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | sed -E 's/^([a-z-]+):.*## (.*)/  make \1\t\2/'
	@echo ""
	@echo "Note: 'make lint' fails on formatting until formatting is applied;"
	@echo "use LINT_FORMAT=0 make lint to skip the swift-format check."

daemon: ## Build the universal fsearch daemon into Vendor/
	scripts/build-daemon.sh

project: ## Generate FSearch.xcodeproj with XcodeGen
	xcodegen generate

build: project ## Build the universal Debug app (same as CI)
	$(XCODEBUILD) build

test: ## Run FSearchKit tests (needs Vendor/fsearch)
	cd Packages/FSearchKit && swift test

ui: ## Run the panel UI smoke test (needs a GUI session)
	scripts/ui-smoke.sh

coverage: ## FSearchKit coverage report (llvm-cov)
	@if [ -x scripts/coverage.sh ]; then scripts/coverage.sh; else \
	cd Packages/FSearchKit && swift test --enable-code-coverage && \
	xcrun llvm-cov report "$$(find .build -name FSearchKitPackageTests.xctest -path '*debug*' | head -1)/Contents/MacOS/FSearchKitPackageTests" \
		-instr-profile=.build/debug/codecov/default.profdata -ignore-filename-regex='Tests/|\.build/'; fi

bench: ## Run the benchmarks
	scripts/bench.sh

format: ## Format Swift sources in place
	xcrun swift format format $(FORMAT_CFG) --in-place -r $(SWIFT_DIRS)

lint: ## Lint Swift format (LINT_FORMAT=0 skips), credits, shell scripts
	@set -e; \
	if [ "$(LINT_FORMAT)" = "0" ]; then echo "skipping swift-format check (LINT_FORMAT=0)"; \
	else xcrun swift format lint --strict $(FORMAT_CFG) -r $(SWIFT_DIRS); fi; \
	scripts/gen-credits.sh --check; \
	for f in scripts/*.sh; do bash -n "$$f"; done; \
	if command -v shellcheck >/dev/null; then shellcheck -S warning scripts/*.sh; else echo "shellcheck not installed; skipped"; fi; \
	if command -v actionlint >/dev/null; then actionlint; else echo "actionlint not installed; skipped"; fi

type: project ## Warnings-as-errors package build, plus app warnings check
	cd Packages/FSearchKit && swift build --build-tests -Xswiftc -warnings-as-errors
	@mkdir -p build
	$(XCODEBUILD) build-for-testing > build/type.log 2>&1 || { tail -40 build/type.log; exit 1; }
	@if grep -E '(App|AppTests|AppUITests|Packages)/.*warning:' build/type.log | sort -u | grep .; then \
		echo "type: warnings in project sources"; exit 1; fi
	@echo "type: ok"

check: lint type test ## lint, type, test

.PHONY: hooks
hooks: ## Install the repo git hooks (secret checks)
	git config core.hooksPath scripts/hooks
