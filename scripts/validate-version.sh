#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version>" >&2
  exit 64
fi

version=$1
numeric_identifier='(0|[1-9][0-9]*)'
non_numeric_identifier='[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*'
prerelease_identifier="(${numeric_identifier}|${non_numeric_identifier})"
build_identifier='[0-9A-Za-z-]+'
semver_core="${numeric_identifier}\.${numeric_identifier}\.${numeric_identifier}"
semver_prerelease="(-${prerelease_identifier}(\.${prerelease_identifier})*)?"
semver_build="(\+${build_identifier}(\.${build_identifier})*)?"
semver_pattern="^${semver_core}${semver_prerelease}${semver_build}$"

if [[ ! $version =~ $semver_pattern ]]; then
  echo "Invalid SemVer version: $version" >&2
  exit 64
fi
