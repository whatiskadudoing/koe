# Koe Development Makefile
# macOS 14+, Swift 5.9+, Apple Silicon

.PHONY: all build build-release clean test format format-check lint lint-fix docs bundle
.PHONY: installer-build installer-lint installer-fmt installer-fmt-check
.PHONY: check ci setup help clean-install run restart dev

# Default target
all: help

#------------------------------------------------------------------------------
# Swift Development Commands
#------------------------------------------------------------------------------

## Build debug version
build:
	cd KoeApp && swift build

## Build release version
build-release:
	cd KoeApp && swift build -c release

## Clean build artifacts
clean:
	cd KoeApp && swift package clean
	rm -rf KoeApp/.build
	rm -rf KoeApp/dist
	@for pkg in Packages/*; do \
		if [ -d "$$pkg/.build" ]; then \
			rm -rf "$$pkg/.build"; \
		fi \
	done

## Run tests (all packages)
test:
	cd KoeApp && swift test

#------------------------------------------------------------------------------
# Development Workflow Commands
#------------------------------------------------------------------------------

## Run the app (requires bundle due to UNUserNotificationCenter)
run: bundle
	@echo "Starting Koe..."
	@open KoeApp/dist/Koe.app

## Restart: kill running app, rebuild bundle, and start (main dev workflow)
restart:
	@echo "=== Restarting Koe ==="
	@-pkill -f "Koe" 2>/dev/null || true
	@sleep 0.5
	@$(MAKE) bundle --no-print-directory 2>&1 | grep -E "(Building|Build complete|App bundle)"
	@echo "Starting Koe..."
	@open KoeApp/dist/Koe.app
	@sleep 2
	@pgrep -l Koe && echo "=== Koe restarted ===" || echo "Warning: Koe may not have started"

## Dev workflow: format, rebuild bundle, and restart
dev:
	@echo "=== Dev Workflow ==="
	@-pkill -f "Koe" 2>/dev/null || true
	@sleep 0.5
	@echo "Formatting..."
	@swift-format format --in-place --recursive KoeApp/Koe Packages 2>/dev/null || true
	@$(MAKE) bundle --no-print-directory 2>&1 | grep -E "(Building|Build complete|App bundle)"
	@echo "Starting Koe..."
	@open KoeApp/dist/Koe.app
	@sleep 2
	@pgrep -l Koe && echo "=== Dev cycle complete ===" || echo "Warning: Koe may not have started"

#------------------------------------------------------------------------------
# Code Quality Commands
#------------------------------------------------------------------------------

## Format Swift code using swift-format
format:
	@if command -v swift-format >/dev/null 2>&1; then \
		swift-format format --in-place --recursive KoeApp/Koe Packages; \
	else \
		echo "swift-format not found. Install with: brew install swift-format"; \
		exit 1; \
	fi

## Check Swift formatting (CI-friendly, no changes)
format-check:
	@if command -v swift-format >/dev/null 2>&1; then \
		swift-format lint --recursive KoeApp/Koe Packages; \
	else \
		echo "swift-format not found. Install with: brew install swift-format"; \
		exit 1; \
	fi

## Lint Swift code using SwiftLint
lint:
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint KoeApp/Koe Packages; \
	else \
		echo "SwiftLint not found. Install with: brew install swiftlint"; \
		exit 1; \
	fi

## Fix auto-correctable SwiftLint issues
lint-fix:
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint --fix KoeApp/Koe Packages; \
	else \
		echo "SwiftLint not found. Install with: brew install swiftlint"; \
		exit 1; \
	fi

#------------------------------------------------------------------------------
# Documentation
#------------------------------------------------------------------------------

## Generate documentation (requires swift-docc-plugin in Package.swift)
docs:
	cd KoeApp && swift package generate-documentation --target Koe

## Preview documentation in browser
docs-preview:
	cd KoeApp && swift package --disable-sandbox preview-documentation --target Koe

#------------------------------------------------------------------------------
# App Bundle
#------------------------------------------------------------------------------

## Create app bundle (release)
bundle: build-release
	@cd KoeApp && \
	rm -rf dist/Koe.app && \
	EXECUTABLE=$$(find .build -name "Koe" -type f -path "*release*" | grep -v dSYM | head -1) && \
	mkdir -p dist/Koe.app/Contents/MacOS && \
	mkdir -p dist/Koe.app/Contents/Resources && \
	mkdir -p dist/Koe.app/Contents/Frameworks && \
	cp "$$EXECUTABLE" dist/Koe.app/Contents/MacOS/Koe && \
	cp Koe/Info.plist dist/Koe.app/Contents/Info.plist && \
	/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string Koe" dist/Koe.app/Contents/Info.plist 2>/dev/null || \
	/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable Koe" dist/Koe.app/Contents/Info.plist && \
	echo -n "APPL????" > dist/Koe.app/Contents/PkgInfo && \
	chmod +x dist/Koe.app/Contents/MacOS/Koe && \
	if [ -d ".build/arm64-apple-macosx/release/llama.framework" ]; then \
		cp -R .build/arm64-apple-macosx/release/llama.framework dist/Koe.app/Contents/Frameworks/ && \
		install_name_tool -add_rpath @executable_path/../Frameworks dist/Koe.app/Contents/MacOS/Koe 2>/dev/null || true; \
	fi && \
	codesign --force --deep --sign - --identifier "com.koe.voice" --entitlements Koe.entitlements \
		--requirements '=designated => identifier "com.koe.voice"' dist/Koe.app && \
	echo "App bundle created at KoeApp/dist/Koe.app"

#------------------------------------------------------------------------------
# Installer Commands
#------------------------------------------------------------------------------

## Build Deno installer
installer-build:
	cd installer && deno task build:arm64

## Lint Deno installer
installer-lint:
	cd installer && deno lint

## Format Deno installer
installer-fmt:
	cd installer && deno fmt

## Check Deno installer formatting
installer-fmt-check:
	cd installer && deno fmt --check

#------------------------------------------------------------------------------
# Aggregate Commands
#------------------------------------------------------------------------------

## Run all checks (for CI)
check: format-check lint
	cd installer && deno lint && deno fmt --check

## Full CI pipeline
ci: check build-release

## Setup development environment
setup:
	@echo "Installing development tools..."
	@command -v swift-format >/dev/null 2>&1 || (echo "Installing swift-format..." && brew install swift-format)
	@command -v swiftlint >/dev/null 2>&1 || (echo "Installing swiftlint..." && brew install swiftlint)
	@command -v deno >/dev/null 2>&1 || (echo "Installing deno..." && brew install deno)
	@echo "Development tools installed successfully!"

#------------------------------------------------------------------------------
# Clean Install (Full Reset for Testing)
#------------------------------------------------------------------------------

## Remove ALL app data for fresh install testing (app, data, prefs, permissions)
clean-install:
	@echo "=== Koe Full Clean Install Reset ==="
	@echo ""
	@echo "Stopping Koe if running..."
	@-pkill -9 Koe 2>/dev/null || true
	@sleep 1
	@echo ""
	@echo "Removing app from /Applications..."
	@-rm -rf /Applications/Koe.app 2>/dev/null || true
	@echo ""
	@echo "Removing Application Support data..."
	@-rm -rf ~/Library/Application\ Support/Koe 2>/dev/null || true
	@echo ""
	@echo "Removing Caches..."
	@-rm -rf ~/Library/Caches/com.koe.voice 2>/dev/null || true
	@echo ""
	@echo "Removing Preferences (UserDefaults)..."
	@-defaults delete com.koe.voice 2>/dev/null || true
	@echo ""
	@echo "Removing Saved Application State..."
	@-rm -rf ~/Library/Saved\ Application\ State/com.koe.voice.savedState 2>/dev/null || true
	@echo ""
	@echo "Resetting TCC permissions (Accessibility, Microphone, Speech Recognition)..."
	@-tccutil reset Accessibility com.koe.voice 2>/dev/null || true
	@-tccutil reset Microphone com.koe.voice 2>/dev/null || true
	@-tccutil reset SpeechRecognition com.koe.voice 2>/dev/null || true
	@echo ""
	@echo "=== Clean complete! Ready for fresh install test ==="
	@echo ""
	@echo "To test installer, run:"
	@echo "  curl -fsSL https://raw.githubusercontent.com/anthropics/koe/main/install.sh | bash"

#------------------------------------------------------------------------------
# Help
#------------------------------------------------------------------------------

## Show this help
help:
	@echo "Koe Development Commands"
	@echo "========================"
	@echo ""
	@echo "Development Workflow:"
	@echo "  make run            Build and run the app"
	@echo "  make restart        Kill, rebuild, and restart (fast iteration)"
	@echo "  make dev            Format, rebuild, and restart"
	@echo ""
	@echo "Swift:"
	@echo "  make build          Build debug version"
	@echo "  make build-release  Build release version"
	@echo "  make clean          Clean all build artifacts"
	@echo "  make test           Run tests"
	@echo "  make bundle         Create signed app bundle"
	@echo ""
	@echo "Code Quality:"
	@echo "  make format         Format Swift code"
	@echo "  make format-check   Check formatting (CI)"
	@echo "  make lint           Run SwiftLint"
	@echo "  make lint-fix       Auto-fix lint issues"
	@echo ""
	@echo "Documentation:"
	@echo "  make docs           Generate documentation"
	@echo "  make docs-preview   Preview docs in browser"
	@echo ""
	@echo "Installer:"
	@echo "  make installer-build      Build Deno installer"
	@echo "  make installer-lint       Lint installer code"
	@echo "  make installer-fmt        Format installer code"
	@echo "  make installer-fmt-check  Check installer formatting"
	@echo ""
	@echo "Aggregate:"
	@echo "  make check          Run all checks (CI)"
	@echo "  make ci             Full CI pipeline"
	@echo "  make setup          Install dev tools"
	@echo ""
	@echo "Testing:"
	@echo "  make clean-install  Full reset for fresh install testing"
	@echo "                      (removes app, data, prefs, permissions)"
