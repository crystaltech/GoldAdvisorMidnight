# WoW Projects Structure

This workspace is centered on `GoldAdvisorAddon/` with active addon code and reference materials grouped by purpose.

## Key Folders

- `GoldAdvisorAddon/`
  - Active addon project repository.
  - **Protected path:** `GoldAdvisorAddon/source/GoldAdvisorMidnight/` (do not modify during cleanup).
- `GoldAdvisorAddon/data/`
  - Structured data files used for analysis or addon workflows.
- `GoldAdvisorAddon/references/`
  - Long-term reference assets and imports.
- `GoldAdvisorAddon/references/WoW_Game_Notes/`
  - WoW gameplay and profession notes.
- `GoldAdvisorAddon/references/Spreadsheet/`
  - Spreadsheet references and converted data.
- `GoldAdvisorAddon/references/WIP:broken addons/legacy-addon-2026-03-06/`
  - Archived legacy addon workspace kept for historical reference.

## Cleanup Conventions

- Remove temporary lock files like `~$*.xlsx` when present.
- Remove `.DS_Store` files outside protected code paths (`GoldAdvisorAddon/source/GoldAdvisorMidnight/`).
- Keep release artifacts in `GoldAdvisorAddon/releases/` canonical and consistently named.
