"""Build the FunASR ONNX runtime wrapper as a static library."""

import os
import shutil
from pathlib import Path

from ..config import BuildConfig
from ..runner import run
from .patches import patch_funasr


def build(config: BuildConfig) -> Path:
    root = config.speech / ".build-deps" / config.target
    source = config.speech / ".build-deps/sources/funasr-231ec5dda739c83f35e59e875736cde3ef1af161/runtime/onnxruntime"
    work = root / "funasr-source"
    patch_funasr(source, work)
    # The staged vendor include directory also contains the public FunASR API
    # header. FunASR's own sources include their copy, and clang treats the two
    # paths as distinct files, causing duplicate enum definitions. Hide the
    # staged copy while compiling; archive() restores it afterward.
    staged_header = config.speech_vendor / "include/funasrruntime.h"
    staged_header_backup = staged_header.with_suffix(".h.build-backup")
    if staged_header.exists():
        staged_header.replace(staged_header_backup)
    ort_root = root / "ort-staging"
    if ort_root.exists():
        shutil.rmtree(ort_root)
    (ort_root / "include").mkdir(parents=True, exist_ok=True)
    (ort_root / "lib").mkdir(parents=True, exist_ok=True)
    for header in (config.speech_vendor / "include").glob("*"):
        if header.name not in {"funasrruntime.h", "piper.h"}:
            if header.is_dir():
                shutil.copytree(header, ort_root / "include" / header.name)
            else:
                shutil.copy2(header, ort_root / "include" / header.name)
    ort_lib = config.speech_vendor / "lib" / "libonnxruntime.a"
    if ort_lib.exists():
        shutil.copy2(ort_lib, ort_root / "lib" / ort_lib.name)
    cmake_file = work / "src/CMakeLists.txt"
    text = cmake_file.read_text().replace("add_library(funasr SHARED", "add_library(funasr STATIC")
    cmake_file.write_text(text)
    args = ["cmake", "-S", work, "-B", root / "funasr", "-G", "Ninja",
            "-DCMAKE_BUILD_TYPE=Release", "-DBUILD_SHARED_LIBS=OFF",
            "-DCMAKE_POSITION_INDEPENDENT_CODE=ON", "-DCMAKE_CXX_STANDARD=17",
            f"-DONNXRUNTIME_DIR={ort_root}",
            "-DCMAKE_POLICY_VERSION_MINIMUM=3.5", "-DENABLE_FFMPEG=OFF",
            "-DFUNASR_BUILD_TESTS=OFF"]
    if config.target.startswith("macos-"):
        args += [f"-DCMAKE_OSX_ARCHITECTURES={config.target.removeprefix('macos-')}",
                 "-DCMAKE_CXX_FLAGS=-Wno-deprecated-declarations"]
    elif config.target == "ios-arm64":
        args += ["-DCMAKE_SYSTEM_NAME=iOS", "-DCMAKE_OSX_SYSROOT=iphoneos",
                 "-DCMAKE_OSX_ARCHITECTURES=arm64", "-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0"]
    elif config.target == "android-arm64-v8a":
        args += [f"-DCMAKE_TOOLCHAIN_FILE={os.environ['ANDROID_NDK_HOME']}/build/cmake/android.toolchain.cmake",
                 "-DANDROID_ABI=arm64-v8a", "-DANDROID_PLATFORM=android-24"]
    run(args, cwd=config.app)
    try:
        run(["cmake", "--build", root / "funasr", "--target", "funasr", "--parallel"], cwd=config.app)
    finally:
        if staged_header_backup.exists():
            staged_header_backup.replace(staged_header)
    return root / "funasr"
