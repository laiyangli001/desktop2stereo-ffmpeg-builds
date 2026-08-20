#!/usr/bin/env python3
from __future__ import annotations

from collections import deque
from pathlib import Path
import shutil
import subprocess
import sys


def command(*arguments: str) -> str:
    return subprocess.check_output(arguments, text=True, encoding="utf-8").strip()


def dependencies(binary: Path) -> list[str]:
    lines = command("otool", "-L", str(binary)).splitlines()[1:]
    result: list[str] = []
    for line in lines:
        value = line.strip().split(" (", 1)[0]
        if value.startswith(("/opt/homebrew/", "/usr/local/")):
            result.append(value)
    return result


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: bundle-macos.py FFMPEG_PREFIX")
    prefix = Path(sys.argv[1]).resolve()
    bin_dir = prefix / "bin"
    lib_dir = prefix / "lib"
    queue = deque([bin_dir / "ffmpeg", bin_dir / "ffprobe"])
    queue.extend(path for path in lib_dir.glob("*.dylib") if path.is_file())
    processed: set[Path] = set()

    while queue:
        binary = queue.popleft()
        binary = binary.resolve()
        if binary in processed or not binary.is_file():
            continue
        processed.add(binary)
        for original in dependencies(binary):
            source = Path(original)
            destination = lib_dir / source.name
            if not destination.exists():
                shutil.copy2(source, destination)
                destination.chmod(0o755)
                queue.append(destination)
            subprocess.run(
                ["install_name_tool", "-change", original, f"@rpath/{source.name}", str(binary)],
                check=True,
            )

    for executable in (bin_dir / "ffmpeg", bin_dir / "ffprobe"):
        subprocess.run(
            ["install_name_tool", "-add_rpath", "@executable_path/../lib", str(executable)],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    for library in lib_dir.glob("*.dylib"):
        subprocess.run(
            ["install_name_tool", "-id", f"@rpath/{library.name}", str(library)], check=True
        )
        subprocess.run(
            ["install_name_tool", "-add_rpath", "@loader_path", str(library)],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


if __name__ == "__main__":
    main()
