"""Fail early with actionable diagnostics before Flutter links native code."""

import json
import subprocess
from pathlib import Path

from ..config import BuildConfig


def _symbols(path: Path) -> str:
    for tool in (("nm", "-gC", path), ("nm", "-g", path), ("dumpbin", "/SYMBOLS", path)):
        try:
            result = subprocess.run([str(x) for x in tool], text=True,
                                    capture_output=True, check=False)
            if result.returncode == 0:
                return result.stdout
        except FileNotFoundError:
            continue
    return ""


def validate(config: BuildConfig) -> None:
    speech = config.speech_vendor
    ocr = config.ocr_vendor
    speech_lib = speech / "lib" / ("zh_speech_deps.lib" if config.target == "windows-x64" else "libzh_speech_deps.a")
    if not speech_lib.exists():
        raise RuntimeError(f"missing speech archive: {speech_lib}")
    re2_name = "re2.lib" if config.target == "windows-x64" else "libre2.a"
    re2_lib = speech / "lib" / re2_name
    if not re2_lib.exists():
        raise RuntimeError(f"missing staged RE2 archive: {re2_lib}")
    re2_symbols = _symbols(re2_lib)
    if not re2_symbols or not any(
        marker in re2_symbols for marker in ("re2::RE2", "3re23RE2", "RE2@re2")
    ):
        raise RuntimeError(f"RE2 archive has no RE2 definitions: {re2_lib}")
    for name in ("piper.h", "funasrruntime.h"):
        if not (speech / "include" / name).exists():
            raise RuntimeError(f"missing speech header: {name}")
    manifest = speech / "native-dependencies.json"
    if manifest.exists():
        data = json.loads(manifest.read_text())
        for archive in data.get("archives", []):
            if not Path(archive).exists():
                raise RuntimeError(f"manifest archive no longer exists: {archive}")
        declared_re2 = data.get("required", {}).get("re2")
        if declared_re2 != str(re2_lib):
            raise RuntimeError("manifest does not declare the staged RE2 dependency")
    # Static C++ symbols may be mangled differently across toolchains; archive
    # presence and manifest checks are authoritative here. Link-time checks are
    # performed by each platform's Flutter build.
    if ocr.exists():
        if not any(ocr.rglob("*ncnn*.a")) and config.target != "windows-x64":
            raise RuntimeError(f"ncnn archive not found under {ocr}")
