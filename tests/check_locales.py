#!/usr/bin/env python3
"""Check that runtime localization references have a base English definition."""

from __future__ import annotations

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
ADDON_NAME = "GoldAdvisorMidnight"
ROOT = REPO_ROOT / ADDON_NAME
KEY_PATTERN = re.compile(
    r'(?:GAM\.)?L\[\s*["\']([^"\']+)["\']\s*\]'
    r'|\bL\(\s*["\']([^"\']+)["\']'
)
VALUE_PATTERN = re.compile(
    r'(?:GAM\.)?L\[\s*["\']([^"\']+)["\']\s*\]\s*=\s*(["\'])(.*?)\2'
)
FORMAT_PATTERN = re.compile(r'%(?:\.\d+)?[A-Za-z]')

def keys_in(path: Path) -> set[str]:
    return {
        match.group(1) or match.group(2)
        for match in KEY_PATTERN.finditer(path.read_text(encoding="utf-8-sig"))
    }


def values_in(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        match = VALUE_PATTERN.search(line)
        if match:
            values[match.group(1)] = match.group(3)
    return values


base_keys = keys_in(ROOT / "Locale.lua")
base_values = values_in(ROOT / "Locale.lua")
assert base_keys, "Locale.lua contains no localization keys"

runtime_keys: set[str] = set()
for path in ROOT.rglob("*.lua"):
    relative = path.relative_to(ROOT)
    if relative.parts[0] in {"Locale", "tests", "tools"} or relative == Path("Locale.lua"):
        continue
    runtime_keys.update(keys_in(path))

missing_base = sorted(runtime_keys - base_keys)
assert not missing_base, f"runtime localization keys missing from Locale.lua: {missing_base}"
required_translations = runtime_keys

locale_reports = []
for path in sorted((ROOT / "Locale").glob("*.lua")):
    locale_keys = keys_in(path)
    unknown = sorted(locale_keys - base_keys)
    assert not unknown, f"{path.name} defines unknown localization keys: {unknown}"
    missing_runtime = sorted(required_translations - locale_keys)
    assert not missing_runtime, (
        f"{path.name} is missing active runtime translations: {missing_runtime}"
    )
    locale_values = values_in(path)
    format_mismatches = sorted(
        key for key in required_translations
        if sorted(FORMAT_PATTERN.findall(locale_values.get(key, "")))
        != sorted(FORMAT_PATTERN.findall(base_values.get(key, "")))
    )
    assert not format_mismatches, (
        f"{path.name} changes required format placeholders: {format_mismatches}"
    )
    locale_reports.append(
        f"{path.stem}={len(required_translations)}/{len(required_translations)} translated"
    )

assert not (ROOT / "Locale" / "ShortUI.lua").exists(), (
    "English ShortUI overrides must not replace translated labels"
)
print(
    f"PASS: all {len(runtime_keys)} runtime keys have base definitions and translations; "
    + ", ".join(locale_reports)
)
