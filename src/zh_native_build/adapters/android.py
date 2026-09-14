import os
from .base import PlatformAdapter


class AndroidAdapter(PlatformAdapter):
    targets = ("android-arm64-v8a",)

    def environment(self) -> dict[str, str]:
        required = ("ANDROID_NDK_HOME", "ANDROID_SDK_ROOT")
        return {name: os.environ[name] for name in required if name in os.environ}
