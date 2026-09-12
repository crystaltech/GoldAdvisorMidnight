#!/usr/bin/env python3
"""Run the complete behavior-preserving refactor verification gate."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
ADDON_NAME = "GoldAdvisorMidnightDev" if (REPO_ROOT / "GoldAdvisorMidnightDev").is_dir() else "GoldAdvisorMidnight"
ADDON_ROOT = REPO_ROOT / ADDON_NAME
TEST_ROOT = REPO_ROOT / "tests"
TOOL_ROOT = REPO_ROOT / "tools"

LUA_TESTS = (
    "run.lua",
    "pricing_formula.lua",
    "pricing_contract.lua",
    "pricing_facade.lua",
    "strategy_list.lua",
    "strategy_detail.lua",
    "pricing_derivation.lua",
    "core_migrations.lua",
    "state.lua",
    "vendor_prices.lua",
    "crafting_stats.lua",
    "profession_node_display.lua",
    "cooldown_tracker.lua",
    "craftsim_bridge.lua",
    "ah_scan.lua",
    "quick_buy.lua",
    "recipe_audit.lua",
    "pricing_inventory.lua",
    "reagent_mix_optimizer.lua",
    "vi_breakdown_plan.lua",
    "dev_identity.lua",
    "settings_startup.lua",
    "theme_profiles.lua",
    "craftsim_queue.lua",
    "crushing_layout.lua",
    "detail_layout.lua",
    "quick_buy_window.lua",
    "rocky_yield.lua",
    "scan_shortcuts.lua",
    "secondary_theme.lua",
    "settings_scale.lua",
    "window_geometry.lua",
)


def executable(*names: str) -> str:
    for name in names:
        resolved = shutil.which(name)
        if resolved:
            return resolved
    raise SystemExit(f"Missing required executable; tried: {', '.join(names)}")


def run(label: str, command: list[str], cwd: Path = ADDON_ROOT) -> None:
    print(f"\n== {label} ==", flush=True)
    subprocess.run(command, cwd=cwd, check=True)


def main() -> int:
    lua = executable("lua5.4", "lua")
    luac = executable("luac5.4", "luac")

    syntax_files = sorted(ADDON_ROOT.rglob("*.lua")) + [TOOL_ROOT / "RecipeAudit.lua"]
    for path in syntax_files:
        run(f"syntax {path.relative_to(REPO_ROOT)}", [luac, "-p", str(path)])

    for test_name in LUA_TESTS:
        run(f"test {test_name}", [lua, str(TEST_ROOT / test_name)])

    run("retained recipe catalog audit", [lua, str(TOOL_ROOT / "audit_recipe_catalog.lua")])
    run(
        "CraftSim specialization pricing-node parity",
        [lua, str(TOOL_ROOT / "audit_specialization_catalog.lua")],
        cwd=REPO_ROOT,
    )
    run(
        "commodity manifest source parity",
        [
            sys.executable,
            str(TOOL_ROOT / "generate_commodity_manifest.py"),
            "--wago-build",
            "12.1.0.69587",
            "--expected-count",
            "283",
            "--check",
        ],
    )
    run(
        "pinned Wago recipe parity",
        [
            sys.executable,
            str(TOOL_ROOT / "audit_wago_recipe_data.py"),
            "--wago-dir",
            "../tmp/spreadsheets/recipe-audit-12.1.0.69587",
            "--check",
        ],
    )
    run("TOC runtime boundary", [sys.executable, str(TEST_ROOT / "check_toc.py")])
    run("locale coverage", [sys.executable, str(TEST_ROOT / "check_locales.py")])
    run(
        "transient OK button event binding",
        [sys.executable, str(TEST_ROOT / "check_transient_commit.py")],
    )
    run(
        "release package boundary",
        [sys.executable, str(TOOL_ROOT / "package_release.py"), "--check"],
    )
    if ADDON_NAME.endswith("Dev"):
        print("\n== GitHub publish boundary ==", flush=True)
        print("SKIP: development addon trees are not production release layouts", flush=True)
    else:
        run(
            "GitHub publish boundary",
            [sys.executable, str(TOOL_ROOT / "check_publish_boundary.py")],
        )

    print("\nPASS: complete Gold Advisor Midnight verification gate", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
