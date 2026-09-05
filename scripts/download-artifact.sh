#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <url> <sha256> <destination>" >&2
  exit 64
fi

url=$1
expected_sha256=$2
destination=$3

if [[ ! $expected_sha256 =~ ^[0-9a-f]{64}$ ]]; then
  echo "Invalid SHA-256 for $destination" >&2
  exit 64
fi

sha256() {
  shasum -a 256 "$1" | awk '{print $1}'
}

if [[ -f $destination ]]; then
  actual_sha256=$(sha256 "$destination")
  if [[ $actual_sha256 == "$expected_sha256" ]]; then
    echo "Verified $destination"
    exit 0
  fi

  echo "Replacing $destination because its SHA-256 does not match" >&2
fi

mkdir -p "$(dirname "$destination")"
temporary_file=$(mktemp "${destination}.download.XXXXXX")
trap 'rm -f "$temporary_file"' EXIT

curl \
  --fail \
  --location \
  --retry 3 \
  --retry-all-errors \
  --show-error \
  --output "$temporary_file" \
  "$url"

actual_sha256=$(sha256 "$temporary_file")
if [[ $actual_sha256 != "$expected_sha256" ]]; then
  echo "SHA-256 mismatch for $url" >&2
  echo "Expected: $expected_sha256" >&2
  echo "Actual:   $actual_sha256" >&2
  exit 1
fi

mv -f "$temporary_file" "$destination"
trap - EXIT
echo "Downloaded and verified $destination"
