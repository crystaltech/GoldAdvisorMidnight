# Contributing / Dev Workflow

## Branch Strategy

```
feature / fix work
        │
        ▼
  [discord branch]  ──  Discord builds (new features, members-first)
        │
        │  merge when ready for public release
        ▼
  [main branch]  ──────  CurseForge / stable builds
        │
        └── Bug-fix patches branch from main, merged back to both
```

- **`discord`** — default working branch for new features; Discord members get these builds first
- **`main`** — CurseForge-stable; only receives merges from `discord` when features are ready for public release
- **`feat/<name>` / `fix/<name>`** — short-lived work branches; merge into `discord`

## Start-of-session checklist

```bash
# For new features (Discord-first):
git checkout discord
git pull --ff-only
git checkout -b feat/short-task-name

# For bug fixes (patch both branches):
git checkout main
git pull --ff-only
git checkout -b fix/short-task-name
```

## During work

- Commit in small logical chunks
- Keep release artifacts (`releases/*.zip`) out of commits — the `releases/` directory is gitignored
- Bump `ADDON_VERSION` in `Constants.lua` **and** `## Version:` in the TOC together when incrementing the version
- Never commit `.env` — it contains private API credentials

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
release: v1.4.3 (discord)
release: v1.4.3 (curseforge)
```

## Release Scripts

| Script | Purpose | Target | Git action |
|--------|---------|--------|------------|
| `Release_Patreon.command` | Plain handoff zip for direct distribution | Direct handoff | None — zip only |
| `Release_Discord.command` | Plain zip + GitHub **pre-release** | Discord members | Commits, tags `vX.X.X-discord`, pushes current branch |
| `Release_CurseForge.command` | Plain zip + GitHub **stable** release + CF upload | CurseForge / public | Commits, tags `vX.X.X`, pushes `main`, uploads to CF |
| `Package_Addon.command` | Plain zip only, no git | Local testing | None |

### Before any release

1. Bump version in `Constants.lua` (`ADDON_VERSION`) and `GoldAdvisorMidnight.toc` (`## Version:`)
2. Add a `## [X.Y.Z]` entry to the top of `CHANGELOG.md`
3. Run the appropriate release script

### CurseForge prerequisites (one-time setup)

1. Create project at https://www.curseforge.com/project/create
2. Fill in `.env` with `CF_API_TOKEN`, `CF_PROJECT_ID`, `CF_GAME_VERSION_ID`
3. Update `## X-Curse-Project-ID:` in the TOC file

## Version conventions

| Pattern | Meaning | Release target |
|---------|---------|----------------|
| `v1.4.x` | Bug fix / patch | Discord + CurseForge simultaneously |
| `v1.X.0` | New feature release | Discord first → CurseForge after Discord window |
| `vX.X.X-discord` | Discord early-access tag | Discord only (GitHub pre-release) |
| `vX.X.X` | Stable tag | CurseForge + main GitHub release |

## Merging Discord → Main (for CurseForge release)

```bash
git checkout main
git pull --ff-only
git merge discord --no-ff -m "chore: merge discord v1.X.0 → main for CurseForge release"
git push origin main
# then run Release_CurseForge.command
```

## Patch workflow (bug fix that goes to both branches)

```bash
git checkout main && git pull --ff-only
git checkout -b fix/short-name
# make fix, commit
git checkout main && git merge fix/short-name
git checkout discord && git merge fix/short-name
git branch -d fix/short-name
```

## Data regeneration

When importing a new spreadsheet version:

```bash
python3 tools/generate_workbook_data.py
```

This overwrites `source/GoldAdvisorMidnight/Data/WorkbookGenerated.lua` and `StratsGenerated.lua`. Review the diff before committing.

## Cross-computer rule

- Always push before switching machines
- Always `git pull --ff-only` before starting work on another machine
