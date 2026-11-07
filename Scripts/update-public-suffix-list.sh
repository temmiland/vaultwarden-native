#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ '^[0-9a-f]{40}$' ]]; then
  print -u2 "Usage: $0 <40-character publicsuffix/list commit SHA>"
  exit 64
fi

script_dir="${0:A:h}"
repository_root="${script_dir:h}"
destination_dir="${repository_root}/Packages/AppModules/Sources/AutoFillData/Resources"
destination="${destination_dir}/public_suffix_list.dat"
revision="$1"
source_url="https://raw.githubusercontent.com/publicsuffix/list/${revision}/public_suffix_list.dat"

mkdir -p "$destination_dir"
temporary_file="$(mktemp "${destination}.XXXXXX")"
trap 'rm -f "$temporary_file"' EXIT

curl --fail --location --proto '=https' --tlsv1.2 "$source_url" --output "$temporary_file"
grep -q '^// ===BEGIN ICANN DOMAINS===' "$temporary_file"
grep -q '^// ===BEGIN PRIVATE DOMAINS===' "$temporary_file"
mv "$temporary_file" "$destination"
shasum -a 256 "$destination"
