# Contributing / Dev Workflow

## Branch strategy

- `main` — stable branch; only release commits land here directly
- Feature / fix branches for active work:
  - `feat/<name>`
  - `fix/<name>`
  - `chore/<name>`

## Start-of-session checklist

```bash
git checkout main
git pull --ff-only
git checkout -b feat/short-task-name
```

## During work

- Commit in small logical chunks
- Keep release artifacts (`releases/*.zip`) out of commits — the `releases/` directory is gitignored
- Bump `ADDON_VERSION` in `Constants.lua` **and** `## Version:` in the TOC together when incrementing the version

## End-of-session checklist

```bash
git status
git add source/ CHANGELOG.md   # be specific — avoid git add -A
git commit -m "type(scope): short description"
git push -u origin <branch>
```

## Commit message style

```
feat(ui): add profession sub-filter dropdown to left panel
fix(pricing): include Thalassian Songwater in ink strategy cost
fix(scan): remove RebuildList from mid-scan progress throttle
chore(data): regenerate StratsGenerated from 3-19-26 spreadsheet
release: v1.4.3 (protected)
```

## Releasing

1. Bump version in `Constants.lua` (`ADDON_VERSION`) and `GoldAdvisorMidnight.toc` (`## Version:`)
2. Add a `## [X.Y.Z]` entry to the top of `CHANGELOG.md`
3. Run the release script:
   ```bash
   bash Release_Protected.command   # protected build (encoded data)
   bash Release_Addon.command       # plain build
   ```
4. The script will show a diff summary and prompt for confirmation before committing

## Data regeneration

When importing a new spreadsheet version:

```bash
python3 tools/generate_workbook_data.py
```

This overwrites `source/GoldAdvisorMidnight/Data/WorkbookGenerated.lua` and `StratsGenerated.lua`. Review the diff before committing.

## Cross-computer rule

- Always push before switching machines
- Always `git pull --ff-only` before starting work on another machine
