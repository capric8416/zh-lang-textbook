"""Collect native static libraries and create a reproducible manifest."""

import json
import os
import shutil
from pathlib import Path

from ..config import BuildConfig
from ..runner import run


def _find(build: Path, suffix: str) -> list[Path]:
    return sorted(p for p in build.rglob(f"*{suffix}")
                  if "test" not in p.name.lower() and "benchmark" not in p.name.lower())


def _archiver(config: BuildConfig) -> str:
    if config.target == "android-arm64-v8a":
        prebuilt = Path(os.environ["ANDROID_NDK_HOME"]) / "toolchains/llvm/prebuilt"
        candidates = sorted(prebuilt.glob("*/bin/llvm-ar"))
        if not candidates:
            raise RuntimeError(f"Android llvm-ar not found under {prebuilt}")
        return str(candidates[0])
    return shutil.which("ar") or "ar"


def build(config: BuildConfig) -> Path:
    root = config.speech / ".build-deps" / config.target
    vendor = config.speech_vendor
    vendor.mkdir(parents=True, exist_ok=True)
    (vendor / "lib").mkdir(parents=True, exist_ok=True)
    (vendor / "include").mkdir(parents=True, exist_ok=True)
    ext = ".lib" if config.target == "windows-x64" else ".a"
    re2_name = "re2.lib" if config.target == "windows-x64" else "libre2.a"
    re2 = vendor / "lib" / re2_name
    ort = [path for path in _find(root / "onnxruntime", ext)
           if path.name.lower() != re2_name.lower()]
    piper = _find(root / "piper", ext)
    funasr = _find(root / "funasr", ext)
    if not ort or not piper or not funasr or not re2.exists():
        raise RuntimeError("missing ONNX Runtime, RE2, Piper, or FunASR static archive")
    # Piper's espeak ExternalProject leaves both its build-tree archive and
    # the installed archive in the staging tree. They contain the same
    # objects; adding both causes duplicate symbols when the iOS archive is
    # force-loaded (and is also unnecessary on other platforms).
    espeak_name = "espeak-ng.lib" if ext == ".lib" else "libespeak-ng.a"
    espeak_archives = [p for p in piper if p.name.lower() == espeak_name.lower()]
    if espeak_archives:
        installed = [p for p in espeak_archives if "espeak_ng-install" in p.parts]
        keep_espeak = sorted(installed or espeak_archives)[0]
        piper = [p for p in piper if p.name.lower() != espeak_name.lower()]
        piper.append(keep_espeak)
    key = lambda p: p.name.lower()
    ort_main = next((p for p in ort if "onnxruntime" in key(p)), ort[0])
    staged_ort = vendor / "lib" / ("onnxruntime.lib" if ext == ".lib" else "libonnxruntime.a")
    if staged_ort.exists():
        ort_main = staged_ort
    inputs = [ort_main]
    # ONNX Runtime's static build keeps protobuf/ONNX/absl/re2 in separate
    # archives; retain every target archive so the final plugin link resolves
    # the transitive symbols.
    inputs += [
        path for path in ort
        if path != ort_main and not (
            staged_ort.exists() and "onnxruntime" in path.name.lower()
        )
    ]
    inputs.append(re2)
    inputs += [p for p in piper + funasr if p not in inputs]
    output = vendor / "lib" / ("zh_speech_deps.lib" if ext == ".lib" else "libzh_speech_deps.a")
    if output.exists():
        output.unlink()
    if config.target == "windows-x64":
        run(["lib.exe", "/NOLOGO", f"/OUT:{output}", *inputs], cwd=config.app)
    elif config.target.startswith(("macos-", "ios-")):
        run(["libtool", "-static", "-o", output, *inputs], cwd=config.app)
    else:
        script = "create " + str(output) + "\n" + "\n".join(f"addlib {p}" for p in inputs) + "\nsave\nend\n"
        ar = _archiver(config)
        run([ar, "-M"], cwd=config.app, input_text=script)
    # Expose the two public C/C++ headers consumed by the Flutter plugin.
    piper_header = root / "piper-source" / "include" / "piper.h"
    funasr_header = root / "funasr-source" / "include" / "funasrruntime.h"
    for header in (piper_header, funasr_header):
        if header.exists():
            target = vendor / "include" / header.name
            shutil.copy2(header, target)
            if header.name == "funasrruntime.h":
                text = target.read_text()
                if not text.startswith("#pragma once"):
                    target.write_text("#pragma once\n" + text)
    manifest = vendor / "native-dependencies.json"
    manifest.write_text(json.dumps({"target": config.target,
                                    "required": {"re2": str(re2)},
                                    "archives": [str(p) for p in inputs],
                                    "output": str(output)}, indent=2) + "\n")
    return output
