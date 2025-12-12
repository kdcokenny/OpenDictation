# OpenDictation Makefile
# Builds whisper.cpp XCFramework and downloads required models

# Directories
DEPS_DIR := deps
WHISPER_CPP_DIR := $(DEPS_DIR)/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework
MODELS_DIR := Sources/OpenDictation/Resources/Models

# Model URLs (from Hugging Face)
TINY_URL := https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin
SILERO_VAD_URL := https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin

.PHONY: all clean whisper models setup build check help dev reset release dmg run-release

# Default target
all: check setup build

# Development workflow
dev: setup build run

# Prerequisites check
check:
	@echo "Checking prerequisites..."
	@command -v git >/dev/null 2>&1 || { echo "Error: git is not installed"; exit 1; }
	@command -v swift >/dev/null 2>&1 || { echo "Error: swift is not installed"; exit 1; }
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

# Build the Swift package
build:
	@echo "Building OpenDictation..."
	swift build

# Run the app (debug build)
run:
	@echo "Running OpenDictation..."
	swift run

# Clean build artifacts
clean:
	@echo "Cleaning..."
	swift package clean
	@echo "Clean complete"

# Deep clean (removes deps and models)
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

# Build release app using xcodebuild (same as CI)
release:
	@echo "Building release with xcodebuild..."
	@command -v xcodegen >/dev/null 2>&1 || { echo "Installing xcodegen..."; brew install xcodegen; }
	@xcodegen generate
	@xcodebuild -project OpenDictation.xcodeproj \
		-scheme OpenDictation \
		-configuration Release \
		-derivedDataPath build \
		build
	@echo ""
	@echo "Release build complete!"
	@echo "App: build/Build/Products/Release/OpenDictation.app"

# Create styled DMG from release build
dmg: release
	@echo "Creating styled DMG..."
	@command -v create-dmg >/dev/null 2>&1 || { echo "Installing create-dmg..."; brew install create-dmg; }
	@codesign --deep --force -s - build/Build/Products/Release/OpenDictation.app
	@rm -f ~/Downloads/OpenDictation-local.dmg
	@create-dmg \
		--volname "Open Dictation" \
		--volicon "Sources/OpenDictation/Resources/DMG/VolumeIcon.icns" \
		--background "Sources/OpenDictation/Resources/DMG/background.tiff" \
		--window-pos 200 120 \
		--window-size 500 400 \
		--icon-size 70 \
		--icon "OpenDictation.app" 100 200 \
		--hide-extension "OpenDictation.app" \
		--app-drop-link 350 200 \
		~/Downloads/OpenDictation-local.dmg \
		build/Build/Products/Release/OpenDictation.app
	@echo ""
	@echo "DMG created: ~/Downloads/OpenDictation-local.dmg"

# Run the release build
run-release: release
	@open build/Build/Products/Release/OpenDictation.app

# Help
help:
	@echo "OpenDictation Build System"
	@echo ""
	@echo "Targets:"
	@echo "  check       Check if required CLI tools are installed"
	@echo "  whisper     Clone and build whisper.cpp XCFramework"
	@echo "  models      Download bundled Whisper models"
	@echo "  setup       Build framework + download models (run this first)"
	@echo "  build       Build the Swift package (debug)"
	@echo "  run         Run the debug build"
	@echo "  dev         Setup + build + run (for development)"
	@echo "  all         Run check + setup + build (default)"
	@echo "  clean       Clean Swift build artifacts"
	@echo "  clean-all   Clean + remove deps directory"
	@echo "  reset       Reset app state (clear prefs + downloaded models)"
	@echo "  release     Build release app using xcodebuild (same as CI)"
	@echo "  dmg         Create DMG from release build"
	@echo "  run-release Run the release build"
	@echo "  help        Show this help message"
	@echo ""
	@echo "Quick start (development):"
	@echo "  make setup    # First time: build framework + download models"
	@echo "  make build    # Build the app (debug)"
	@echo "  make run      # Run the app"
	@echo ""
	@echo "Release testing:"
	@echo "  make release     # Build release version (same as CI)"
	@echo "  make dmg         # Create DMG for testing"
	@echo "  make run-release # Run release build directly"
