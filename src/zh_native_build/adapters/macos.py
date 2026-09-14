import platform
from .base import PlatformAdapter


class MacOSAdapter(PlatformAdapter):
    targets = ("macos-arm64", "macos-x86_64")

    def environment(self) -> dict[str, str]:
        return {"MACOS_ARCH": self.config.target.removeprefix("macos-") or platform.machine()}
