from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class BuildConfig:
    root: Path
    target: str

    @property
    def app(self) -> Path:
        return self.root / "app"

    @property
    def ocr(self) -> Path:
        return self.app / "native" / "ocr"

    @property
    def speech(self) -> Path:
        return self.app / "native" / "speech"

    @property
    def ocr_vendor(self) -> Path:
        return self.ocr / "vendor" / self.target

    @property
    def speech_vendor(self) -> Path:
        return self.speech / "vendor" / self.target
