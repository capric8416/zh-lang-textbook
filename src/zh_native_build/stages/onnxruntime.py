"""Build the pinned static ONNX Runtime dependency."""

import os
import platform
import shutil
from pathlib import Path

from ..config import BuildConfig
from ..runner import run


ORT_NAME = "onnxruntime-v1.22.0"


def _archiver(config: BuildConfig) -> str:
    if config.target == "android-arm64-v8a":
        prebuilt = Path(os.environ["ANDROID_NDK_HOME"]) / "toolchains/llvm/prebuilt"
        candidates = sorted(prebuilt.glob("*/bin/llvm-ar"))
        if not candidates:
            raise RuntimeError(f"Android llvm-ar not found under {prebuilt}")
        return str(candidates[0])
    return shutil.which("ar") or "ar"


def _component_archives(config: BuildConfig, release: Path) -> list[Path]:
    if config.target == "windows-x64":
        return sorted(
            path for path in release.rglob("onnxruntime*.lib")
            if "test" not in path.name.lower()
        )
    return sorted(release.glob("libonnxruntime_*.a"))


def _stage_headers(config: BuildConfig, source: Path, release: Path) -> None:
    """Stage the public ORT headers in the flat layout expected by consumers.

    The ORT source tree keeps the C/C++ API below
    ``include/onnxruntime/core/session`` while Piper includes
    ``<onnxruntime_cxx_api.h>`` directly.  Official ORT packages flatten these
    public session headers, so reproduce that layout in our vendor directory.
    """
    vendor_include = config.speech_vendor / "include"
    vendor_include.mkdir(parents=True, exist_ok=True)
    for header in release.glob("*.h"):
        shutil.copy2(header, vendor_include / header.name)
    source_include = source / "include"
    for header in source_include.glob("*.h"):
        shutil.copy2(header, vendor_include / header.name)
    session_include = source_include / "onnxruntime/core/session"
    for header in session_include.glob("*.h"):
        shutil.copy2(header, vendor_include / header.name)


def build(config: BuildConfig) -> Path:
    source = config.speech / ".build-deps" / "sources" / ORT_NAME
    build_dir = config.speech / ".build-deps" / config.target / "onnxruntime"
    done = build_dir.parent / "onnxruntime.done"
    release = build_dir / "Release"
    staged_name = "onnxruntime.lib" if config.target == "windows-x64" else "libonnxruntime.a"
    staged = config.speech_vendor / "lib" / staged_name
    if done.exists() and _component_archives(config, release) and staged.exists():
        _stage_headers(config, source, release)
        return build_dir
    if done.exists():
        done.unlink()

    command = [
        source / ("build.bat" if config.target == "windows-x64" else "build.sh"),
        "--config", "Release", "--build_dir", build_dir,
        "--skip_tests",
        "--cmake_extra_defines",
        "onnxruntime_BUILD_UNIT_TESTS=OFF",
        "onnxruntime_BUILD_BENCHMARKS=OFF",
    ]
    if config.target == "android-arm64-v8a":
        command[5:5] = ["--parallel", "2"]
    else:
        command[5:5] = ["--parallel"]
        # ORT's GCC build enables -Werror by default.  GCC 14 reports a
        # maybe-uninitialized diagnostic in the upstream NCHWc optimizer;
        # this is a third-party warning and must not fail the dependency build.
        # Android is excluded because its bundled CMake 3.22 does not support
        # the flag emitted by ORT's build.py.
        command += ["--compile_no_warning_as_error"]
    if config.target == "windows-x64":
        command += ["--cmake_generator", "Visual Studio 17 2022"]
    elif config.target.startswith("macos-"):
        command += ["--osx_arch", config.target.removeprefix("macos-")]
    elif config.target == "ios-arm64":
        command += ["--ios", "--apple_sysroot", "iphoneos", "--osx_arch", "arm64",
                    "--apple_deploy_target", "13.0"]
    elif config.target == "android-arm64-v8a":
        command += ["--android", "--android_sdk_path", os.environ["ANDROID_SDK_ROOT"],
                    "--android_ndk_path", os.environ["ANDROID_NDK_HOME"],
                    "--android_abi", "arm64-v8a", "--android_api", "24"]
    elif config.target != "linux-x64":
        raise ValueError(f"unsupported target: {config.target}")

    if platform.system() == "Linux" and os.geteuid() == 0:
        command.append("--allow_running_as_root")
    run(command, cwd=source)
    # Stage a single ORT archive for Piper/FunASR consumers.
    archives = _component_archives(config, release)
    if not archives:
        raise RuntimeError(f"ONNX Runtime produced no static archives under {release}")
    vendor = config.speech_vendor
    (vendor / "lib").mkdir(parents=True, exist_ok=True)
    (vendor / "include").mkdir(parents=True, exist_ok=True)
    if config.target == "windows-x64":
        run(["lib.exe", "/NOLOGO", f"/OUT:{staged}", *archives], cwd=config.app)
    elif config.target.startswith(("macos-", "ios-")):
        # Apple ships BSD ar, which has no GNU MRI (-M) mode.  libtool is the
        # native static archive combiner on macOS and iOS.
        run(["libtool", "-static", "-o", staged, *archives], cwd=config.app)
    else:
        script = "create " + str(staged) + "\n" + "\n".join(f"addlib {p}" for p in archives) + "\nsave\nend\n"
        run([_archiver(config), "-M"], cwd=config.app, input_text=script)
    _stage_headers(config, source, release)
    fallback = config.speech / "vendor/linux-x64/include"
    if config.target == "android-arm64-v8a" and fallback.exists():
        for header in fallback.glob("*.h"):
            target = vendor / "include" / header.name
            if not target.exists():
                shutil.copy2(header, target)
    done.parent.mkdir(parents=True, exist_ok=True)
    done.touch()
    return build_dir
