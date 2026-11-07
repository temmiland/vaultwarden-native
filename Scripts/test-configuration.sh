#!/usr/bin/env bash
# Exercises xcconfig/Info/entitlement templates with PUBLIC synthetic identifiers only.
# This neither signs nor registers a team, profile, App Group or Keychain capability.
set -euo pipefail
REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/vaultwarden-configuration.XXXXXX")"
trap 'rm -rf "$CHECK_ROOT"' EXIT
cd "$REPOSITORY_ROOT"
[[ -d Vaultwarden.xcodeproj ]] || { echo "Generate the Xcode project first." >&2; exit 1; }
swift Scripts/verify-configuration.swift DEVELOPMENT_TEAM=0000000000
reject_fixture() {
  if swift Scripts/verify-configuration.swift DEVELOPMENT_TEAM=0000000000 "$@" > "$CHECK_ROOT/result.txt" 2>&1; then
    echo "Configuration checker accepted an invalid fixture" >&2
    exit 1
  fi
  if ! grep -q '^Configuration check failed:' "$CHECK_ROOT/result.txt"; then
    echo "Unexpected failure, not a configuration rejection" >&2
    exit 1
  fi
}
reject_fixture VW_KEYCHAIN_PREFIX=invalid
reject_fixture VW_APP_GROUP_IDENTIFIER=invalid
reject_fixture VW_SHARED_KEYCHAIN_SERVICE=fixture.same VW_PRIVATE_KEYCHAIN_SERVICE=fixture.same
echo "Three invalid configuration fixtures rejected; no signed-entitlement assertion."
