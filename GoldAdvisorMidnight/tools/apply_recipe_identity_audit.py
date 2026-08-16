#!/usr/bin/env python3
"""Apply high-confidence recipe identities from the pinned Wago audit.

The audit CSV is the source of resolved IDs/names. By default this is a dry
run; pass --apply to update the checked-in compact and runtime catalogs.
"""

from __future__ import annotations

import argparse
import csv
import io
import subprocess
from collections import defaultdict
from pathlib import Path


def load_catalog_rows() -> dict[str, dict[str, str]]:
    result = subprocess.run(
        ["lua", "tools/audit_recipe_catalog.lua", "--catalog-tsv"],
        check=True,
        capture_output=True,
        text=True,
    )
    return {
        row["strategy_id"]: row
        for row in csv.DictReader(io.StringIO(result.stdout), delimiter="\t")
        if row["record_type"] == "strategy"
    }


def lua_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def find_unique_line(lines: list[str], expected: str, path: Path) -> int:
    matches = [index for index, line in enumerate(lines) if line == expected]
    if len(matches) != 1:
        raise RuntimeError(
            f"{path}: expected one {expected!r} line, found {len(matches)}"
        )
    return matches[0]


def upsert_near_id(
    lines: list[str],
    path: Path,
    strategy_id: str,
    indent: str,
    anchor_key: str,
    fields: list[tuple[str, str]],
) -> list[str]:
    id_index = find_unique_line(
        lines, f'{indent}id = "{lua_string(strategy_id)}",', path
    )
    search_end = min(len(lines), id_index + 20)
    changed = []

    for key, rendered_value in fields:
        prefix = f"{indent}{key} = "
        indexes = [
            index
            for index in range(id_index, search_end)
            if lines[index].startswith(prefix)
        ]
        desired = f"{prefix}{rendered_value},"
        if indexes:
            if lines[indexes[0]] != desired:
                raise RuntimeError(
                    f"{path}: refusing to replace existing {key} for {strategy_id}: "
                    f"{lines[indexes[0]]!r}"
                )
            continue

        anchor_prefix = f"{indent}{anchor_key} = "
        anchor_indexes = [
            index
            for index in range(id_index, search_end)
            if lines[index].startswith(anchor_prefix)
        ]
        if len(anchor_indexes) != 1:
            raise RuntimeError(
                f"{path}: cannot locate {anchor_key} for {strategy_id}"
            )
        insert_at = anchor_indexes[0] + 1
        while insert_at < search_end and any(
            lines[insert_at].startswith(f"{indent}{prior_key} = ")
            for prior_key, _ in fields
        ):
            insert_at += 1
        lines.insert(insert_at, desired)
        search_end += 1
        changed.append(key)

    return changed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument(
        "--audit-csv",
        type=Path,
        default=Path("output/spreadsheet/recipe_catalog_audit.csv"),
    )
    args = parser.parse_args()

    current = load_catalog_rows()
    with args.audit_csv.open("r", encoding="utf-8", newline="") as handle:
        audit_rows = list(csv.DictReader(handle))

    runtime_path = Path("Data/StratsGenerated.lua")
    runtime_lines = runtime_path.read_text(encoding="utf-8").splitlines()
    compact_lines: dict[Path, list[str]] = {}
    changes: dict[str, list[str]] = defaultdict(list)

    for audit in audit_rows:
        strategy_id = audit["strategy_id"]
        catalog = current[strategy_id]
        resolved_id = audit["resolved_recipe_id"]
        recipe_name = audit["wago_recipe_name"]
        if not resolved_id or not recipe_name:
            continue

        if not catalog["recipe_id"]:
            compact_path = Path("Data/Professions") / f'{audit["profession"]}.lua'
            compact = compact_lines.setdefault(
                compact_path,
                compact_path.read_text(encoding="utf-8").splitlines(),
            )
            changed = upsert_near_id(
                compact,
                compact_path,
                strategy_id,
                "    ",
                "patchTag",
                [("recipeID", resolved_id)],
            )
            changes[str(compact_path)].extend(
                f"{strategy_id}: {field}" for field in changed
            )

        runtime_fields = []
        if not catalog["recipe_id"]:
            runtime_fields.append(("recipeID", resolved_id))
        if not catalog["recipe_name"]:
            runtime_fields.append(("recipeName", f'"{lua_string(recipe_name)}"'))
        if runtime_fields:
            changed = upsert_near_id(
                runtime_lines,
                runtime_path,
                strategy_id,
                "  ",
                "stratName",
                runtime_fields,
            )
            changes[str(runtime_path)].extend(
                f"{strategy_id}: {field}" for field in changed
            )

    total = sum(len(items) for items in changes.values())
    print(f"Planned field insertions: {total}")
    for path, items in sorted(changes.items()):
        print(f"  {path}: {len(items)}")

    if not args.apply:
        print("Dry run only; rerun with --apply to write changes.")
        return 0

    runtime_path.write_text("\n".join(runtime_lines) + "\n", encoding="utf-8")
    for path, lines in compact_lines.items():
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("Applied recipe identity corrections.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
