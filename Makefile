# Developer tasks for FSearch. Run `make help`.
# Works with macOS's /usr/bin/make (GNU Make 3.81): no .ONESHELL, no $(file).
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables --no-builtin-rules

# The selected Xcode (xcode-select -s), unless DEVELOPER_DIR is already set.
export DEVELOPER_DIR ?= $(shell xcode-select -p)

# V=1 echoes every command. OPTIONAL=1 also installs the optional lint tools.
V ?= 0
OPTIONAL ?= 0
# Set LINT_FORMAT=0 to skip the swift-format check in `make lint`.
LINT_FORMAT ?= 1
ifeq ($(V),1)
Q :=
else
Q := @
endif

SWIFT_DIRS ?= App AppTests AppUITests Packages/FSearchKit/Sources Packages/FSearchKit/Tests
FORMAT_CFG ?= --configuration .swift-format
RUST_TARGETS ?= aarch64-apple-darwin x86_64-apple-darwin
XCODEBUILD ?= xcodebuild -project FSearch.xcodeproj -scheme FSearch -configuration Debug \
	-derivedDataPath build -destination 'generic/platform=macOS' CODE_SIGN_IDENTITY=-

.DEFAULT_GOAL := help
.PHONY: help install install-tools setup doctor daemon project build test ui coverage bench \
	format format-check lint type check ci hooks clean distclean

help: ## List targets
	@echo "FSearch developer tasks:"
	@awk 'BEGIN { FS = ":.*## " } /^[a-zA-Z_-]+:.*## / { printf "  make %-13s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""
	@echo "V=1 make <target> echoes commands. OPTIONAL=1 make install adds shellcheck and actionlint."
	@echo "LINT_FORMAT=0 make lint skips the swift-format check."

install: install-tools hooks doctor ## Install DEVELOPER prerequisites (xcodegen, rust targets, hooks); NOT the app

install-tools:
	@echo "Installing developer tools only. This does not install the FSearch app."
	$(Q)if command -v xcodegen >/dev/null; then echo "xcodegen: present"; \
	elif command -v brew >/dev/null; then brew install xcodegen; \
	else echo "Homebrew is missing. Install it from https://brew.sh, then run: brew install xcodegen" >&2; exit 1; fi
	$(Q)if command -v rustup >/dev/null; then rustup target add $(RUST_TARGETS); \
	else echo "rustup is missing. Install it from https://rustup.rs, then re-run make install" >&2; exit 1; fi
	$(Q)if [ "$(OPTIONAL)" = "1" ]; then \
		if command -v brew >/dev/null; then \
			for t in shellcheck actionlint; do \
				if command -v $$t >/dev/null; then echo "$$t: present"; else brew install $$t; fi; \
			done; \
		else echo "Homebrew is missing; skipping optional shellcheck and actionlint" >&2; fi; \
	else echo "optional tools skipped (OPTIONAL=1 make install adds shellcheck and actionlint)"; fi

setup: install ## Alias for install

doctor: ## Check developer prerequisites; non-zero if a required one is missing
	$(Q)fail=0; \
	ok()   { printf '  \342\234\223 %s\n' "$$1"; }; \
	bad()  { printf '  \342\234\227 %s\n      fix: %s\n' "$$1" "$$2"; fail=1; }; \
	opt()  { if command -v "$$1" >/dev/null 2>&1; then ok "$$1 (optional)"; \
	         else printf '  - %s not installed (optional)\n      fix: %s\n' "$$1" "$$2"; fi; }; \
	echo "FSearch doctor:"; \
	osv=$$(sw_vers -productVersion 2>/dev/null || echo 0); \
	if [ "$${osv%%.*}" -ge 14 ]; then ok "macOS $$osv (>= 14)"; else bad "macOS $$osv (need >= 14)" "update macOS"; fi; \
	if xp=$$(xcode-select -p 2>/dev/null) && [ -d "$$xp" ]; then ok "developer dir $$xp"; \
	else bad "no Xcode selected" "install Xcode, then sudo xcode-select -s /Applications/Xcode.app"; fi; \
	xv=$$(xcodebuild -version 2>/dev/null | awk 'NR==1 { print $$2 }'); \
	if [ -n "$$xv" ] && [ "$${xv%%.*}" -ge 16 ]; then ok "Xcode $$xv (>= 16)"; \
	else bad "Xcode $${xv:-not usable} (need >= 16)" "install Xcode 16+ and sudo xcode-select -s /Applications/Xcode.app; sudo xcodebuild -license accept"; fi; \
	sv=$$(swift --version 2>&1 | sed -n 's/.*Swift version \([0-9][0-9]*\).*/\1/p' | head -1); \
	if [ -n "$$sv" ] && [ "$$sv" -ge 6 ]; then ok "Swift $$sv"; else bad "Swift $${sv:-not found} (need 6)" "install Xcode 16+"; fi; \
	if xcrun swift format --version >/dev/null 2>&1; then ok "swift-format"; else bad "swift-format not available" "use Xcode 16+ (xcrun swift format)"; fi; \
	if command -v rustup >/dev/null 2>&1; then ok "rustup"; else bad "rustup missing" "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"; fi; \
	if command -v cargo >/dev/null 2>&1; then ok "cargo"; else bad "cargo missing" "install rustup (see above)"; fi; \
	installed=$$(rustup target list --installed 2>/dev/null || true); \
	for t in $(RUST_TARGETS); do \
		if printf '%s\n' "$$installed" | grep -qx "$$t"; then ok "rust target $$t"; \
		else bad "rust target $$t missing" "rustup target add $$t"; fi; \
	done; \
	if command -v xcodegen >/dev/null 2>&1; then ok "xcodegen"; else bad "xcodegen missing" "brew install xcodegen"; fi; \
	hp=$$(git config core.hooksPath || true); \
	if [ "$$hp" = "scripts/hooks" ]; then ok "git hooks installed"; else bad "git hooks not installed" "make hooks"; fi; \
	if [ -x Vendor/fsearch ]; then \
		archs=$$(lipo -archs Vendor/fsearch 2>/dev/null || true); \
		if printf '%s\n' "$$archs" | grep -q arm64 && printf '%s\n' "$$archs" | grep -q x86_64; then ok "Vendor/fsearch universal ($$archs)"; \
		else bad "Vendor/fsearch is not universal ($${archs:-unreadable})" "make daemon"; fi; \
		want=$$(grep -m1 '^REV=' scripts/build-daemon.sh | grep -o '[0-9a-f]\{40\}' || true); \
		have=$$(cat Vendor/fsearch.rev 2>/dev/null || true); \
		if [ -n "$$want" ] && [ -n "$$have" ]; then case "$$want" in "$$have"*) ;; *) bad "Vendor/fsearch is not the pinned revision" "make daemon" ;; esac; fi; \
	else bad "Vendor/fsearch not built" "make daemon"; fi; \
	opt shellcheck "brew install shellcheck"; \
	opt actionlint "brew install actionlint"; \
	opt gh "brew install gh"; \
	if [ $$fail -eq 0 ]; then echo "All required prerequisites present."; else echo "Missing required prerequisites; see fixes above." >&2; fi; \
	exit $$fail

