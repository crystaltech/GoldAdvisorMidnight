#!/usr/bin/env python3
"""Ensure GitHub contains only the public addon, README, and license."""

from __future__ import annotations

import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
ROOT_FILES = {"README.md", "LICENSE"}
ADDON_NAME = "GoldAdvisorMidnightDev" if (REPO_ROOT / "GoldAdvisorMidnightDev").is_dir() else "GoldAdvisorMidnight"
ADDON_PREFIX = f"{ADDON_NAME}/"


def tracked_files() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
    )
    return sorted(
        value.decode("utf-8")
        for value in result.stdout.split(b"\0")
        if value
    )


def main() -> int:
    tracked = tracked_files()
    unexpected = [
        path
        for path in tracked
        if path not in ROOT_FILES and not path.startswith(ADDON_PREFIX)
    ]
    missing = sorted(ROOT_FILES - set(tracked))
    addon_files = [path for path in tracked if path.startswith(ADDON_PREFIX)]

    if unexpected or missing or not addon_files:
        if unexpected:
            print("Unexpected public files:")
            for path in unexpected:
                print(f"  {path}")
        if missing:
            print("Missing required public files:")
            for path in missing:
                print(f"  {path}")
        if not addon_files:
            print("No addon files are tracked.")
        return 1

    print(
        "PASS: GitHub boundary contains README.md, LICENSE, and "
        f"{len(addon_files)} addon files only"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
