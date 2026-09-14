import os
import subprocess
from collections.abc import Sequence


def run(command: Sequence[str], *, cwd=None, env=None, input_text: str | None = None) -> None:
    printable = " ".join(str(part) for part in command)
    print(f"[native-build] {printable}", flush=True)
    merged = os.environ.copy()
    if env:
        merged.update(env)
    subprocess.run([str(part) for part in command], cwd=cwd, env=merged,
                   input=input_text, text=input_text is not None, check=True)
