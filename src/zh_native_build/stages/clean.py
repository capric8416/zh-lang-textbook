"""Remove generated native and Flutter build outputs.

Source checkouts and downloaded speech models are intentionally kept by default.
This makes a clean rebuild deterministic without forcing another network download.
"""

from __future__ import annotations

import shutil
from dataclasses import dataclass
from pathlib import Path

from ..config import BuildConfig


MODULES = ("speech", "ocr", "flutter")


@dataclass(frozen=True)
class CleanItem:
    label: str
    path: Path


def _items(config: BuildConfig, modules: set[str], purge_sources: bool) -> list[CleanItem]:
    items: list[CleanItem] = []
    if "speech" in modules:
        items.extend(
            (
                CleanItem("speech target build", config.speech / ".build-deps" / config.target),
                CleanItem("speech vendor", config.speech_vendor),
            )
        )
        if purge_sources:
            items.append(CleanItem("speech source checkouts", config.speech / ".build-deps" / "sources"))
    if "ocr" in modules:
        items.extend(
            (
                CleanItem("OCR target build", config.ocr / ".build-deps" / config.target),
                CleanItem("OCR vendor", config.ocr_vendor),
            )
        )
        if purge_sources:
            items.append(CleanItem("OCR source checkouts", config.ocr / ".build-deps" / "sources"))
    if "flutter" in modules:
        # Do not remove .dart_tool: it contains the speech model download cache.
        items.append(CleanItem("Flutter build output", config.app / "build"))
        platform = config.target.split("-", 1)[0]
        items.append(CleanItem(f"{platform} generated files", config.app / platform / "flutter" / "ephemeral"))
        for name in (".flutter-plugins", ".flutter-plugins-dependencies"):
            items.append(CleanItem(f"Flutter {name}", config.app / name))
    return items


def clean(
    config: BuildConfig,
    *,
    modules: set[str] | None = None,
    purge_sources: bool = False,
    dry_run: bool = False,
) -> list[Path]:
    """Clean generated outputs for one target and return removed paths.

    ``modules`` accepts ``speech``, ``ocr`` and ``flutter``.  Passing ``None``
    cleans all three.  Missing paths are harmless, which makes this safe to run
    before the first build.
    """

    selected = set(MODULES if modules is None else modules)
    unknown = selected - set(MODULES)
    if unknown:
        raise ValueError(f"unknown clean modules: {', '.join(sorted(unknown))}")

    removed: list[Path] = []
    for item in _items(config, selected, purge_sources):
        if not item.path.exists() and not item.path.is_symlink():
            continue
        print(f"[native-clean] {'would remove' if dry_run else 'remove'} {item.label}: {item.path}", flush=True)
        removed.append(item.path)
        if not dry_run:
            if item.path.is_dir() and not item.path.is_symlink():
                shutil.rmtree(item.path)
            else:
                item.path.unlink()
    return removed
