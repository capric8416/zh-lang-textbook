"""High-level native dependency pipelines."""

from .stages.archive import build as build_archive
from .stages.checkout import checkout_sources
from .stages.funasr import build as build_funasr
from .stages.ocr import build as build_ocr
from .stages.onnxruntime import build as build_ort
from .stages.patches import patch_onnxruntime
from .stages.piper import build as build_piper
from .stages.re2 import build as build_re2
from .stages.validate import validate


def speech(config) -> None:
    checkout_sources(config.root)
    patch_onnxruntime(config.speech / ".build-deps/sources/onnxruntime-v1.22.0")
    build_ort(config)
    build_re2(config)
    build_piper(config)
    build_funasr(config)
    build_archive(config)
    validate(config)


def ocr(config) -> None:
    checkout_sources(config.root)
    build_ocr(config)


def all_components(config) -> None:
    ocr(config)
    speech(config)
