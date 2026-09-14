"""Build Piper as a static library against the staged ONNX Runtime."""

import os
import shutil
from pathlib import Path

from ..config import BuildConfig
from ..runner import run
from .patches import patch_piper


def build(config: BuildConfig) -> Path:
    root = config.speech / ".build-deps" / config.target
    source = config.speech / ".build-deps/sources/piper-404aefedbd74baa0bd43e451bc407a2b3aace0f5"
    work = root / "piper-source"
    patch_piper(source, work)
    # ExternalProject (espeak-ng) caches its own compiler detection; never
    # reuse a build tree across host/target changes.
    build_dir = root / "piper"
    if build_dir.exists():
        shutil.rmtree(build_dir)
    cmake_file = work / "CMakeLists.txt"
    text = cmake_file.read_text()
    text = text.replace("enable_clang_tidy(piper)",
                        'target_compile_definitions(piper PUBLIC BUILDING_LIBPIPER)\n'
                        'option(BUILD_PIPER_EXECUTABLE "Build Piper CLI" OFF)\n'
                        'if(BUILD_PIPER_EXECUTABLE)\n  add_subdirectory(src/main)\nendif()')
    text = text.replace("# ---- piper exe ---\nadd_subdirectory(src/main)\n", "")
    cmake_file.write_text(text)

    args = ["cmake", "-S", work, "-B", build_dir, "-G", "Ninja",
            "-DCMAKE_BUILD_TYPE=Release", "-DBUILD_SHARED_LIBS=OFF",
            "-DBUILD_PIPER_EXECUTABLE=OFF", "-DCMAKE_POSITION_INDEPENDENT_CODE=ON",
            f"-DONNXRUNTIME_DIR={config.speech_vendor}",
            f"-DONNXRUNTIME_LIB={config.speech_vendor / 'lib/libonnxruntime.a'}"]
    if config.target.startswith("macos-"):
        args.append(f"-DCMAKE_OSX_ARCHITECTURES={config.target.removeprefix('macos-')}")
    elif config.target == "ios-arm64":
        args += ["-DCMAKE_SYSTEM_NAME=iOS", "-DCMAKE_OSX_SYSROOT=iphoneos",
                 "-DCMAKE_OSX_ARCHITECTURES=arm64", "-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0"]
    elif config.target == "android-arm64-v8a":
        args += [f"-DCMAKE_TOOLCHAIN_FILE={os.environ['ANDROID_NDK_HOME']}/build/cmake/android.toolchain.cmake",
                 "-DANDROID_ABI=arm64-v8a", "-DANDROID_PLATFORM=android-24"]
    run(args, cwd=config.app)
    run(["cmake", "--build", build_dir, "--parallel"], cwd=config.app)
    return build_dir
