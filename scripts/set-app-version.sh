#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <app-path> <version> <build-number>" >&2
  exit 64
fi

app_path=$1
version=$2
build_number=$3
info_plist="$app_path/Contents/Info.plist"
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

"$script_dir/validate-version.sh" "$version"
if [[ ! $build_number =~ ^[0-9]+$ ]]; then
  echo "Invalid build number: $build_number" >&2
  exit 64
fi
if ! command -v plutil >/dev/null; then
  echo "plutil is required to set the app version" >&2
  exit 1
fi
if [[ ! -f $info_plist ]]; then
  echo "Info.plist is missing from $app_path" >&2
  exit 1
fi

plutil -replace CFBundleShortVersionString -string "$version" "$info_plist"
plutil -replace CFBundleVersion -string "$build_number" "$info_plist"

actual_version=$(plutil -extract CFBundleShortVersionString raw "$info_plist")
actual_build=$(plutil -extract CFBundleVersion raw "$info_plist")
if [[ $actual_version != "$version" || $actual_build != "$build_number" ]]; then
  echo "Failed to set the app version" >&2
  exit 1
fi
