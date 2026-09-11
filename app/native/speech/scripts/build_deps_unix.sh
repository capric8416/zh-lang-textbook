#!/usr/bin/env bash
set -euo pipefail

target="${1:-linux-x64}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
speech_dir="$(cd "$script_dir/.." && pwd)"
# macOS's default filesystem is case-insensitive, while espeak-ng contains
# phoneme files whose names differ only by case. CI can provide a case-
# sensitive volume through this override so ExternalProject's checkout keeps
# the complete source tree.
deps_root="${SPEECH_DEPS_ROOT:-$speech_dir/.build-deps}"
build_root="$deps_root/$target"
source_root="$deps_root/sources"
vendor="$speech_dir/vendor/$target"
piper_commit=404aefedbd74baa0bd43e451bc407a2b3aace0f5
funasr_commit=231ec5dda739c83f35e59e875736cde3ef1af161
ort_tag=v1.22.0
ort_revision=f217402897f40ebba457e2421bc0a4702771968e

mkdir -p "$build_root" "$source_root" "$vendor/include" "$vendor/lib"

checkout() {
  local url="$1" revision="$2" destination="$3"
  local current expected
  if [[ ! -d "$destination/.git" ]]; then
    git init -q "$destination"
    git -C "$destination" remote add origin "$url"
  fi
  current="$(git -C "$destination" rev-parse --verify HEAD 2>/dev/null || true)"
  if git -C "$destination" rev-parse --verify --quiet "$revision^{commit}" >/dev/null; then
    expected="$(git -C "$destination" rev-parse --verify "$revision^{commit}")"
  else
    git -C "$destination" fetch --depth 1 origin "$revision"
    expected="$(git -C "$destination" rev-parse --verify 'FETCH_HEAD^{commit}')"
  fi
  if [[ "$current" != "$expected" ]]; then
    git -C "$destination" checkout -q --detach "$expected"
  fi
}

checkout https://github.com/microsoft/onnxruntime.git "$ort_revision" \
  "$source_root/onnxruntime-$ort_tag"
checkout https://github.com/OHF-Voice/piper1-gpl.git "$piper_commit" \
  "$source_root/piper-$piper_commit"
checkout https://github.com/modelscope/FunASR.git "$funasr_commit" \
  "$source_root/funasr-$funasr_commit"

ort_source="$source_root/onnxruntime-$ort_tag"
piper_source="$source_root/piper-$piper_commit"
funasr_source="$source_root/funasr-$funasr_commit/runtime/onnxruntime"
ort_build="$build_root/onnxruntime"

# GitLab regenerated Eigen's source archive without changing its contents;
# ONNX Runtime 1.22.0 still records the old archive SHA-1. Pin the currently
# served archive hash so FetchContent remains verified and reproducible.
sed -i.bak \
  's/5ea4d05e62d7f954a46b3213f9b2535bdd866803/51982be81bbe52572b54180454df11a3ece9a934/' \
  "$ort_source/cmake/deps.txt"
rm -f "$ort_source/cmake/deps.txt.bak"

# GCC 15 no longer exposes uint8_t through ONNX Runtime's transitive includes.
# Keep the pinned 1.22.0 source buildable on current Linux distributions.
optimizer_api="$ort_source/onnxruntime/core/optimizer/transpose_optimization/optimizer_api.h"
if ! grep -q '^#include <cstdint>$' "$optimizer_api"; then
  perl -0pi.bak -e \
    's/^#include <functional>$/#include <cstdint>\n#include <functional>/m' \
    "$optimizer_api"
  rm -f "$optimizer_api.bak"
fi

# The Ubuntu 20.04 image's clang does not recognize -mavxvnni. ORT's MLAS
# condition assumes every non-GCC compiler supports it, so restrict that flag
# to GCC versions known to implement it; AVX2 remains enabled for clang.
mlas_cmake="$ort_source/cmake/onnxruntime_mlas.cmake"
sed -i.bak \
  's/if(NOT "${CMAKE_CXX_COMPILER_ID}" STREQUAL "GNU" OR CMAKE_CXX_COMPILER_VERSION VERSION_GREATER "11")/if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU" AND CMAKE_CXX_COMPILER_VERSION VERSION_GREATER "11")/' \
  "$mlas_cmake"
