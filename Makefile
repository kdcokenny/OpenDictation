# OpenDictation Makefile
# Builds whisper.cpp XCFramework and downloads required models

# Directories
DEPS_DIR := deps
WHISPER_CPP_DIR := $(DEPS_DIR)/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework
MODELS_DIR := OpenDictation/Resources/Models

# Model URLs (from Hugging Face)
TINY_URL := https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin
SILERO_VAD_URL := https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin

.PHONY: all clean whisper models setup build check help dev reset release dmg run-release run lint lint-fix lsp test

# Default target
all: check setup build

# Development workflow
dev: setup build run

# Prerequisites check
check:
	@echo "Checking prerequisites..."
	@command -v git >/dev/null 2>&1 || { echo "Error: git is not installed"; exit 1; }
	@command -v xcodebuild >/dev/null 2>&1 || { echo "Error: Xcode is not installed"; exit 1; }
	@command -v curl >/dev/null 2>&1 || { echo "Error: curl is not installed"; exit 1; }
	@echo "Prerequisites OK"

# Build whisper.cpp XCFramework
whisper:
	@mkdir -p $(DEPS_DIR)
	@if [ ! -d "$(FRAMEWORK_PATH)" ]; then \
		echo "Building whisper.xcframework..."; \
		if [ ! -d "$(WHISPER_CPP_DIR)" ]; then \
			echo "Cloning whisper.cpp..."; \
			git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git $(WHISPER_CPP_DIR); \
		fi; \
		echo "Running build-xcframework.sh (this may take a few minutes)..."; \
		cd $(WHISPER_CPP_DIR) && ./build-xcframework.sh; \
		echo "whisper.xcframework built successfully"; \
	else \
		echo "whisper.xcframework already exists, skipping build"; \
	fi

# Download bundled models
models:
	@echo "Downloading models..."
	@mkdir -p $(MODELS_DIR)
	@if [ ! -f "$(MODELS_DIR)/ggml-tiny.bin" ]; then \
		echo "Downloading ggml-tiny.bin (~75MB multilingual)..."; \
		curl -L --progress-bar -o "$(MODELS_DIR)/ggml-tiny.bin" "$(TINY_URL)"; \
		echo "Downloaded ggml-tiny.bin"; \
	else \
		echo "ggml-tiny.bin already exists"; \
	fi
	@if [ ! -f "$(MODELS_DIR)/ggml-silero-v5.1.2.bin" ]; then \
		echo "Downloading ggml-silero-v5.1.2.bin (~2MB VAD model)..."; \
		curl -L --progress-bar -o "$(MODELS_DIR)/ggml-silero-v5.1.2.bin" "$(SILERO_VAD_URL)"; \
		echo "Downloaded ggml-silero-v5.1.2.bin"; \
	else \
		echo "VAD model already exists"; \
	fi

# Full setup: build framework and download models
setup: whisper models
	@echo ""
	@echo "Setup complete!"
	@echo "Framework: $(FRAMEWORK_PATH)"
	@echo "Models: $(MODELS_DIR)"
	@echo ""
	@echo "Next: run 'make build' to build the app"

# Setup LSP support for non-Xcode editors (VSCode, Cursor, Neovim, etc.)
lsp:
	@if command -v xcode-build-server >/dev/null 2>&1; then \
		echo "Generating LSP configuration..."; \
		xcode-build-server config -project OpenDictation.xcodeproj -scheme OpenDictation; \
		echo "buildServer.json created. Restart your editor/LSP to apply."; \
	else \
		echo "xcode-build-server not installed."; \
		echo "Install with: brew install xcode-build-server"; \
		exit 1; \
	fi

# Build the app (debug)
build:
	@if [ ! -f buildServer.json ] && command -v xcode-build-server >/dev/null 2>&1; then \
		echo "buildServer.json not found, generating LSP configuration..."; \
		$(MAKE) lsp; \
	fi
	@echo "Building OpenDictation Dev..."
	@xcodebuild -project OpenDictation.xcodeproj \
		-scheme OpenDictation \
		-configuration "Debug (Dev)" \
		build
	@echo ""
	@echo "Debug build complete!"
 
# Run tests (depends on setup to ensure .xcodeproj is up to date)
test: setup
	@echo "Running tests..."
	@xcodebuild -project OpenDictation.xcodeproj \
		-scheme OpenDictationTests \
		-destination 'platform=macOS' \
		test


