#!/usr/bin/env python3
"""Validate and build a minimal, deterministic GoldAdvisorMidnight release zip."""

from __future__ import annotations

import argparse
import re
import zipfile
from pathlib import Path


ADDON_NAME = "GoldAdvisorMidnight"
TOC_PATH = Path("GoldAdvisorMidnight.toc")


def read_release_files() -> tuple[str, list[Path]]:
    if not TOC_PATH.is_file():
        raise SystemExit("Run this tool from the GoldAdvisorMidnight addon directory.")

    version = None
    runtime_files: list[Path] = []
    for raw_line in TOC_PATH.read_text(encoding="utf-8-sig").splitlines():
        line = raw_line.strip()
        if line.startswith("## Version:"):
            version = line.split(":", 1)[1].strip()
        elif line and not line.startswith("#"):
            runtime_files.append(Path(line.replace("\\", "/")))

    if not version or not re.fullmatch(r"[0-9A-Za-z._+-]+", version):
        raise SystemExit("TOC Version is missing or unsafe for a release filename.")

    missing = [path for path in runtime_files if not path.is_file()]
    if missing:
        rendered = "\n".join(f"  {path}" for path in missing)
        raise SystemExit(f"TOC references missing runtime files:\n{rendered}")

    duplicates = sorted({path for path in runtime_files if runtime_files.count(path) > 1})
    if duplicates:
        rendered = "\n".join(f"  {path}" for path in duplicates)
        raise SystemExit(f"TOC contains duplicate runtime files:\n{rendered}")

    return version, [TOC_PATH, *runtime_files]


def write_zip(destination: Path, files: list[Path]) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            archive_name = Path(ADDON_NAME) / path
            info = zipfile.ZipInfo(archive_name.as_posix(), date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, path.read_bytes())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="validate the TOC release set without writing a zip",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("output/releases"),
        help="release artifact directory",
    )
    args = parser.parse_args()

    version, files = read_release_files()
    if args.check:
        print(f"PASS: release set {version} contains {len(files)} files")
        return 0

    destination = args.output_dir / f"{ADDON_NAME}-{version}.zip"
    write_zip(destination, files)
    print(f"Wrote {destination} ({len(files)} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
