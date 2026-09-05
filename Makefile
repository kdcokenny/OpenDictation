SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

include scripts/dependencies.env

PROJECT := OpenDictation.xcodeproj
SCHEME := OpenDictation
DEPS_DIR := deps
WHISPER_DIR := $(DEPS_DIR)/whisper.cpp
WHISPER_FRAMEWORK := $(WHISPER_DIR)/build-apple/whisper.xcframework
WHISPER_ARCHIVE := $(DEPS_DIR)/whisper-v$(WHISPER_VERSION)-xcframework.zip
WHISPER_URL := https://github.com/ggml-org/whisper.cpp/releases/download/v$(WHISPER_VERSION)/whisper-v$(WHISPER_VERSION)-xcframework.zip
WHISPER_STAMP := $(WHISPER_DIR)/.xcframework-version
MODELS_DIR := OpenDictation/Resources/Models
TINY_MODEL := $(MODELS_DIR)/ggml-tiny.bin
TINY_URL := https://huggingface.co/ggerganov/whisper.cpp/resolve/$(WHISPER_TINY_REVISION)/ggml-tiny.bin
SILERO_MODEL := $(MODELS_DIR)/ggml-silero-v5.1.2.bin
SILERO_URL := https://huggingface.co/ggml-org/whisper-vad/resolve/$(SILERO_VAD_REVISION)/ggml-silero-v5.1.2.bin
DOWNLOAD := scripts/download-artifact.sh

BUILD_DIR ?= build
DIST_DIR ?= dist
APP_PATH := $(BUILD_DIR)/Build/Products/Release/OpenDictation.app
TEST_RESULTS := $(BUILD_DIR)/TestResults.xcresult
RELEASE_VERSION ?= 0.0.0-dev
BUILD_NUMBER ?= 0
XCODEBUILD_FLAGS ?=

.PHONY: all build check ci clean clean-all dev dmg generate help lint lint-fix lsp models release reset run run-release setup test verify-release whisper

all: build

dev: build run

check:
	@command -v git >/dev/null || { echo "git is required" >&2; exit 1; }
	@command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
	@command -v shasum >/dev/null || { echo "shasum is required" >&2; exit 1; }
	@command -v unzip >/dev/null || { echo "unzip is required" >&2; exit 1; }
	@command -v xcodebuild >/dev/null || { echo "Xcode is required" >&2; exit 1; }
	@command -v xcodegen >/dev/null || { echo "xcodegen is required. Install it with: brew install xcodegen" >&2; exit 1; }

whisper:
	@expected_stamp='$(WHISPER_VERSION):$(WHISPER_XCFRAMEWORK_SHA256)'; \
	actual_stamp="$$(cat '$(WHISPER_STAMP)' 2>/dev/null || true)"; \
	if [[ -d '$(WHISPER_FRAMEWORK)' && "$$actual_stamp" == "$$expected_stamp" ]]; then \
		echo "Verified whisper.cpp $(WHISPER_VERSION) XCFramework"; \
		exit 0; \
	fi; \
	'$(DOWNLOAD)' '$(WHISPER_URL)' '$(WHISPER_XCFRAMEWORK_SHA256)' '$(WHISPER_ARCHIVE)'; \
	extract_dir="$$(mktemp -d '$(DEPS_DIR)/whisper.extract.XXXXXX')"; \
	trap 'rm -rf "$$extract_dir"' EXIT; \
	unzip -q '$(WHISPER_ARCHIVE)' -d "$$extract_dir"; \
	test -d "$$extract_dir/build-apple/whisper.xcframework" || { echo "whisper.cpp archive has an unexpected layout" >&2; exit 1; }; \
	mkdir -p '$(WHISPER_DIR)'; \
	rm -rf '$(WHISPER_DIR)/build-apple'; \
	mv "$$extract_dir/build-apple" '$(WHISPER_DIR)/build-apple'; \
	printf '%s\n' "$$expected_stamp" > '$(WHISPER_STAMP)'; \
	echo "Installed whisper.cpp $(WHISPER_VERSION) XCFramework"

models:
	@'$(DOWNLOAD)' '$(TINY_URL)' '$(WHISPER_TINY_SHA256)' '$(TINY_MODEL)'
	@'$(DOWNLOAD)' '$(SILERO_URL)' '$(SILERO_VAD_SHA256)' '$(SILERO_MODEL)'

generate:
	@xcodegen generate --spec project.yml

setup:
	@$(MAKE) check
	@$(MAKE) whisper
	@$(MAKE) models
	@$(MAKE) generate
	@echo "Setup complete"

build: setup
	@xcodebuild \
		-project '$(PROJECT)' \
		-scheme '$(SCHEME)' \
		-configuration 'Debug (Dev)' \
		-derivedDataPath '$(BUILD_DIR)' \
		$(XCODEBUILD_FLAGS) \
		build

test: setup
	@rm -rf '$(TEST_RESULTS)'
	@xcodebuild \
		-project '$(PROJECT)' \
		-scheme '$(SCHEME)' \
		-configuration Debug \
		-destination 'platform=macOS' \
		-derivedDataPath '$(BUILD_DIR)' \
		-resultBundlePath '$(TEST_RESULTS)' \
		$(XCODEBUILD_FLAGS) \
		test