rm -f "$mlas_cmake.bak"

# --skip_tests prevents test execution, but ONNX Runtime otherwise still adds
# and compiles the large onnxruntime_test_all target. Disable those targets at
# CMake configuration time as well; this build only needs the runtime library.
ort_args=(
  --config Release --parallel --skip_tests
  --cmake_extra_defines
  onnxruntime_BUILD_UNIT_TESTS=OFF
  onnxruntime_BUILD_BENCHMARKS=OFF
)
cmake_platform_args=()
funasr_platform_args=()
case "$target" in
  linux-x64)
    ort_args+=(--build_dir "$ort_build")
    ;;
  macos-*)
    arch="${target#macos-}"
    ort_args+=(--build_dir "$ort_build" --osx_arch "$arch")
    cmake_platform_args+=("-DCMAKE_OSX_ARCHITECTURES=$arch")
    funasr_platform_args+=("-DCMAKE_CXX_FLAGS=-Wno-deprecated-declarations")
    ;;
  ios-arm64)
    ort_args+=(--build_dir "$ort_build" --ios --apple_sysroot iphoneos \
      --osx_arch arm64 --apple_deploy_target 13.0)
    cmake_platform_args+=(
      -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos
      -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0)
    funasr_platform_args+=("-DCMAKE_CXX_FLAGS=-Wno-deprecated-declarations")
    ;;
  android-arm64-v8a)
    : "${ANDROID_NDK_HOME:?ANDROID_NDK_HOME is required}"
    : "${ANDROID_SDK_ROOT:?ANDROID_SDK_ROOT is required}"
    ort_args+=(--build_dir "$ort_build" --android
      --android_sdk_path "$ANDROID_SDK_ROOT"
      --android_ndk_path "$ANDROID_NDK_HOME"
      --android_abi arm64-v8a --android_api 24)
    cmake_platform_args+=(
      "-DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"
      -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24)
    ;;
  *) echo "Unsupported target: $target" >&2; exit 2 ;;
esac

if [[ "$(id -u)" -eq 0 ]]; then
  ort_args+=(--allow_running_as_root)
fi

if [[ ! -f "$build_root/onnxruntime.done" ]]; then
  "$ort_source/build.sh" "${ort_args[@]}"
  touch "$build_root/onnxruntime.done"
fi

# Stage the C/C++ API in the flat layout expected by both upstream runtimes.
cp "$ort_source/include/onnxruntime/core/session/"*.h "$vendor/include/"
mkdir -p "$vendor/include/onnxruntime"
cp "$ort_source/include/onnxruntime/core/session/"*.h \
  "$vendor/include/onnxruntime/"
if [[ -f "$ort_build/Release/onnxruntime_config.h" ]]; then
  cp "$ort_build/Release/onnxruntime_config.h" "$vendor/include/"
fi

# Upstream Piper currently defaults to SHARED and downloads a shared ORT.
# The pinned source is patched in the build tree to consume our static ORT.
piper_work="$build_root/piper-source"
rm -rf "$piper_work"
cp -R "$piper_source/libpiper" "$piper_work"
cp "$piper_source/setup.py" "$build_root/setup.py"
sed -i.bak 's/cmake_minimum_required(VERSION 3.26)/cmake_minimum_required(VERSION 3.16)/' \
  "$piper_work/CMakeLists.txt"
sed -i.bak 's/add_library(piper SHARED/add_library(piper STATIC/' \
  "$piper_work/CMakeLists.txt"
sed -i.bak 's/enable_clang_tidy(piper)/target_compile_definitions(piper PUBLIC BUILDING_LIBPIPER)\n\noption(BUILD_PIPER_EXECUTABLE "Build the Piper command-line executable" OFF)\nif(BUILD_PIPER_EXECUTABLE)\n  add_subdirectory(src\/main)\nendif()/' \
  "$piper_work/CMakeLists.txt"
sed -i.bak '/# ---- piper exe ---/{N; s/# ---- piper exe ---\nadd_subdirectory(src\/main)//;}' \
  "$piper_work/CMakeLists.txt"
