#!/usr/bin/env bash
set -euo pipefail

target="${1:?target is required}"
archive="${RUNNER_TEMP:-/tmp}/native-${target}.tar.xz"
tar_archive="$archive"

# GitHub's Windows runner exposes RUNNER_TEMP as a native path such as
# D:\a\_temp. GNU tar treats the colon as its remote-archive separator, so
# convert only the path passed to tar into Git Bash's POSIX form.
if [[ "$target" == windows-* ]]; then
  tar_archive="$(cygpath -u "$archive")"
fi

TARGET="$target" mise run native
tar -cJf "$tar_archive" -C . \
  "native/ocr/vendor/$target" \
  "native/speech/vendor/$target"
python ../.github/scripts/upload_release_asset.py natives "$archive"
