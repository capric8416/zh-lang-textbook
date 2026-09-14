from .base import PlatformAdapter


class WindowsAdapter(PlatformAdapter):
    targets = ("windows-x64",)

    def environment(self) -> dict[str, str]:
        return {}
