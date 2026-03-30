#!/usr/bin/env python3
"""Generate a compact strategy coverage report from checked-in addon data."""

from __future__ import annotations

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
STRATS_PATH = REPO_ROOT / "GoldAdvisorMidnight" / "Data" / "StratsGenerated.lua"
REPORT_PATH = REPO_ROOT / "docs" / "reports" / "strategy_coverage_report.md"


def parse_recipe_blocks(text: str) -> list[dict[str, str | None]]:
    marker = "GAM_RECIPES_GENERATED[#GAM_RECIPES_GENERATED+1] = {"
    blocks: list[dict[str, str | None]] = []
    start = 0

    while True:
        idx = text.find(marker, start)
        if idx == -1:
            break

        brace_start = text.find("{", idx)
        depth = 0
        pos = brace_start
        while pos < len(text):
            ch = text[pos]
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    pos += 1
                    break
            pos += 1

        block = text[idx:pos]
        blocks.append(
            {
                "id": match_value(block, r'id = "([^"]+)"'),
                "profession": match_value(block, r'profession = "([^"]+)"'),
                "stratName": match_value(block, r'stratName = "([^"]+)"'),
                "sourceTab": match_value(block, r'sourceTab = "([^"]+)"'),
                "sourceBlock": match_value(block, r'sourceBlock = (?:"([^"]+)"|nil)'),
            }
        )
        start = pos

    return blocks


def match_value(block: str, pattern: str) -> str | None:
    match = re.search(pattern, block)
    if not match:
        return None
    return match.group(1)


def format_entry(entry: dict[str, str | None]) -> str:
    source_tab = entry.get("sourceTab") or "Unknown"
    source_block = entry.get("sourceBlock") or "n/a"
    return (
        f"- `{entry.get('id')}` | {entry.get('profession')} | "
        f"{entry.get('stratName')} | source: {source_tab} ({source_block})"
    )


def build_report(blocks: list[dict[str, str | None]]) -> str:
    workbook_backed = [b for b in blocks if b.get("sourceTab") and b["sourceTab"] != "Manual"]
    manual_shipped = [b for b in blocks if b.get("sourceTab") == "Manual"]

    lines = [
        "# Strategy Coverage Report",
        "",
        "Generated from checked-in `GoldAdvisorMidnight/Data/StratsGenerated.lua`.",
        "This audit only uses repo-visible data and does not load addon runtime modules.",
        "",
        "## Workbook-backed and shipped",
        "",
        f"Count: {len(workbook_backed)}",
        "",
    ]
    lines.extend(format_entry(entry) for entry in workbook_backed)
    lines.extend(
        [
            "",
            "## Manual and shipped",
            "",
            f"Count: {len(manual_shipped)}",
            "",
        ]
    )
    if manual_shipped:
        lines.extend(format_entry(entry) for entry in manual_shipped)
    else:
        lines.append("- None found in checked-in shipped data.")

    lines.extend(
        [
            "",
            "## Workbook-only and missing",
            "",
            (
                "- None discoverable from checked-in repo data. The repository currently does not "
                "include a separate workbook strategy index beyond the shipped generated recipe table, "
                "so there is no authoritative local source for workbook entries that exist outside the "
                "addon payload."
            ),
            "",
        ]
    )
    return "\n".join(lines)


def main() -> int:
    text = STRATS_PATH.read_text(encoding="utf-8")
    blocks = parse_recipe_blocks(text)
    REPORT_PATH.write_text(build_report(blocks), encoding="utf-8")
    print(f"Wrote {REPORT_PATH.relative_to(REPO_ROOT)} ({len(blocks)} strategies)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
