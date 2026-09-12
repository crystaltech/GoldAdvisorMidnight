#!/usr/bin/env python3
"""Run all offline regressions using isolated Lua 5.1 runtimes (pip install lupa)."""
from pathlib import Path
import os
import subprocess
import sys

try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    raise SystemExit("Install the test dependency first: python -m pip install lupa")

root = Path(__file__).resolve().parents[1]
addon = root / "GoldAdvisorMidnight"
results = []
os.chdir(addon)
compiler = LuaRuntime().eval("function(s) local f,e=loadstring(s); return e end")
for path in sorted(addon.rglob("*.lua")):
    error = compiler(path.read_text(encoding="utf-8-sig"))
    if error:
        results.append((str(path.relative_to(root)), "FAIL: " + str(error)))
for path in sorted((root / "tests").glob("*.lua")):
    if path.name == "TestLoader.lua":
        continue
    try:
        LuaRuntime().execute(path.read_text(encoding="utf-8-sig"))
        results.append((path.name, "PASS"))
    except Exception as error:
        results.append((path.name, "FAIL: " + str(error)))
for name in ("check_toc.py", "check_locales.py", "check_transient_commit.py"):
    completed = subprocess.run([sys.executable, str(root / "tests" / name)], cwd=root,
                               capture_output=True, text=True)
    results.append((name, "PASS" if completed.returncode == 0 else "FAIL: " + completed.stdout + completed.stderr))
report = "\n".join(name + ": " + outcome for name, outcome in results) + "\n"
(root / "review-test-results.txt").write_text(report, encoding="utf-8")
failures = [(name, outcome) for name, outcome in results if outcome != "PASS"]
for name, outcome in failures:
    print(name + ": " + outcome)
print(f"{len(results) - len(failures)}/{len(results)} checks passed; runtime Lua syntax checked.")
raise SystemExit(1 if failures else 0)
