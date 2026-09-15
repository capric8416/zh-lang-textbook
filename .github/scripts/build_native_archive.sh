#!/usr/bin/env bash
set -euo pipefail

target="${1:?target is required}"
archive="${RUNNER_TEMP:-/tmp}/native-${target}.tar.xz"

TARGET="$target" mise run native
tar -cJf "$archive" -C . \
  "native/ocr/vendor/$target" \
  "native/speech/vendor/$target"
python ../.github/scripts/upload_release_asset.py natives "$archive"
