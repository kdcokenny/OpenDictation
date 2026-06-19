#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="OpenDictation Dev"
BUNDLE_ID="com.opendictation.dev"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_DIR="$ROOT_DIR/.derivedData"
APP_BUNDLE="$DERIVED_DATA_DIR/Build/Products/Debug (Dev)/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
PROJECT_FILE="$ROOT_DIR/OpenDictation.xcodeproj"

stop_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

ensure_project() {
  if [[ -d "$PROJECT_FILE" && "$PROJECT_FILE/project.pbxproj" -nt "$ROOT_DIR/project.yml" ]]; then
    return
  fi

  if ! command -v xcodegen >/dev/null 2>&1; then
    echo "OpenDictation.xcodeproj is missing or stale. Install xcodegen to regenerate it." >&2
    exit 1
  fi

  (cd "$ROOT_DIR" && xcodegen generate)
}

build_app() {
  ensure_project
  xcodebuild build \
    -project "$PROJECT_FILE" \
    -scheme OpenDictation \
    -configuration "Debug (Dev)" \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_DIR"
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

stop_app
build_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
