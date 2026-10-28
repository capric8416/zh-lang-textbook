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
if [[ "${VERIFY_SPEECH_BRIDGE:-0}" == "1" ]]; then
  bridge_build="build/native-speech-$target"
  cmake_args=(-S native/speech -B "$bridge_build" -DCMAKE_BUILD_TYPE=Release)
  if [[ "$target" == android-arm64-v8a ]]; then
    : "${ANDROID_NDK_HOME:?Android NDK is required for bridge verification}"
    cmake_args+=(
      "-DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"
      -DANDROID_ABI=arm64-v8a
      -DANDROID_PLATFORM=android-24
    )
  fi
  cmake "${cmake_args[@]}"
  cmake --build "$bridge_build" --parallel 2
  library="$bridge_build/libzh_speech.so"
  for symbol in zh_speech_snac_create zh_speech_snac_encode_wav zh_speech_snac_decode_wav; do
    if ! readelf -Ws "$library" | grep -F "$symbol" >/dev/null; then
      echo "Missing SNAC export: $symbol" >&2
      exit 1
    fi
  done
fi
tar -cJf "$tar_archive" -C . \
  "native/ocr/vendor/$target" \
  "native/speech/vendor/$target"
python ../.github/scripts/upload_release_asset.py natives "$archive"
