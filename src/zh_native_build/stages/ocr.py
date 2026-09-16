"""Build the trimmed static ncnn and OpenCV OCR dependencies."""

import os
import shutil
from pathlib import Path

from ..config import BuildConfig
from ..runner import run


def _platform_args(config: BuildConfig) -> list[str]:
    if config.target == "windows-x64":
        # Match Flutter's Windows targets, which use the dynamic MSVC CRT
        # (/MD).  All static dependencies and their consumer must use the
        # same runtime to avoid LNK2038/LNK2005 failures at link time.
        return ["-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL"]
    if config.target == "android-arm64-v8a":
        return [f"-DCMAKE_TOOLCHAIN_FILE={os.environ['ANDROID_NDK_HOME']}/build/cmake/android.toolchain.cmake",
                "-DANDROID_ABI=arm64-v8a", "-DANDROID_PLATFORM=android-23", "-DANDROID_STL=c++_static"]
    if config.target.startswith("macos-"):
        return [f"-DCMAKE_OSX_ARCHITECTURES={config.target.removeprefix('macos-')}", "-DCMAKE_OSX_DEPLOYMENT_TARGET=10.15"]
    if config.target == "ios-arm64":
        return ["-DCMAKE_SYSTEM_NAME=iOS", "-DCMAKE_OSX_SYSROOT=iphoneos",
                "-DCMAKE_OSX_ARCHITECTURES=arm64", "-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0"]
    return []


def build(config: BuildConfig) -> Path:
    root = config.ocr / ".build-deps" / config.target
    source_root = config.ocr / ".build-deps/sources"
    vendor = config.ocr_vendor
    ncnn = source_root / "ncnn-20241226"
    opencv = source_root / "opencv-4.11.0"
    if vendor.exists():
        shutil.rmtree(vendor)
    vendor.mkdir(parents=True)
    common = ["-G", "Ninja", "-DCMAKE_BUILD_TYPE=Release", "-DBUILD_SHARED_LIBS=OFF",
              "-DCMAKE_POSITION_INDEPENDENT_CODE=ON", f"-DCMAKE_INSTALL_PREFIX={vendor}"]
    platform_args = _platform_args(config)
    ncnn_build = root / "ncnn"
    run(["cmake", "-S", ncnn, "-B", ncnn_build, *common, *platform_args,
         "-DNCNN_SHARED_LIB=OFF", "-DNCNN_VULKAN=OFF", "-DNCNN_BUILD_TOOLS=OFF",
         "-DNCNN_BUILD_EXAMPLES=OFF", "-DNCNN_BUILD_BENCHMARK=OFF", "-DNCNN_BUILD_TESTS=OFF"], cwd=config.app)
    run(["cmake", "--build", ncnn_build, "--parallel"], cwd=config.app)
    run(["cmake", "--install", ncnn_build], cwd=config.app)
    opencv_build = root / "opencv"
    # OpenCV defaults to a static CRT and overrides CMAKE_MSVC_RUNTIME_LIBRARY
    # for static builds unless its own CRT switch is disabled explicitly.
    opencv_args = ["-DBUILD_WITH_STATIC_CRT=OFF"] if config.target == "windows-x64" else []
    run(["cmake", "-S", opencv, "-B", opencv_build, *common, *platform_args, *opencv_args,
         "-DBUILD_LIST=core,imgproc,imgcodecs", "-DBUILD_TESTS=OFF", "-DBUILD_PERF_TESTS=OFF",
         "-DBUILD_EXAMPLES=OFF", "-DBUILD_ANDROID_EXAMPLES=OFF", "-DBUILD_ANDROID_PROJECTS=OFF",
         "-DBUILD_DOCS=OFF", "-DBUILD_opencv_apps=OFF",
         "-DBUILD_opencv_python3=OFF", "-DBUILD_PROTOBUF=OFF", "-DWITH_PROTOBUF=OFF",
         "-DWITH_FFMPEG=OFF", "-DWITH_GSTREAMER=OFF", "-DWITH_OPENCL=OFF",
         "-DWITH_OPENEXR=OFF", "-DWITH_TIFF=OFF", "-DWITH_WEBP=OFF", "-DWITH_ITT=OFF",
         "-DWITH_IPP=OFF", "-DWITH_EIGEN=OFF", "-DWITH_LAPACK=OFF",
         "-DOPENCV_FORCE_3RDPARTY_BUILD=ON"], cwd=config.app)
    run(["cmake", "--build", opencv_build, "--parallel"], cwd=config.app)
    run(["cmake", "--build", opencv_build, "--target", "ade", "--parallel"], cwd=config.app)
    run(["cmake", "--install", opencv_build], cwd=config.app)
    # CMake uses lib64 on some Linux distributions; the Flutter plugin expects
    # the portable vendor/<target>/lib layout.
    lib64 = vendor / "lib64"
    lib = vendor / "lib"
    if lib64.exists():
        lib.mkdir(exist_ok=True)
        for item in lib64.iterdir():
            destination = lib / item.name
            if destination.exists():
                if destination.is_dir():
                    shutil.rmtree(destination)
                else:
                    destination.unlink()
            shutil.move(str(item), str(destination))
        lib64.rmdir()
    # The installed ncnn/OpenCV package files contain absolute paths produced
    # before the lib64 -> lib normalization. Keep those imported targets in
    # sync with the portable layout consumed by the Flutter CMake project.
    for cmake_file in vendor.rglob("*.cmake"):
        text = cmake_file.read_text()
        normalized = text.replace("/lib64/", "/lib/")
        if normalized != text:
            cmake_file.write_text(normalized)
    # Android OpenCV installs its archives below sdk/native/staticlibs; the
    # Flutter OCR CMakeLists consumes the portable vendor/lib layout.
    android_lib = vendor / "sdk" / "native" / "staticlibs" / "arm64-v8a"
    if android_lib.exists():
        for archive in android_lib.glob("*.a"):
            shutil.copy2(archive, lib / archive.name)
    android_third_party = vendor / "sdk" / "native" / "3rdparty" / "libs" / "arm64-v8a"
    if android_third_party.exists():
        for archive in android_third_party.glob("*.a"):
            shutil.copy2(archive, lib / archive.name)
    android_headers = vendor / "sdk" / "native" / "jni" / "include"
    if android_headers.exists():
        target_headers = vendor / "include" / "opencv4"
        if target_headers.exists():
            shutil.rmtree(target_headers)
        shutil.copytree(android_headers, target_headers)
    return vendor
