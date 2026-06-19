#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MARKER_PATH="$ROOT_DIR/Benchmarks/TranscriptCleanup/.run-live-benchmark"

cd "$ROOT_DIR"

printf '%s\n' "$@" > "$MARKER_PATH"
trap 'rm -f "$MARKER_PATH"' EXIT

OPENDICTATION_RUN_LIVE_CLEANUP_BENCHMARKS=1 \
xcodebuild test \
  -project OpenDictation.xcodeproj \
  -scheme OpenDictation \
  -destination 'platform=macOS' \
  -only-testing:OpenDictationTests/TranscriptPostProcessorTests/testLiveHybridProductBenchmarkPassesDefaultLocalModel
