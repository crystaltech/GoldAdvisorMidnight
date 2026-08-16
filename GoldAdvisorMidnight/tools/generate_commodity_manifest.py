#!/usr/bin/env python3
"""Generate the runtime commodity manifest from pinned TSM and Wago CSV data.

The addon never consumes these CSVs at runtime. This tool intersects generated
strategy outputs with TSM's observed commodity market and uses Wago ItemSparse
metadata as a structural validation layer.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import os
import shutil
import subprocess
import sys
import urllib.request
from collections import defaultdict
from pathlib import Path


REGIONS = ("us", "eu", "kr", "tw")
TSM_URL = "https://public-data.tradeskillmaster.com/retail/{region}/commodities.csv"
WAGO_URL = "https://wago.tools/db2/ItemSparse/csv?product=wow&build={build}"

# Newly released commodities can take several regional market snapshots to
# appear in TSM. Keep this list deliberately small and require live ItemSparse
# validation below. Remove an entry once the ordinary TSM union contains it.
REVIEWED_COMMODITY_EXCEPTIONS = {
    271889: "12.1 Alluring Nostrum Q1; live unbound stackable output",
    271890: "12.1 Alluring Nostrum Q2; live unbound stackable output",
}


LUA_EXTRACTOR = r'''
GAM_RECIPES_GENERATED = {}
local paths = assert(os.getenv("GAM_STRATEGY_FILES"), "GAM_STRATEGY_FILES is required")
for path in paths:gmatch("[^|]+") do
    assert(loadfile(path))()
end

local function Clean(value)
    return tostring(value or ""):gsub("[\t\r\n]", " ")
end

local function EmitOutputs(strategyIndex, groupPrefix, outputs)
    for outputIndex, output in ipairs(outputs or {}) do
        local group = groupPrefix .. tostring(outputIndex)
        for _, itemID in ipairs(output.itemIDs or {}) do
            print(table.concat({ "O", strategyIndex, group, itemID }, "\t"))
        end
    end
end

for strategyIndex, strategy in ipairs(GAM_RECIPES_GENERATED) do
    print(table.concat({
        "S",
        strategyIndex,
        Clean(strategy.id),
        Clean(strategy.profession),
        Clean(strategy.stratName),
        strategy.disabledReason and "1" or "0",
    }, "\t"))

    local outputs = strategy.outputs
    if type(outputs) ~= "table" and type(strategy.output) == "table" then
        outputs = { strategy.output }
    end
    EmitOutputs(strategyIndex, "base:", outputs)

    for variantKey, variant in pairs(strategy.rankVariants or {}) do
        local variantOutputs = variant.outputs
        if type(variantOutputs) ~= "table" and type(variant.output) == "table" then
            variantOutputs = { variant.output }
        end
        EmitOutputs(strategyIndex, "variant:" .. Clean(variantKey) .. ":", variantOutputs)
    end
end
'''


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--strategies",
        type=Path,
        nargs="+",
        default=[
            Path("Data/StratsGenerated.lua"),
            Path("Data/Strategies/Patch12_1.lua"),
        ],
        help="strategy Lua files, loaded in order",
    )
    parser.add_argument(
        "--source-dir",
        type=Path,
        default=Path("tmp/spreadsheets/commodity-sources"),
        help="directory containing downloaded source CSVs",
    )
    parser.add_argument(
        "--wago-build",
        required=True,
        help="explicit Retail build, for example 12.0.7.68887",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("Data/CommodityManifest.lua"),
        help="generated Lua manifest",
    )
    parser.add_argument(
        "--expected-count",
        type=int,
        required=True,
        help="reviewed strategy count; generation fails on drift",
    )
    parser.add_argument(
        "--download",
        action="store_true",
        help="download/replace source CSVs before generation",
    )
    parser.add_argument(
        "--allow-validation-warnings",
        action="store_true",
        help="generate despite retained IDs that conflict with Wago metadata",
    )
    return parser.parse_args()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + ".download")
    request = urllib.request.Request(url, headers={"User-Agent": "GoldAdvisorMidnight-data-tool/1"})
    try:
        with urllib.request.urlopen(request, timeout=120) as response, temporary.open("wb") as output:
            shutil.copyfileobj(response, output)
        temporary.replace(destination)
    finally:
        if temporary.exists():
            temporary.unlink()


def source_paths(source_dir: Path, wago_build: str) -> tuple[dict[str, Path], Path]:
    tsm = {region: source_dir / f"tsm-{region}-commodities.csv" for region in REGIONS}
    wago = source_dir / f"wago-itemsparse-{wago_build}.csv"
    return tsm, wago


def refresh_sources(tsm_paths: dict[str, Path], wago_path: Path, wago_build: str) -> None:
    for region, path in tsm_paths.items():
        print(f"Downloading TSM {region.upper()} commodities...", file=sys.stderr)
        download(TSM_URL.format(region=region), path)
    print(f"Downloading Wago ItemSparse build {wago_build}...", file=sys.stderr)
    download(WAGO_URL.format(build=wago_build), wago_path)


def extract_strategies(paths: list[Path]) -> list[dict[str, object]]:
    environment = os.environ.copy()
    environment["GAM_STRATEGY_FILES"] = "|".join(str(path.resolve()) for path in paths)
    result = subprocess.run(
        ["lua", "-e", LUA_EXTRACTOR],
        check=True,
        capture_output=True,
        text=True,
        env=environment,
    )

    strategies: dict[int, dict[str, object]] = {}
    for row in csv.reader(result.stdout.splitlines(), delimiter="\t"):
        if not row:
            continue
        if row[0] == "S" and len(row) == 6:
            index = int(row[1])
            strategies[index] = {
                "id": row[2],
                "profession": row[3],
                "name": row[4],
                "disabled": row[5] == "1",
                "groups": defaultdict(list),
            }
        elif row[0] == "O" and len(row) == 4:
            index = int(row[1])
            if index not in strategies:
                raise RuntimeError(f"output record precedes strategy {index}")
            groups = strategies[index]["groups"]
            assert isinstance(groups, defaultdict)
            groups[row[2]].append(int(row[3]))
        else:
            raise RuntimeError(f"unexpected Lua extractor row: {row!r}")

    return [strategies[index] for index in sorted(strategies)]


def read_tsm(paths: dict[str, Path]) -> tuple[set[int], dict[str, dict[str, str]]]:
    commodity_ids: set[int] = set()
    sources: dict[str, dict[str, str]] = {}

    for region, path in paths.items():
        updated_at = ""
        with path.open(newline="", encoding="utf-8-sig") as handle:
            reader = csv.DictReader(handle)
            required = {"itemId", "updatedAt"}
            if not reader.fieldnames or not required.issubset(reader.fieldnames):
                raise RuntimeError(f"{path} does not contain the expected TSM columns")
            for row in reader:
                commodity_ids.add(int(row["itemId"]))
                if not updated_at:
                    updated_at = row["updatedAt"]
        if not updated_at:
            raise RuntimeError(f"{path} contains no commodity rows")
        sources[region] = {
            "url": TSM_URL.format(region=region),
            "updatedAt": updated_at,
            "sha256": sha256(path),
        }

    return commodity_ids, sources


def read_wago(path: Path, referenced_ids: set[int]) -> dict[int, dict[str, object]]:
    items: dict[int, dict[str, object]] = {}
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        required = {"ID", "Display_lang", "Stackable", "Bonding", "InventoryType"}
        if not reader.fieldnames or not required.issubset(reader.fieldnames):
            raise RuntimeError(f"{path} does not contain the expected Wago ItemSparse columns")
        for row in reader:
            item_id = int(row["ID"])
            if item_id in referenced_ids:
                items[item_id] = {
                    "name": row["Display_lang"],
                    "stackable": int(row["Stackable"]),
                    "bonding": int(row["Bonding"]),
                    "inventoryType": int(row["InventoryType"]),
                }
    return items


def classify(
    strategies: list[dict[str, object]], commodity_ids: set[int]
) -> tuple[list[dict[str, object]], set[int], dict[str, int], list[str]]:
    retained: list[dict[str, object]] = []
    retained_ids: set[int] = set()
    profession_counts: dict[str, int] = defaultdict(int)
    notes: list[str] = []

    for strategy in strategies:
        if strategy["disabled"]:
            continue
        groups = strategy["groups"]
        assert isinstance(groups, defaultdict)
        if not groups:
            continue

        filtered_groups: dict[str, list[int]] = {}
        eligible = True
        for group, ids in groups.items():
            filtered = [item_id for item_id in ids if item_id in commodity_ids]
            filtered_groups[group] = filtered
            if not filtered:
                eligible = False
            elif len(filtered) != len(ids):
                rejected = sorted(set(ids) - set(filtered))
                notes.append(
                    f'{strategy["id"]} group {group}: rejected item IDs '
                    + ", ".join(str(item_id) for item_id in rejected)
                )

        if not eligible:
            continue

        retained.append(strategy)
        profession_counts[str(strategy["profession"])] += 1
        for ids in filtered_groups.values():
            retained_ids.update(ids)

    return retained, retained_ids, dict(profession_counts), notes


def validate_wago(item_ids: set[int], items: dict[int, dict[str, object]]) -> list[str]:
    warnings: list[str] = []
    for item_id in sorted(item_ids):
        item = items.get(item_id)
        if not item:
            warnings.append(f"item {item_id}: missing from Wago ItemSparse")
            continue
        if int(item["stackable"]) <= 1:
            warnings.append(f'item {item_id} ({item["name"]}): Stackable <= 1')
        if int(item["inventoryType"]) != 0:
            warnings.append(f'item {item_id} ({item["name"]}): InventoryType != 0')
        if int(item["bonding"]) != 0:
            warnings.append(f'item {item_id} ({item["name"]}): Bonding != 0')
    return warnings


def lua_string(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return f'"{escaped}"'


def render_manifest(
    *,
    strategies: list[dict[str, object]],
    retained: list[dict[str, object]],
    item_ids: set[int],
    profession_counts: dict[str, int],
    tsm_sources: dict[str, dict[str, str]],
    wago_build: str,
    wago_path: Path,
    notes: list[str],
) -> str:
    disabled_count = sum(bool(strategy["disabled"]) for strategy in strategies)
    lines = [
        "-- GoldAdvisorMidnight/Data/CommodityManifest.lua",
        "-- AUTO-GENERATED by tools/generate_commodity_manifest.py; do not edit manually.",
        "-- Commodity membership: TSM regional union plus reviewed new-item exceptions.",
        "-- Structural validation: Wago ItemSparse.",
        "GAM_COMMODITY_MANIFEST = {",
        "  schemaVersion = 1,",
        f"  rawStrategyCount = {len(strategies)},",
        f"  disabledStrategyCount = {disabled_count},",
        f"  strategyCount = {len(retained)},",
        f"  excludedStrategyCount = {len(strategies) - len(retained)},",
        f"  itemCount = {len(item_ids)},",
        "  professionCounts = {",
    ]

    for profession in sorted(profession_counts):
        lines.append(f"    [{lua_string(profession)}] = {profession_counts[profession]},")
    lines.extend(("  },", "  source = {", "    tsm = {"))

    for region in REGIONS:
        source = tsm_sources[region]
        lines.extend(
            (
                f"      [{lua_string(region)}] = {{",
                f"        url = {lua_string(source['url'])},",
                f"        updatedAt = {lua_string(source['updatedAt'])},",
                f"        sha256 = {lua_string(source['sha256'])},",
                "      },",
            )
        )

    lines.extend(
        (
            "    },",
            "    wago = {",
            f"      build = {lua_string(wago_build)},",
            f"      url = {lua_string(WAGO_URL.format(build=wago_build))},",
            f"      sha256 = {lua_string(sha256(wago_path))},",
            "    },",
            "  },",
            "  auditNotes = {",
        )
    )
    for note in sorted(notes):
        lines.append(f"    {lua_string(note)},")
    lines.extend(("  },", "  itemIDs = {"))
    for item_id in sorted(item_ids):
        lines.append(f"    [{item_id}] = true,")
    lines.extend(("  },", "}", ""))
    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    tsm_paths, wago_path = source_paths(args.source_dir, args.wago_build)
    if args.download:
        refresh_sources(tsm_paths, wago_path, args.wago_build)

    missing = [path for path in (*tsm_paths.values(), wago_path) if not path.is_file()]
    if missing:
        print("Missing source files:", file=sys.stderr)
        for path in missing:
            print(f"  {path}", file=sys.stderr)
        print("Run again with --download or populate --source-dir.", file=sys.stderr)
        return 2

    strategies = extract_strategies(args.strategies)
    commodity_ids, tsm_sources = read_tsm(tsm_paths)
    exception_notes = []
    for item_id, reason in REVIEWED_COMMODITY_EXCEPTIONS.items():
        if item_id not in commodity_ids:
            commodity_ids.add(item_id)
            exception_notes.append(f"reviewed commodity exception {item_id}: {reason}")
    retained, retained_ids, profession_counts, notes = classify(strategies, commodity_ids)
    notes.extend(exception_notes)

    referenced_ids = {
        item_id
        for strategy in strategies
        for ids in strategy["groups"].values()
        for item_id in ids
    }
    wago_items = read_wago(wago_path, referenced_ids)
    warnings = validate_wago(retained_ids, wago_items)

    print(
        f"Strategies: raw={len(strategies)} retained={len(retained)} "
        f"excluded={len(strategies) - len(retained)} items={len(retained_ids)}"
    )
    for profession in sorted(profession_counts):
        print(f"  {profession}: {profession_counts[profession]}")
    for note in sorted(notes):
        print(f"AUDIT: {note}")
    for warning in warnings:
        print(f"WARNING: {warning}", file=sys.stderr)

    if len(retained) != args.expected_count:
        print(
            f"Refusing to generate: expected {args.expected_count} retained strategies, "
            f"found {len(retained)}.",
            file=sys.stderr,
        )
        return 1
    if warnings and not args.allow_validation_warnings:
        print(
            "Refusing to generate with Wago validation warnings. Review the source data "
            "or rerun with --allow-validation-warnings and document the exception.",
            file=sys.stderr,
        )
        return 1

    rendered = render_manifest(
        strategies=strategies,
        retained=retained,
        item_ids=retained_ids,
        profession_counts=profession_counts,
        tsm_sources=tsm_sources,
        wago_build=args.wago_build,
        wago_path=wago_path,
        notes=notes,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix(args.output.suffix + ".tmp")
    temporary.write_text(rendered, encoding="utf-8")
    temporary.replace(args.output)
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