# Run the app (debug build)
run:
	@echo "Running OpenDictation Dev..."
	@APP_PATH=$$(xcodebuild -project OpenDictation.xcodeproj -scheme OpenDictation -configuration "Debug (Dev)" -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR' | sed 's/.*= //'); \
	open "$$APP_PATH/OpenDictation Dev.app"

# Clean build artifacts
clean:
	@echo "Cleaning..."
	@rm -rf build
	@DERIVED_DATA=$$(xcodebuild -project OpenDictation.xcodeproj -scheme OpenDictation -showBuildSettings 2>/dev/null | grep -m1 'BUILD_DIR' | sed 's/.*= //' | sed 's|/Build/Products||'); \
	if [ -n "$$DERIVED_DATA" ] && [ -d "$$DERIVED_DATA" ]; then \
		echo "Cleaning DerivedData: $$DERIVED_DATA"; \
		rm -rf "$$DERIVED_DATA"; \
	fi
	@echo "Clean complete"

# Deep clean (removes deps and build)
clean-all: clean
	@echo "Removing dependencies..."
	rm -rf $(DEPS_DIR)
	@echo "Note: Models in $(MODELS_DIR) preserved. Remove manually if needed."
	@echo "Deep clean complete"

# Reset app state for testing (clears preferences and downloaded models)
reset:
	@echo "Resetting OpenDictation to fresh state..."
	@pkill -x OpenDictation 2>/dev/null || true
	@defaults delete com.opendictation 2>/dev/null || true
	@rm -rf ~/Library/Application\ Support/com.opendictation/Models/
	@echo "Reset complete. Run 'make run' to test fresh install flow."

# Build release app
release:
	@echo "Building release..."
	@xcodebuild -project OpenDictation.xcodeproj \
		-scheme OpenDictation \
		-configuration Release \
		build
	@echo ""
	@echo "Release build complete!"

# Create styled DMG from release build
dmg: release
	@echo "Creating styled DMG..."
	@command -v create-dmg >/dev/null 2>&1 || { echo "Installing create-dmg..."; brew install create-dmg; }
	@APP_PATH=$$(xcodebuild -project OpenDictation.xcodeproj -scheme OpenDictation -configuration Release -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR' | sed 's/.*= //'); \
	codesign --deep --force -s - "$$APP_PATH/OpenDictation.app"; \
	rm -f ~/Downloads/OpenDictation-local.dmg; \
	create-dmg \
		--volname "Open Dictation" \
		--volicon "OpenDictation/Resources/DMG/VolumeIcon.icns" \
		--background "OpenDictation/Resources/DMG/background.tiff" \
		--window-pos 200 120 \
		--window-size 500 400 \
		--icon-size 70 \
		--icon "OpenDictation.app" 100 200 \
		--hide-extension "OpenDictation.app" \
		--app-drop-link 350 200 \
		~/Downloads/OpenDictation-local.dmg \
		"$$APP_PATH/OpenDictation.app"
	@echo ""
	@echo "DMG created: ~/Downloads/OpenDictation-local.dmg"

# Run the release build
run-release: release
	@APP_PATH=$$(xcodebuild -project OpenDictation.xcodeproj -scheme OpenDictation -configuration Release -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR' | sed 's/.*= //'); \
	open "$$APP_PATH/OpenDictation.app"

# Lint Swift code with SwiftLint
lint:
	@if which swiftlint >/dev/null; then \
		swiftlint; \
	else \
		echo "SwiftLint not installed. Run: brew install swiftlint"; \
		exit 1; \
	fi

# Auto-fix lint violations where possible
lint-fix:
	@if which swiftlint >/dev/null; then \
		swiftlint --fix && swiftlint; \
	else \
		echo "SwiftLint not installed. Run: brew install swiftlint"; \
		exit 1; \
	fi

# Help
help:
	@echo "OpenDictation Build System"
	@echo ""
	@echo "Targets:"
	@echo "  check       Check if required CLI tools are installed"
	@echo "  whisper     Clone and build whisper.cpp XCFramework"
	@echo "  models      Download bundled Whisper models"
	@echo "  setup       Build framework + download models (run this first)"
	@echo "  build       Build the app (debug)"
	@echo "  run         Run the debug build"
	@echo "  dev         Setup + build + run (for development)"
	@echo "  all         Run check + setup + build (default)"
	@echo "  clean       Clean build artifacts"
	@echo "  clean-all   Clean + remove deps directory"
	@echo "  reset       Reset app state (clear prefs + downloaded models)"
	@echo "  release     Build release version"
	@echo "  dmg         Create DMG from release build"
	@echo "  run-release Run the release build"
	@echo "  lint        Run SwiftLint on all Swift files"
	@echo "  lint-fix    Auto-fix SwiftLint violations"
	@echo "  lsp         Setup LSP for non-Xcode editors (VSCode, Neovim, etc.)"
	@echo "  help        Show this help message"
	@echo ""
	@echo "Quick start (development):"
	@echo "  make setup    # First time: build framework + download models"
	@echo "  make build    # Build the app (debug)"
	@echo "  make run      # Run the app"
	@echo ""
	@echo "Non-Xcode editors (VSCode, Cursor, Neovim):"
	@echo "  brew install xcode-build-server"
	@echo "  make lsp      # Generate LSP configuration"
	@echo "  make build    # Build once to populate indexes"
	@echo ""
	@echo "Release testing:"
	@echo "  make release     # Build release version"
	@echo "  make dmg         # Create DMG for testing"
	@echo "  make run-release # Run release build directly"
