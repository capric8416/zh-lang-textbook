from .base import PlatformAdapter
from .android import AndroidAdapter
from .ios import IOSAdapter
from .linux import LinuxAdapter
from .macos import MacOSAdapter
from .windows import WindowsAdapter


def for_target(target: str) -> PlatformAdapter:
    for adapter in (LinuxAdapter, AndroidAdapter, MacOSAdapter, IOSAdapter, WindowsAdapter):
        if target in adapter.targets:
            return adapter(target)
    raise ValueError(f"unsupported native build target: {target}")
