#!/usr/bin/env bash
# Synthetic tracked repository only. Never prints the fixture credential value.
set -euo pipefail
REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/vaultwarden-secret-check.XXXXXX")"
trap 'rm -rf "$CHECK_ROOT"' EXIT
git -C "$CHECK_ROOT" init --quiet
printf '%s\n' 'Only synthetic ordinary text.' > "$CHECK_ROOT/fixture.txt"
git -C "$CHECK_ROOT" add fixture.txt
(cd "$CHECK_ROOT" && swift "$REPOSITORY_ROOT/Scripts/check-source-secrets.swift")
# Split intentionally: a scanner regression fixture is not a real credential in this script.
printf '%s%s\n' 'AKIA' '0000000000000000' > "$CHECK_ROOT/fixture.txt"
if (cd "$CHECK_ROOT" && swift "$REPOSITORY_ROOT/Scripts/check-source-secrets.swift") > "$CHECK_ROOT/result.txt" 2>&1; then
  echo "Credential checker accepted synthetic negative fixture" >&2
  exit 1
fi
if ! grep -Fq 'fixture.txt (content withheld)' "$CHECK_ROOT/result.txt"; then
  echo "Credential checker did not name the offending file safely" >&2
  exit 1
fi
if grep -Eq 'AKIA[0-9]{16}' "$CHECK_ROOT/result.txt"; then
  echo "Credential checker leaked synthetic matching content" >&2
  exit 1
fi
TOKEN_PREFIX='glpat-abcdefghijklmnop'
TOKEN_SUFFIX='qrstuvwxyz123456'
printf '%s%s\n' "$TOKEN_PREFIX" "$TOKEN_SUFFIX" > "$CHECK_ROOT/fixture.txt"
if (cd "$CHECK_ROOT" && swift "$REPOSITORY_ROOT/Scripts/check-source-secrets.swift") > "$CHECK_ROOT/result.txt" 2>&1; then
  echo "Credential checker accepted a synthetic GitLab token" >&2
  exit 1
fi
if ! grep -Fq 'fixture.txt (content withheld)' "$CHECK_ROOT/result.txt" ||
  grep -Fq "$TOKEN_PREFIX$TOKEN_SUFFIX" "$CHECK_ROOT/result.txt"; then
  echo "Credential checker missed the synthetic token or leaked its content" >&2
  exit 1
fi
echo "Synthetic credentials rejected without printing their content."

# Neither a newly created file nor generated SDK source may escape the publication check.
printf '%s\n' 'Only synthetic ordinary text.' > "$CHECK_ROOT/fixture.txt"
mkdir -p "$CHECK_ROOT/Packages/VaultwardenSDK/Sources/BitwardenSdk"
for target in new-source.swift Packages/VaultwardenSDK/Sources/BitwardenSdk/generated.swift LICENSE dataset.dat; do
  printf '%s%s\n' "$TOKEN_PREFIX" "$TOKEN_SUFFIX" > "$CHECK_ROOT/$target"
  if (cd "$CHECK_ROOT" && swift "$REPOSITORY_ROOT/Scripts/check-source-secrets.swift") > "$CHECK_ROOT/result.txt" 2>&1; then
    echo "Credential checker skipped new/generated source" >&2
    exit 1
  fi
  if ! grep -Fq "$target (content withheld)" "$CHECK_ROOT/result.txt" ||
    grep -Fq "$TOKEN_PREFIX$TOKEN_SUFFIX" "$CHECK_ROOT/result.txt"; then
    echo "Credential checker missed new/generated source or leaked content" >&2
    exit 1
  fi
  rm "$CHECK_ROOT/$target"
done
echo "New and generated source fixtures rejected safely."

# A deleted file remains part of publication history. The history mode must catch it without
# printing the synthetic token itself.
printf '%s%s\n' "$TOKEN_PREFIX" "$TOKEN_SUFFIX" > "$CHECK_ROOT/fixture.txt"
git -C "$CHECK_ROOT" add fixture.txt
git -C "$CHECK_ROOT" -c user.name='Secret Scanner Fixture' -c user.email='scanner@example.invalid' \
  commit --quiet -m 'Add synthetic historical token fixture'
rm "$CHECK_ROOT/fixture.txt"
git -C "$CHECK_ROOT" add -u
git -C "$CHECK_ROOT" -c user.name='Secret Scanner Fixture' -c user.email='scanner@example.invalid' \
  commit --quiet -m 'Remove synthetic historical token fixture'
if (cd "$CHECK_ROOT" && swift "$REPOSITORY_ROOT/Scripts/check-source-secrets.swift" --history) > "$CHECK_ROOT/result.txt" 2>&1; then
  echo "Credential checker missed a token in reachable Git history" >&2
  exit 1
fi
if ! grep -Fq 'fixture.txt (content withheld)' "$CHECK_ROOT/result.txt" ||
  grep -Fq "$TOKEN_PREFIX$TOKEN_SUFFIX" "$CHECK_ROOT/result.txt"; then
  echo "History checker missed the fixture or leaked its content" >&2
  exit 1
fi
echo "Synthetic token in reachable Git history rejected without printing its content."