Vendor/fsearch:
	scripts/build-daemon.sh

daemon: ## Rebuild the universal fsearch daemon into Vendor/ (pinned revision)
	scripts/build-daemon.sh

project: ## Generate FSearch.xcodeproj with XcodeGen
	$(Q)xcodegen generate

build: project ## Build the universal Debug app (same as CI)
	$(Q)$(XCODEBUILD) build

test: Vendor/fsearch ## Run FSearchKit tests (builds Vendor/fsearch if missing)
	$(Q)cd Packages/FSearchKit && swift test

ui: Vendor/fsearch ## End-to-end UI tests; needs an idle logged-in GUI session
	$(Q)scripts/ui-smoke.sh

coverage: Vendor/fsearch ## Coverage report for FSearchKit and both app suites (UI tests need a GUI session)
	$(Q)scripts/coverage.sh

bench: Vendor/fsearch ## Run the benchmarks
	$(Q)scripts/bench.sh

format: ## Format Swift sources in place
	$(Q)xcrun swift format format $(FORMAT_CFG) --in-place -r $(SWIFT_DIRS)

format-check: ## Check Swift formatting only (no changes)
	$(Q)xcrun swift format lint --strict $(FORMAT_CFG) -r $(SWIFT_DIRS)

lint: ## Lint swift-format (LINT_FORMAT=0 skips), links, credits, shell scripts, workflows
	$(Q)if [ "$(LINT_FORMAT)" = "0" ]; then echo "skipping swift-format check (LINT_FORMAT=0)"; \
	else xcrun swift format lint --strict $(FORMAT_CFG) -r $(SWIFT_DIRS); fi
	$(Q)scripts/check-links.sh
	$(Q)scripts/gen-credits.sh --check
	$(Q)for f in scripts/*.sh scripts/hooks/*; do bash -n "$$f"; done
	$(Q)if command -v shellcheck >/dev/null; then shellcheck -S warning scripts/*.sh; \
	else echo "shellcheck not installed; skipped (brew install shellcheck)"; fi
	$(Q)if command -v actionlint >/dev/null; then actionlint; \
	else echo "actionlint not installed; skipped (brew install actionlint)"; fi

type: project ## Warnings-as-errors package build, plus app warnings check
	$(Q)cd Packages/FSearchKit && swift build --build-tests -Xswiftc -warnings-as-errors
	$(Q)mkdir -p build
	$(Q)$(XCODEBUILD) build-for-testing > build/type.log 2>&1 || { tail -40 build/type.log; exit 1; }
	$(Q)w=$$(grep -E '(App|AppTests|AppUITests|Packages)/.*warning:' build/type.log | sort -u || true); \
	if [ -n "$$w" ]; then printf '%s\n' "$$w"; echo "type: warnings in project sources"; exit 1; fi
	@echo "type: ok"

check: lint type test ## lint, type, test

ci: check ## Run locally what CI runs: check plus the 90% kit and 80% app unit coverage gates
	$(Q)scripts/coverage.sh --kit-only --min 90
	$(Q)scripts/coverage.sh --unit-only --min 80

hooks: ## Install the repo git hooks (secret checks)
	$(Q)git config core.hooksPath scripts/hooks

clean: ## Remove build outputs (build/, .build, Packages/FSearchKit/.build)
	$(Q)rm -rf build .build Packages/FSearchKit/.build

distclean: clean ## clean, plus Vendor/fsearch and the generated FSearch.xcodeproj
	$(Q)rm -rf Vendor/fsearch Vendor/fsearch.rev FSearch.xcodeproj
