#!/usr/bin/env python3
"""Guard transient OK buttons against focus-loss redraw regressions."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TARGETS = (
    ROOT / "GoldAdvisorMidnightDev" / "UI" / "MainWindowDetail.lua",
    ROOT / "GoldAdvisorMidnightDev" / "UI" / "MainWindowLeftPanel.lua",
)

ATTACH_START = "local function AttachTransientCommitButton"
ATTACH_END = "\n    button:Hide()\nend"
MOUSE_DOWN = re.compile(
    r'button:SetScript\("OnMouseDown", function\(\)(.*?)\n\s*end\)', re.DOTALL
)

for path in TARGETS:
    source = path.read_text(encoding="utf-8-sig")
    start = source.index(ATTACH_START)
    end = source.index(ATTACH_END, start) + len(ATTACH_END)
    helper = source[start:end]
    mouse_down = MOUSE_DOWN.search(helper)
    assert mouse_down, f"{path.name}: transient OnMouseDown handler not found"
    assert mouse_down.group(1).count("CommitCurrentValue(true)") == 1, (
        f"{path.name}: OnMouseDown must submit the pending draft exactly once"
    )
    assert 'button:SetScript("OnClick"' not in helper, (
        f"{path.name}: mouse-up must not submit the value a second time"
    )
    assert "_gamPendingText" in helper and "_gamRestoringText" in helper, (
        f"{path.name}: focus-loss redraws must preserve the typed draft"
    )
    assert "C_Timer.After(0, RestoreCommittedText)" in helper, (
        f"{path.name}: focus-loss cancellation must wait for button mouse-down"
    )

print("PASS: transient OK buttons preserve and submit drafts before focus loss")
