from abc import ABC, abstractmethod
from pathlib import Path

from ..config import BuildConfig


class PlatformAdapter(ABC):
    targets: tuple[str, ...] = ()

    def __init__(self, target: str):
        self.config = BuildConfig(Path(__file__).resolve().parents[3], target)

    @abstractmethod
    def environment(self) -> dict[str, str]:
        """Return platform-specific toolchain environment overrides."""

    def build(self, component: str) -> None:
        from ..pipeline import all_components, ocr, speech
        {"ocr": ocr, "speech": speech, "all": all_components}[component](self.config)
