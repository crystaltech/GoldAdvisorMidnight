#!/usr/bin/env python3
"""Join the retained GAM catalog to pinned Wago DB2 CSV exports.

This script intentionally uses only the Python standard library. Run it from
the addon directory after downloading the pinned Wago tables to /tmp:

    python3 tools/audit_wago_recipe_data.py
"""

from __future__ import annotations

import argparse
import csv
import io
import re
import subprocess
from collections import Counter, defaultdict
from pathlib import Path


BUILD = "12.1.0.69299"
WAGO_BASE = "https://wago.tools/db2"

PROFESSION_SKILL_LINES = {
    "Alchemy": 171,
    "Blacksmithing": 164,
    "Cooking": 185,
    "Enchanting": 333,
    "Engineering": 202,
    "Inscription": 773,
    "Jewelcrafting": 755,
    "Leatherworking": 165,
    "Tailoring": 197,
}

# Generic salvage/processing spells intentionally back several strategy views.
# The last entry is a punctuation/name correction whose identity is otherwise
# exact in the pinned SpellName and SkillLineAbility data.
GENERIC_RECIPE_IDS = {
    "inscription__tranquility_bloom_milling__midnight_1": 1269575,
    "inscription__argentleaf_milling__midnight_1": 1269575,
    "inscription__sanguithorn_milling__midnight_1": 1269575,
    "inscription__mana_lily_milling__midnight_1": 1269575,
    "jewelcrafting__refulgent_copper_ore_prospecting__midnight_1": 1231127,
    "jewelcrafting__brilliant_silver_ore_prospecting__midnight_1": 1231127,
    "jewelcrafting__umbral_tin_ore_prospecting__midnight_1": 1231127,
    "jewelcrafting__dazzling_thorium_prospecting__midnight_1": 1231127,
    "jewelcrafting__crushing__midnight_1": 1231132,
    "engineering__recycling_argentleaf_pigment__midnight_1": 1229930,
    "engineering__recycling_bright_linen_bolt__midnight_1": 1229930,
    "engineering__recycling_codified_azeroot__midnight_1": 1229930,
    "engineering__recycling_imbued_bright_linen_bolt__midnight_1": 1229930,
    "engineering__recycling_powder_pigment__midnight_1": 1229930,
    "engineering__farstrider_hawkeye__midnight_1": 1261866,
}


