"""Build and stage ONNX Runtime's pinned RE2 dependency."""

import shutil
from pathlib import Path

from ..config import BuildConfig
from ..runner import run


def _library_name(config: BuildConfig) -> str:
    return "re2.lib" if config.target == "windows-x64" else "libre2.a"


def _find_built_library(config: BuildConfig, build_dir: Path) -> Path | None:
    name = _library_name(config)
    candidates = sorted(
        path for path in (build_dir / "Release").rglob(name)
        if "re2-build" in path.as_posix()
    )
    return candidates[0] if candidates else None


def build(config: BuildConfig) -> Path:
    """Build the RE2 target from ORT's configured FetchContent tree."""
    root = config.speech / ".build-deps" / config.target
    ort_build = root / "onnxruntime"
    release = ort_build / "Release"
    staged = config.speech_vendor / "lib" / _library_name(config)
    if not release.exists():
        raise RuntimeError(
            f"ONNX Runtime must be configured before RE2: {release}"
        )

    parallel = "2" if config.target == "android-arm64-v8a" else ""
    target_build = release
    if config.target == "windows-x64":
        # With the Visual Studio generator FetchContent's RE2 project is
        # emitted only in its nested build tree, not as re2.vcxproj in ORT's
        # top-level solution.
        nested = release / "_deps" / "re2-build"
        if nested.exists() and not any(release.glob("re2.vcxproj")):
            target_build = nested
    command = ["cmake", "--build", target_build, "--config", "Release",
               "--target", "re2", "--parallel"]
    if parallel:
        command.append(parallel)
    run(command, cwd=config.app)

    built = _find_built_library(config, ort_build)
    if built is None:
        raise RuntimeError(
            f"RE2 target completed without producing {_library_name(config)}"
        )
    staged.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(built, staged)
    return staged
