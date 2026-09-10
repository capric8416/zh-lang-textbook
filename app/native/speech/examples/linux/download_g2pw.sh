#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
destination="${1:-$script_dir/build/g2pw}"
revision="36c3fcce93aebfcb54803d2ad6677023a28ad950"
base_url="https://cdn.jsdelivr.net/gh/GitYCC/g2pW@$revision/g2pw"

checksum_for() {
  case "$1" in
    char_bopomofo_dict.json)
      printf '%s' 'fbde8d392453612c814bb6728c6d5f52a1f9d38135a602ef98f821fa22d7f005'
      ;;
    bopomofo_to_pinyin_wo_tune_dict.json)
      printf '%s' '0fe90e26be7653023772b3ad2d08952961bbf295fb39ba685c7172d3d9769f52'
      ;;
  esac
}

mkdir -p "$destination"
for name in char_bopomofo_dict.json bopomofo_to_pinyin_wo_tune_dict.json; do
  checksum="$(checksum_for "$name")"
  if ! printf '%s  %s\n' "$checksum" "$destination/$name" | \
      sha256sum --check --status 2>/dev/null; then
    partial="$destination/$name.part"
    curl --fail --location --retry 3 --output "$partial" \
      "$base_url/$name"
    printf '%s  %s\n' "$checksum" "$partial" | sha256sum --check
    mv "$partial" "$destination/$name"
  fi
done

printf '%s\n' "$destination"