def normalized(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", (value or "").lower())


def int_value(value: str | None) -> int:
    try:
        return int(value or 0)
    except ValueError:
        return 0


def float_value(value: str | None) -> float:
    try:
        return float(value or 0)
    except ValueError:
        return 0.0


def read_csv(path: Path):
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        yield from csv.DictReader(handle)


def load_catalog() -> tuple[dict[str, dict], dict[str, dict[str, list[dict]]]]:
    result = subprocess.run(
        ["lua", "tools/audit_recipe_catalog.lua", "--catalog-tsv"],
        check=True,
        capture_output=True,
        text=True,
    )
    rows = list(csv.DictReader(io.StringIO(result.stdout), delimiter="\t"))
    strategies = {
        row["strategy_id"]: row for row in rows if row["record_type"] == "strategy"
    }
    facts: dict[str, dict[str, list[dict]]] = defaultdict(
        lambda: {"reagent": [], "output": []}
    )
    for row in rows:
        if row["record_type"] in ("reagent", "output"):
            facts[row["strategy_id"]][row["record_type"]].append(row)
    return strategies, facts


def parse_item_ids(value: str) -> set[int]:
    return {int(part) for part in (value or "").split(",") if part}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--wago-dir", type=Path, default=Path("/tmp"))
    parser.add_argument(
        "--output-dir", type=Path, default=Path("output/spreadsheet")
    )
    args = parser.parse_args()

    paths = {
        "skill": args.wago_dir / "gam-skilllineability.csv",
        "names": args.wago_dir / "gam-spellname.csv",
        "reagents": args.wago_dir / "gam-spellreagents.csv",
        "effects": args.wago_dir / "gam-spelleffect.csv",
        "crafting": args.wago_dir / "gam-craftingdata.csv",
        "item_quality": args.wago_dir / "gam-craftingdataitemquality.csv",
        "enchant_quality": args.wago_dir / "gam-craftingdataenchantquality.csv",
    }
    missing = [str(path) for path in paths.values() if not path.exists()]
    if missing:
        raise SystemExit("Missing Wago inputs: " + ", ".join(missing))

    strategies, facts = load_catalog()

    spell_names = {
        int_value(row["ID"]): row["Name_lang"] for row in read_csv(paths["names"])
    }
    profession_spells: dict[int, dict[str, set[int]]] = defaultdict(
        lambda: defaultdict(set)
    )
    spell_professions: dict[int, set[int]] = defaultdict(set)
    for row in read_csv(paths["skill"]):
        skill_line = int_value(row["SkillLine"])
        spell_id = int_value(row["Spell"])
        name = spell_names.get(spell_id)
        if skill_line and spell_id and name:
            profession_spells[skill_line][normalized(name)].add(spell_id)
            spell_professions[spell_id].add(skill_line)

    resolved_ids: dict[str, int] = {}
    identity_status: dict[str, str] = {}
    identity_detail: dict[str, str] = {}
    for strategy_id, strategy in strategies.items():
        catalog_id = int_value(strategy["recipe_id"])
        profession_line = PROFESSION_SKILL_LINES[strategy["profession"]]
        if catalog_id:
            resolved_ids[strategy_id] = catalog_id
            expected_name = strategy["recipe_name"] or strategy["strategy_name"]
            actual_name = spell_names.get(catalog_id, "")
            in_profession = profession_line in spell_professions.get(catalog_id, set())
            if not actual_name:
                identity_status[strategy_id] = "catalog_id_missing_from_wago"
                identity_detail[strategy_id] = str(catalog_id)
            elif normalized(actual_name) != normalized(expected_name):
                identity_status[strategy_id] = "catalog_name_mismatch"
                identity_detail[strategy_id] = actual_name
            elif not in_profession:
                identity_status[strategy_id] = "catalog_profession_mismatch"
                identity_detail[strategy_id] = actual_name
            else:
                identity_status[strategy_id] = "confirmed"
                identity_detail[strategy_id] = actual_name
            continue

        if strategy_id in GENERIC_RECIPE_IDS:
            recipe_id = GENERIC_RECIPE_IDS[strategy_id]
            resolved_ids[strategy_id] = recipe_id
            identity_status[strategy_id] = "suggested_generic_or_alias"
            identity_detail[strategy_id] = spell_names.get(recipe_id, "")
            continue

        candidates = profession_spells[profession_line].get(
            normalized(strategy["strategy_name"]), set()
        )
        if len(candidates) == 1:
            recipe_id = next(iter(candidates))
            resolved_ids[strategy_id] = recipe_id
            identity_status[strategy_id] = "suggested_exact_name"
            identity_detail[strategy_id] = spell_names.get(recipe_id, "")
        elif not candidates:
            identity_status[strategy_id] = "unresolved"
            identity_detail[strategy_id] = "No profession spell name match"
        else:
            identity_status[strategy_id] = "ambiguous"
            identity_detail[strategy_id] = ",".join(map(str, sorted(candidates)))

    recipe_ids = set(resolved_ids.values())

    fixed_reagents: dict[int, list[tuple[int, int]]] = defaultdict(list)
    for row in read_csv(paths["reagents"]):
        spell_id = int_value(row["SpellID"])
        if spell_id not in recipe_ids:
            continue
        for index in range(8):
            item_id = int_value(row[f"Reagent_{index}"])
            quantity = int_value(row[f"ReagentCount_{index}"])
            if item_id and quantity > 0:
                fixed_reagents[spell_id].append((item_id, quantity))

    crafting_data_by_spell: dict[int, set[int]] = defaultdict(set)
    direct_outputs: dict[int, set[int]] = defaultdict(set)
    for row in read_csv(paths["effects"]):
        spell_id = int_value(row["SpellID"])
        if spell_id not in recipe_ids:
            continue
        effect = int_value(row["Effect"])
        item_id = int_value(row["EffectItemType"])
        misc_value = int_value(row["EffectMiscValue_0"])
        if effect == 288 and misc_value:
            crafting_data_by_spell[spell_id].add(misc_value)
        if effect in (24, 157) and item_id:
            direct_outputs[spell_id].add(item_id)

    used_crafting_data = {
        data_id for values in crafting_data_by_spell.values() for data_id in values
    }
    crafting_outputs: dict[int, set[int]] = defaultdict(set)
    for row in read_csv(paths["crafting"]):
        data_id = int_value(row["ID"])
        if data_id in used_crafting_data:
            item_id = int_value(row["CraftedItemID"])
            if item_id:
                crafting_outputs[data_id].add(item_id)
    for quality_path in (paths["item_quality"], paths["enchant_quality"]):
        for row in read_csv(quality_path):
            data_id = int_value(row["CraftingDataID"])
            if data_id in used_crafting_data:
                item_id = int_value(row["ItemID"])
                if item_id:
                    crafting_outputs[data_id].add(item_id)

    report_rows = []
    for strategy_id in sorted(strategies):
        strategy = strategies[strategy_id]
        recipe_id = resolved_ids.get(strategy_id, 0)
        catalog_reagents = []
        for fact in facts[strategy_id]["reagent"]:
            catalog_reagents.append(
                (parse_item_ids(fact["item_ids"]), float_value(fact["quantity"]))
            )

        reagent_findings = []
        for item_id, quantity in fixed_reagents.get(recipe_id, []):
            matches = [qty for item_ids, qty in catalog_reagents if item_id in item_ids]
            if not matches:
                reagent_findings.append(f"missing item {item_id} x{quantity}")
            elif all(abs(quantity - qty) > 0.000001 for qty in matches):
                reagent_findings.append(
                    f"item {item_id} Wago={quantity} catalog={','.join(map(str, matches))}"
                )
        if reagent_findings:
            fixed_reagent_status = "mismatch"
        elif fixed_reagents.get(recipe_id):
            fixed_reagent_status = "confirmed"
        else:
            fixed_reagent_status = "no_fixed_reagents_in_db2"

        wago_outputs = set(direct_outputs.get(recipe_id, set()))
        for data_id in crafting_data_by_spell.get(recipe_id, set()):
            wago_outputs.update(crafting_outputs.get(data_id, set()))
        catalog_outputs = set()
        for fact in facts[strategy_id]["output"]:
            catalog_outputs.update(parse_item_ids(fact["item_ids"]))
        if not wago_outputs:
            output_status = "requires_schematic_or_salvage_check"
            output_detail = ""
        elif not (wago_outputs & catalog_outputs):
            output_status = "mismatch"
            output_detail = (
                f"Wago={','.join(map(str, sorted(wago_outputs)))};"
                f"catalog={','.join(map(str, sorted(catalog_outputs)))}"
            )
        elif wago_outputs == catalog_outputs:
            output_status = "confirmed"
            output_detail = ""
        else:
            output_status = "partial_quality_set"
            output_detail = (
                f"Wago={','.join(map(str, sorted(wago_outputs)))};"
                f"catalog={','.join(map(str, sorted(catalog_outputs)))}"
            )

        source_url = (
            f"{WAGO_BASE}/SkillLineAbility/csv?product=wow&build={BUILD}"
        )
        report_rows.append(
            {
                "strategy_id": strategy_id,
                "profession": strategy["profession"],
                "strategy_name": strategy["strategy_name"],
                "profile": strategy["profile"],
                "catalog_recipe_id": strategy["recipe_id"],
                "resolved_recipe_id": recipe_id or "",
                "wago_recipe_name": spell_names.get(recipe_id, ""),
                "identity_status": identity_status[strategy_id],
                "identity_detail": identity_detail[strategy_id],
                "fixed_reagent_status": fixed_reagent_status,
                "fixed_reagent_findings": "; ".join(reagent_findings),
                "output_status": output_status,
                "output_findings": output_detail,
                "source_build": BUILD,
                "source_url": source_url,
            }
        )

    args.output_dir.mkdir(parents=True, exist_ok=True)
    csv_path = args.output_dir / "recipe_catalog_audit.csv"
    with csv_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(report_rows[0]))
        writer.writeheader()
        writer.writerows(report_rows)

    identity_counts = Counter(row["identity_status"] for row in report_rows)
    reagent_counts = Counter(row["fixed_reagent_status"] for row in report_rows)
    output_counts = Counter(row["output_status"] for row in report_rows)
    actionable = [
        row
        for row in report_rows
        if row["identity_status"] != "confirmed"
        or row["fixed_reagent_status"] == "mismatch"
        or row["output_status"] == "mismatch"
    ]

    md_path = args.output_dir / "recipe_catalog_audit_summary.md"
    with md_path.open("w", encoding="utf-8") as handle:
        handle.write("# Gold Advisor Midnight recipe catalog audit\n\n")
        handle.write(f"Pinned Wago build: `{BUILD}`  \n")
        handle.write(f"Retained strategies: `{len(report_rows)}`  \n")
        handle.write(f"Detailed CSV: `{csv_path.name}`\n\n")
        handle.write("## Identity results\n\n")
        for status, count in sorted(identity_counts.items()):
            handle.write(f"- `{status}`: {count}\n")
        handle.write("\n## Fixed reagent results\n\n")
        for status, count in sorted(reagent_counts.items()):
            handle.write(f"- `{status}`: {count}\n")
        handle.write("\n## Output-ID results\n\n")
        for status, count in sorted(output_counts.items()):
            handle.write(f"- `{status}`: {count}\n")
        handle.write("\n## Actionable rows\n\n")
        handle.write("| Profession | Strategy | Identity | Reagents | Outputs | Detail |\n")
        handle.write("|---|---|---|---|---|---|\n")
        for row in actionable:
            detail = row["fixed_reagent_findings"] or row["identity_detail"]
            handle.write(
                "| {profession} | {strategy_name} | {identity_status} → {resolved_recipe_id} "
                "| {fixed_reagent_status} | {output_status} | {detail} |\n".format(
                    **row, detail=detail.replace("|", "\\|")
                )
            )
        handle.write("\n## Sources and limits\n\n")
        handle.write(
            f"- Skill/name identity: {WAGO_BASE}/SkillLineAbility/csv?product=wow&build={BUILD}\n"
        )
        handle.write(
            f"- Fixed reagents: {WAGO_BASE}/SpellReagents/csv?product=wow&build={BUILD}\n"
        )
        handle.write(
            f"- Ranked outputs: {WAGO_BASE}/CraftingDataItemQuality/csv?product=wow&build={BUILD}\n"
        )
        handle.write(
            "- Modified reagent slots, salvage yield distributions, and base output quantities "
            "require `C_TradeSkillUI.GetRecipeSchematic` or a matching CraftSim recipe snapshot.\n"
        )

    print(f"Wrote {csv_path}")
    print(f"Wrote {md_path}")
    print(f"Identity: {dict(sorted(identity_counts.items()))}")
    print(f"Fixed reagents: {dict(sorted(reagent_counts.items()))}")
    print(f"Outputs: {dict(sorted(output_counts.items()))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
