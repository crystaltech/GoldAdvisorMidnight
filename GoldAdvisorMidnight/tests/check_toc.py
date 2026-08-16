#!/usr/bin/env python3
"""Verify that the TOC references every runtime Lua file exactly once."""

from pathlib import Path


root = Path(__file__).resolve().parents[1]
toc = root / "GoldAdvisorMidnight.toc"

listed = []
for raw_line in toc.read_text(encoding="utf-8").splitlines():
    line = raw_line.strip()
    if line.lower().endswith(".lua"):
        listed.append(line.replace("\\", "/"))

duplicates = sorted(path for path in set(listed) if listed.count(path) > 1)
missing = sorted(path for path in listed if not (root / path).is_file())

runtime = set()
for pattern in ("*.lua", "Data/**/*.lua", "Locale/**/*.lua", "UI/**/*.lua"):
    for path in root.glob(pattern):
        runtime.add(path.relative_to(root).as_posix())

# Repository-only audit modules are loaded explicitly by their test harnesses,
# never by the live addon.
developer_only = {"RecipeAudit.lua"}
unlisted = sorted(runtime - set(listed) - developer_only)

assert not duplicates, f"duplicate TOC entries: {duplicates}"
assert not missing, f"missing TOC files: {missing}"
assert not unlisted, f"runtime Lua files absent from TOC: {unlisted}"

# Shared UIDropDownMenu list buttons belong to Blizzard.  Mutating them from an
# addon can taint unrelated protected UI callbacks, including the Game Menu.
shared_dropdown_writes = []
for path in sorted(root.rglob("*.lua")):
    if "tests" in path.parts:
        continue
    source = path.read_text(encoding="utf-8")
    if "DropDownList1Button" in source or "DropDownList2Button" in source:
        shared_dropdown_writes.append(path.relative_to(root).as_posix())

assert not shared_dropdown_writes, (
    f"runtime code accesses Blizzard shared dropdown buttons: {shared_dropdown_writes}"
)
print(f"PASS: TOC covers {len(listed)} runtime Lua files")
