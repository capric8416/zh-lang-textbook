import os
from .base import PlatformAdapter


class LinuxAdapter(PlatformAdapter):
    targets = ("linux-x64",)

    def environment(self) -> dict[str, str]:
        return {"CC": os.environ.get("CC", "clang"), "CXX": os.environ.get("CXX", "clang++")}
