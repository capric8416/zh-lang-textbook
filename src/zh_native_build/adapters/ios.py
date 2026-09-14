from .base import PlatformAdapter


class IOSAdapter(PlatformAdapter):
    targets = ("ios-arm64",)

    def environment(self) -> dict[str, str]:
        return {"APPLE_PLATFORM": "iphoneos", "APPLE_ARCH": "arm64"}
