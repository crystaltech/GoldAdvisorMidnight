#!/usr/bin/env python3
"""Extract one version's Markdown body from the local changelog."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


SEMVER = re.compile(r"\d+\.\d+\.\d+")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("output", type=Path)
    parser.add_argument("--changelog", type=Path, default=Path("CHANGELOG.md"))
    args = parser.parse_args()

    if not SEMVER.fullmatch(args.version):
        raise SystemExit(f"Version must use MAJOR.MINOR.PATCH: {args.version!r}")
    if not args.changelog.is_file():
        raise SystemExit(f"Changelog not found: {args.changelog}")

    source = args.changelog.read_text(encoding="utf-8-sig")
    heading = re.compile(
        rf"(?m)^## \[{re.escape(args.version)}\][^\r\n]*\r?\n"
    )
    match = heading.search(source)
    if not match:
        raise SystemExit(f"Changelog has no [{args.version}] release section")

    next_heading = re.search(r"(?m)^## (?:\[|Unreleased\b)", source[match.end() :])
    end = match.end() + next_heading.start() if next_heading else len(source)
    body = source[match.end() : end].strip()
    if not body:
        raise SystemExit(f"Changelog section [{args.version}] is empty")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(body + "\n", encoding="utf-8", newline="\n")
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
