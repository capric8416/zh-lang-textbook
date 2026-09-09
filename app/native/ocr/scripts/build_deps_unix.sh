#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <linux-x64|android-arm64-v8a|macos-x86_64|macos-arm64|ios-arm64>" >&2
  exit 2
fi

target="$1"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ocr_root="$(cd "${script_dir}/.." && pwd)"
deps_root="${ocr_root}/.build-deps"
source_root="${deps_root}/sources"
build_root="${deps_root}/${target}"
vendor_root="${ocr_root}/vendor/${target}"
opencv_source="${source_root}/opencv-4.11.0"
ncnn_source="${source_root}/ncnn-20241226"

mkdir -p "${source_root}" "${build_root}"

if [[ ! -d "${opencv_source}/.git" ]]; then
  git clone --depth 1 --branch 4.11.0 \
    https://github.com/opencv/opencv.git "${opencv_source}"
fi
if [[ ! -d "${ncnn_source}/.git" ]]; then
  git clone --depth 1 --branch 20241226 \
    https://github.com/Tencent/ncnn.git "${ncnn_source}"
fi

cmake -E remove_directory "${vendor_root}"
mkdir -p "${vendor_root}"

platform_args=()
opencv_platform_args=()
openmp=OFF
case "${target}" in
  linux-x64)
    openmp=ON
    ;;
  android-arm64-v8a)
    : "${ANDROID_NDK_HOME:?ANDROID_NDK_HOME must point to Android NDK}"
    platform_args+=(
      "-DCMAKE_TOOLCHAIN_FILE=${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake"
      "-DANDROID_ABI=arm64-v8a"
      "-DANDROID_PLATFORM=android-23"
      "-DANDROID_STL=c++_static"
    )
    opencv_platform_args+=("-DBUILD_ANDROID_PROJECTS=OFF")
    ;;
  macos-x86_64)
    platform_args+=("-DCMAKE_OSX_ARCHITECTURES=x86_64" "-DCMAKE_OSX_DEPLOYMENT_TARGET=10.15")
    ;;
  macos-arm64)
    platform_args+=("-DCMAKE_OSX_ARCHITECTURES=arm64" "-DCMAKE_OSX_DEPLOYMENT_TARGET=10.15")
    ;;
  ios-arm64)
    platform_args+=(
      "-DCMAKE_SYSTEM_NAME=iOS"
      "-DCMAKE_OSX_SYSROOT=iphoneos"
      "-DCMAKE_OSX_ARCHITECTURES=arm64"
      "-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0"
    )
    ;;
  *)
    echo "unsupported target: ${target}" >&2
    exit 2
    ;;
esac

common_args=(
  -G Ninja
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
  "-DCMAKE_INSTALL_PREFIX=${vendor_root}"
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  -DBUILD_SHARED_LIBS=OFF
)

cmake -S "${ncnn_source}" -B "${build_root}/ncnn" \
  "${common_args[@]}" "${platform_args[@]}" \
  -DNCNN_VERSION=20241226 \
  -DNCNN_SHARED_LIB=OFF \
  "-DNCNN_OPENMP=${openmp}" \
  -DNCNN_VULKAN=OFF \
  -DNCNN_BUILD_TOOLS=OFF \
  -DNCNN_BUILD_EXAMPLES=OFF \
  -DNCNN_BUILD_BENCHMARK=OFF \
  -DNCNN_BUILD_TESTS=OFF
cmake --build "${build_root}/ncnn" --parallel
cmake --install "${build_root}/ncnn"

cmake -S "${opencv_source}" -B "${build_root}/opencv" \
  "${common_args[@]}" "${platform_args[@]}" "${opencv_platform_args[@]}" \
  -DBUILD_LIST=core,imgproc,imgcodecs \
  -DBUILD_opencv_apps=OFF \
  -DBUILD_opencv_java=OFF \
  -DBUILD_opencv_python2=OFF \
  -DBUILD_opencv_python3=OFF \
  -DBUILD_EXAMPLES=OFF \
  -DBUILD_PERF_TESTS=OFF \
  -DBUILD_TESTS=OFF \
  -DBUILD_DOCS=OFF \
  -DBUILD_PROTOBUF=OFF \
  -DWITH_PROTOBUF=OFF \
  -DWITH_FLATBUFFERS=OFF \
  -DOPENCV_FORCE_3RDPARTY_BUILD=ON \
  -DWITH_JPEG=ON \
  -DWITH_PNG=ON \
  -DWITH_ZLIB=ON \
  -DWITH_FFMPEG=OFF \
  -DWITH_GSTREAMER=OFF \
  -DWITH_GTK=OFF \
  -DWITH_OPENCL=OFF \
  -DWITH_OPENEXR=OFF \
  -DWITH_TIFF=OFF \
  -DWITH_WEBP=OFF \
  -DWITH_ITT=OFF \
  -DWITH_IPP=OFF \
  -DWITH_KLEIDICV=OFF \
  -DWITH_LAPACK=OFF
cmake --build "${build_root}/opencv" --parallel
# OpenCV exports the optional ADE target even when G-API is excluded by
# BUILD_LIST. Build it explicitly so the installed OpenCV CMake package never
# references a missing lib/opencv4/3rdparty/libade.a archive.
cmake --build "${build_root}/opencv" --target ade --parallel
cmake --install "${build_root}/opencv"

echo "Static OCR dependencies installed in ${vendor_root}"