release: setup
	@xcodebuild \
		-project '$(PROJECT)' \
		-scheme '$(SCHEME)' \
		-configuration Release \
		-derivedDataPath '$(BUILD_DIR)' \
		MARKETING_VERSION='$(RELEASE_VERSION)' \
		CURRENT_PROJECT_VERSION='$(BUILD_NUMBER)' \
		ARCHS=arm64 \
		$(XCODEBUILD_FLAGS) \
		clean build
	@scripts/set-app-version.sh '$(APP_PATH)' '$(RELEASE_VERSION)' '$(BUILD_NUMBER)'

verify-release: release
	@test -x '$(APP_PATH)/Contents/MacOS/OpenDictation' || { echo "Release executable is missing" >&2; exit 1; }
	@tiny_model="$$(find '$(APP_PATH)/Contents/Resources' -type f -name ggml-tiny.bin -print -quit)"; \
	test -n "$$tiny_model" || { echo "ggml-tiny.bin is missing from the app" >&2; exit 1; }; \
	printf '%s  %s\n' '$(WHISPER_TINY_SHA256)' "$$tiny_model" | shasum -a 256 -c -
	@silero_model="$$(find '$(APP_PATH)/Contents/Resources' -type f -name ggml-silero-v5.1.2.bin -print -quit)"; \
	test -n "$$silero_model" || { echo "Silero VAD model is missing from the app" >&2; exit 1; }; \
	printf '%s  %s\n' '$(SILERO_VAD_SHA256)' "$$silero_model" | shasum -a 256 -c -
	@test -d '$(APP_PATH)/Contents/Frameworks/whisper.framework' || { echo "whisper.framework is missing from the app" >&2; exit 1; }
	@echo "Verified release app and bundled resources"

lint:
	@command -v swiftlint >/dev/null || { echo "SwiftLint is required. Install it with: brew install swiftlint" >&2; exit 1; }
	@swiftlint --strict

lint-fix:
	@command -v swiftlint >/dev/null || { echo "SwiftLint is required. Install it with: brew install swiftlint" >&2; exit 1; }
	@swiftlint --fix
	@swiftlint --strict

ci:
	@$(MAKE) lint
	@$(MAKE) test
	@$(MAKE) verify-release

dmg: verify-release
	@command -v create-dmg >/dev/null || { echo "create-dmg is required. Install it with: brew install create-dmg" >&2; exit 1; }
	@mkdir -p '$(DIST_DIR)'
	@codesign --deep --force --sign - --entitlements OpenDictation/OpenDictation.entitlements '$(APP_PATH)'
	@rm -f '$(DIST_DIR)/OpenDictation-local.dmg'
	@create-dmg \
		--volname 'Open Dictation' \
		--volicon 'OpenDictation/Resources/DMG/VolumeIcon.icns' \
		--background 'OpenDictation/Resources/DMG/background.tiff' \
		--window-pos 200 120 \
		--window-size 500 400 \
		--icon-size 70 \
		--icon 'OpenDictation.app' 100 200 \
		--hide-extension 'OpenDictation.app' \
		--app-drop-link 350 200 \
		'$(DIST_DIR)/OpenDictation-local.dmg' \
		'$(APP_PATH)'
	@echo "Created $(DIST_DIR)/OpenDictation-local.dmg with an ad hoc signature"

lsp: generate
	@command -v xcode-build-server >/dev/null || { echo "xcode-build-server is required. Install it with: brew install xcode-build-server" >&2; exit 1; }
	@xcode-build-server config -project '$(PROJECT)' -scheme '$(SCHEME)'

run: build
	@open '$(BUILD_DIR)/Build/Products/Debug (Dev)/OpenDictation Dev.app'

run-release: release
	@open '$(APP_PATH)'

clean:
	@for path in '$(BUILD_DIR)' '$(DIST_DIR)'; do \
		if [[ -z "$$path" || "$$path" == /* || "$$path" == '.' || "$$path" == '..' || "$$path" == *'../'* || "$$path" == *'/..' ]]; then \
			echo "Refusing to clean unsafe path: $$path" >&2; \
			exit 1; \
		fi; \
	done
	@rm -rf -- '$(BUILD_DIR)' '$(DIST_DIR)'

clean-all: clean
	@rm -rf -- '$(DEPS_DIR)'

reset:
	@pkill -x OpenDictation 2>/dev/null || true
	@defaults delete com.opendictation 2>/dev/null || true
	@rm -rf -- "$$HOME/Library/Application Support/com.opendictation/Models"

help:
	@echo 'OpenDictation build targets'
	@echo '  setup          Download verified dependencies and generate the Xcode project'
	@echo '  build          Build the development app'
	@echo '  test           Run the macOS unit tests'
	@echo '  lint           Run SwiftLint in strict mode'
	@echo '  release        Make a clean unsigned release build in build/'
	@echo '  verify-release Check the app executable, framework, and bundled models'
	@echo '  ci             Run lint, tests, and release verification'
	@echo '  dmg            Create a local ad hoc signed DMG in dist/'
	@echo '  clean-all      Remove generated builds and downloaded dependencies'
