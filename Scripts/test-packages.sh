#!/usr/bin/env bash
# Runs every remaining local Swift package in a deterministic order. Each owns its build cache,
# so serial execution avoids contention in the vendored Bitwarden SDK build products.
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

packages=(
  VaultwardenSDK
  AppModules
)

for package in "${packages[@]}"; do
  echo "==> Testing Packages/${package}"
  (
    cd "${REPOSITORY_ROOT}/Packages/${package}"
    swift test --no-parallel
  )
done
