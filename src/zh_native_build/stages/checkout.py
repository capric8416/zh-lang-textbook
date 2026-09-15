from dataclasses import dataclass
from pathlib import Path

from ..runner import run


@dataclass(frozen=True)
class Source:
    name: str
    url: str
    revision: str
    component: str


SOURCES = (
    Source("onnxruntime-v1.22.0", "https://github.com/microsoft/onnxruntime.git", "f217402897f40ebba457e2421bc0a4702771968e", "speech"),
    Source("piper-404aefedbd74baa0bd43e451bc407a2b3aace0f5", "https://github.com/OHF-Voice/piper1-gpl.git", "404aefedbd74baa0bd43e451bc407a2b3aace0f5", "speech"),
    Source("funasr-231ec5dda739c83f35e59e875736cde3ef1af161", "https://github.com/modelscope/FunASR.git", "231ec5dda739c83f35e59e875736cde3ef1af161", "speech"),
    Source("nlohmann-json-3.11.3", "https://github.com/nlohmann/json.git", "v3.11.3", "speech"),
    Source("opencv-4.11.0", "https://github.com/opencv/opencv.git", "4.11.0", "ocr"),
    Source("ncnn-20241226", "https://github.com/Tencent/ncnn.git", "20241226", "ocr"),
)


def checkout_sources(root: Path) -> dict[str, str]:
    revisions: dict[str, str] = {}
    for source in SOURCES:
        path = root / "app" / "native" / source.component / ".build-deps" / "sources" / source.name
        path.parent.mkdir(parents=True, exist_ok=True)
        if not (path / ".git").exists():
            run(["git", "init", "-q", path])
            run(["git", "-C", path, "remote", "add", "origin", source.url])
        result = __import__("subprocess").run(
            ["git", "-C", path, "rev-parse", "--verify", f"{source.revision}^{{commit}}"],
            text=True, capture_output=True,
        )
        fetched = result.returncode != 0
        if fetched:
            run(["git", "-C", path, "fetch", "--depth", "1", "origin", source.revision])
        # A shallow fetch of a tag/revision updates FETCH_HEAD but does not
        # necessarily create a local tag or branch (notably OpenCV 4.11.0).
        # Checkout FETCH_HEAD immediately after fetching; use the named ref
        # only when it was already present locally.
        checkout_ref = "FETCH_HEAD" if fetched else source.revision
        run(["git", "-C", path, "checkout", "-q", "--detach", checkout_ref])
        # FunASR and ONNX Runtime keep required headers/libraries in submodules.
        # Initialize them explicitly because this lightweight checkout does not
        # use `git clone --recurse-submodules`.
        if source.name.startswith(("funasr-", "onnxruntime-")):
            run(["git", "-C", path, "submodule", "update", "--init", "--recursive"])
        revisions[source.name] = source.revision
    return revisions