rm -f "$piper_work/CMakeLists.txt.bak"
patch --batch --forward -p1 -d "$piper_work" \
  -i "$speech_dir/patches/piper-pinyin-whitespace.patch"
if grep -q 'phonemes.push_back(" ");' \
    "$piper_work/src/chinese_phonemizer.cpp"; then
  echo "Piper pinyin whitespace patch did not take effect" >&2
  exit 1
fi
case "$target" in
  android-*)
    sed -i.bak "/-DCMAKE_BUILD_TYPE=\${CMAKE_BUILD_TYPE}/a\\
      -DCMAKE_TOOLCHAIN_FILE:FILEPATH=\${CMAKE_TOOLCHAIN_FILE}\\
      -DANDROID_ABI:STRING=\${ANDROID_ABI}\\
      -DANDROID_PLATFORM:STRING=\${ANDROID_PLATFORM}" "$piper_work/CMakeLists.txt"
    ;;
  ios-*)
    sed -i.bak "/-DCMAKE_BUILD_TYPE=\${CMAKE_BUILD_TYPE}/a\\
      -DCMAKE_SYSTEM_NAME:STRING=iOS\\
      -DCMAKE_OSX_SYSROOT:STRING=\${CMAKE_OSX_SYSROOT}\\
      -DCMAKE_OSX_ARCHITECTURES:STRING=\${CMAKE_OSX_ARCHITECTURES}\\
      -DCMAKE_OSX_DEPLOYMENT_TARGET:STRING=\${CMAKE_OSX_DEPLOYMENT_TARGET}" "$piper_work/CMakeLists.txt"
    ;;
  macos-*)
    sed -i.bak "/-DCMAKE_BUILD_TYPE=\${CMAKE_BUILD_TYPE}/a\\
      -DCMAKE_OSX_ARCHITECTURES:STRING=\${CMAKE_OSX_ARCHITECTURES}" "$piper_work/CMakeLists.txt"
    ;;
esac
rm -f "$piper_work/CMakeLists.txt.bak"

# First combine ORT components so find_library sees a conventional archive.
ort_archives=()
while IFS= read -r archive; do ort_archives+=("$archive"); done < <(
  find "$ort_build" -name '*.a' -type f \
    ! -name '*test*' ! -name '*benchmark*' | sort
)
if (( ${#ort_archives[@]} == 0 )); then
  echo "No static ONNX Runtime archives found" >&2
  exit 1
fi
if [[ "$(uname -s)" == Darwin ]]; then
  libtool -static -o "$vendor/lib/libonnxruntime.a" "${ort_archives[@]}"
else
  {
    echo 'create libonnxruntime.a'
    for archive in "${ort_archives[@]}"; do echo "addlib $archive"; done
    echo 'save'
    echo 'end'
  } | (cd "$vendor/lib" && ar -M)
fi
re2_archive="$(find "$ort_build" -type f -iname '*re2*.a' | head -n 1)"
if [[ -z "$re2_archive" ]]; then
  echo "No static RE2 archive found under $ort_build" >&2
  exit 1
fi
cp "$re2_archive" "$vendor/lib/libre2.a"

cmake -S "$piper_work" -B "$build_root/piper" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_PIPER_EXECUTABLE=OFF \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DONNXRUNTIME_DIR="$vendor" "${cmake_platform_args[@]}"
cmake --build "$build_root/piper" --parallel

funasr_work="$build_root/funasr-source"
rm -rf "$funasr_work"
rm -rf "$build_root/funasr"
rm -f "$vendor/include/funasrruntime.h"
cp -R "$funasr_source" "$funasr_work"
# FunASR's Apple guard accidentally omits MODEL_PARA's definition while
# compiling OfflineStream. Keep the ITN implementation platform-specific, but
# make the shared model-type constants available on every platform.
offline_stream="$funasr_work/include/offline-stream.h"
perl -0pi.bak -e \
  's/#if !defined\(__APPLE__\)\n#include "itn-model\.h"\n#include "com-define\.h"\n#endif/#if !defined(__APPLE__)\n#include "itn-model.h"\n#endif\n#include "com-define.h"/' \
  "$offline_stream"
rm -f "$offline_stream.bak"
# libc++ removed the deprecated std::ptr_fun adaptor; this header is compiled
# as C++17, so use equivalent lambdas for both trim helpers.
limonp_string_util="$funasr_work/third_party/jieba/include/limonp/StringUtil.hpp"
sed -i.bak \
  -e 's/std::not1(std::ptr_fun<unsigned, bool>(IsSpace))/[](unsigned c) { return !IsSpace(c); }/g' \
  -e 's/std::not1(std::bind2nd(std::equal_to<char>(), x))/[x](char c) { return c != x; }/g' \
  "$limonp_string_util"
rm -f "$limonp_string_util.bak"
openfst_header="$funasr_work/third_party/openfst/src/include/fst/fst.h"
sed -i.bak \
  -e 's/isymbols_ = impl\.isymbols_ ? impl\.isymbols_->Copy() : nullptr;/isymbols_.reset(impl.isymbols_ ? impl.isymbols_->Copy() : nullptr);/' \
  -e 's/osymbols_ = impl\.osymbols_ ? impl\.osymbols_->Copy() : nullptr;/osymbols_.reset(impl.osymbols_ ? impl.osymbols_->Copy() : nullptr);/' \
  "$openfst_header"
rm -f "$openfst_header.bak"
openfst_bitable="$funasr_work/third_party/openfst/src/include/fst/bi-table.h"
sed -i.bak 's/new S(table\.s_)/new S(*table.selector_)/' "$openfst_bitable"
rm -f "$openfst_bitable.bak"
fbank_rfft="$funasr_work/third_party/kaldi-native-fbank/kaldi-native-fbank/csrc/rfft.h"
perl -0pi.bak -e \
  's/^#include <memory>$/#include <cstdint>\n#include <memory>/m' "$fbank_rfft"
rm -f "$fbank_rfft.bak"
funasr_util="$funasr_work/src/util.h"
perl -0pi.bak -e \
  's/^#define UTIL_H$/#define UTIL_H\n#include <cstdint>/m' "$funasr_util"
rm -f "$funasr_util.bak"
funasr_tensor="$funasr_work/src/tensor.h"
sed -i.bak 's/aligned_free(buff)/AlignedFree(buff)/g' "$funasr_tensor"
rm -f "$funasr_tensor.bak"
funasr_alignedmem="$funasr_work/src/alignedmem.cpp"
perl -0pi.bak -e \
  's/^#include "precomp\.h"/#include "precomp.h"\n#include <cstdint>/m; s/\(size_t\)\(p1\)/(uintptr_t)(p1)/' \
  "$funasr_alignedmem"
rm -f "$funasr_alignedmem.bak"
sed -i.bak 's/add_library(funasr SHARED/add_library(funasr STATIC/' \
  "$funasr_work/src/CMakeLists.txt"
rm -f "$funasr_work/src/CMakeLists.txt.bak"
cmake -S "$funasr_work" -B "$build_root/funasr" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DCMAKE_CXX_STANDARD=17 \
  -DONNXRUNTIME_DIR="$vendor" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DENABLE_FFMPEG=OFF -DFUNASR_BUILD_TESTS=OFF \
  "${cmake_platform_args[@]}" "${funasr_platform_args[@]}"
cmake --build "$build_root/funasr" --target funasr --parallel

cp "$piper_work/include/piper.h" "$vendor/include/"
cp "$funasr_work/include/funasrruntime.h" "$vendor/include/"

archives=("$vendor/lib/libonnxruntime.a")
while IFS= read -r archive; do archives+=("$archive"); done < <(
  find "$build_root/piper" "$build_root/funasr" -name '*.a' -type f | sort
)
if [[ "$(uname -s)" == Darwin ]]; then
  libtool -static -o "$vendor/lib/libzh_speech_deps.a" "${archives[@]}"
else
  {
    echo 'create libzh_speech_deps.a'
    for archive in "${archives[@]}"; do echo "addlib $archive"; done
    echo 'save'
    echo 'end'
  } | (cd "$vendor/lib" && ar -M)
fi

echo "Static speech dependencies installed in $vendor"
