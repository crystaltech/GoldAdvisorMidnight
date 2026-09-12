# Production integration review — 2.1.0

Status: offline-validated and committed on release/2.1.0-integration. No push or merge performed. Live validation remains outstanding.

## Git before

- Current branch: feature/main-frame-redesign.
- HEAD, main and origin/main: ac21fe983d142bd03a778a655309fc7ff9a53d87 (v2.0.10).
- Remote: https://github.com/crystaltech/GoldAdvisorMidnight.git.
- Production folder: 78 tracked files reported deleted; README modified; Dev source untracked.
- Other untracked work: GAM-main-frame-redesign-brief.md, GOLDMAKING-UX-PLAN.md, REVIEW.md, STRATEGY-AUDIT.md, GAM.zip, GoldAdvisorMidnightDev.zip, zips/, review-changed-files.txt, review-changes.patch, review-test-results.txt, strategy-catalog-audit.txt, strategy-catalog.tsv.
- Tests, tools, local workflow and source-audit inputs were ignored by the existing local ignore rules.
- Fetch confirmed origin/main remains at ac21fe9. Git printed unrelated long-path errors for internal refs/codex checkpoint refs; the fetch completed successfully. No history repair or checkpoint deletion was attempted.
- Normalized addon comparison: 62 changed files, 16 unchanged, two new files (CraftSimQueue.lua, RecipeAudit.lua). Full line-by-line comparison: before-production-vs-dev.patch.

## Recovery and branch structure

ac21fe9 — main, origin/main, v2.0.10, safety/main-before-2.1.0-integration
|-- c73d44e — feature/main-frame-redesign, safety/dev-astra10-before-production
|   Complete Dev source, tests, tools, and review/design notes.
`-- 2d9b16e — release/2.1.0-integration
    `-- safety/2.1.0-verification — production tests/tools and this review evidence.

The integration branch was created from fetched origin/main. The preserved Dev source was copied from its committed archive into production paths, then adapted. This is a new production commit, not a merge of the Dev-only folder or private tooling into main. Both original histories remain intact. No reset --hard, force push, branch deletion, or main history rewrite was used.

## Exact production changes

- Promote all completed Dev addon functionality, including Comfortable/appearance profiles, VI planning corrections, CraftSim queue, scan modifiers, Quick Buy and recipe-refresh fixes, and window geometry handling.
- Restore GoldAdvisorMidnight folder, TOC title, production Notes, GoldAdvisorMidnightDB and /gam plus /goldadvisor.
- Version 2.1.0 reflects the new UI and backward-compatible functionality; remove development suffix and TOC development marker.
- Replace IS_DEV_BUILD UI guards with explicit USE_COMFORTABLE_UI = true. Comfortable remains the production default, including for obsolete classic/soft theme options. Custom appearance profiles remain available.
- Remove Dev label rewriting, broker naming, frame-name suffixing and the offset that accommodated side-by-side AH buttons. Stable production names remain.
- Keep namespaced catalog data to avoid process-global collisions.
- Update production installation and scan instructions in README.
- Restore verification/tool paths to production. The publishing gate now runs, with no Dev-layout skip. Existing publishing boundary remains unchanged: README, LICENSE and addon files only.
- No duplicate Dev addon folder is in the integration tree or ZIP.

The precise conversion-only source patch is dev-to-production-conversion.patch. The entire proposed main change is proposed-main.patch. The latter is also available using:

    git diff main..release/2.1.0-integration
    git show 2d9b16e

Commit scope: 65 files, 3348 insertions and 446 deletions.

## Saved settings and geometry

Production remains on GoldAdvisorMidnightDB; it does not import or overwrite the isolated Dev database. No user must copy Dev settings to upgrade.

Existing schema 19 from 2.0.10 runs the additive schema 20 migration, creating only missing appearance-profile containers and a missing default selection. Existing profiles, selections, global/per-strategy quantities, favorites, prices, gear cache, custom options and geometry are preserved. Older supported migrations remain in place. Fresh users receive the existing 50-craft default; existing explicit batch settings remain.

Regression checks cover both legacy/fresh initialization and the actual prior production schema 19, repeated initialization, and preservation of a separate Dev database sentinel. Geometry tests exercise production identity, validate invalid dimensions/anchors, retain full width/height/position while Details is resized/moved/hidden, and restore from persisted full geometry after simulated reload. Source inspection confirms full geometry is restored before initial OnHide capture; compact capture is guarded and mainDetailSize is separate.

## Validation

- Complete tools/verify.py gate: PASS (see verification.txt).
- All 32 Lua suites: PASS under Lua 5.1, including production identity, migration and geometry regressions.
- All runtime Lua syntax: PASS.
- Retained recipe catalog, pinned Wago parity, commodity manifest and CraftSim specialization-node parity: PASS against existing local audit sources.
- TOC: 78 runtime Lua files covered.
- Locale check: 309 keys covered in all 10 translations.
- Transient edit-box binding static checks: PASS.
- Production package: 80 files, version 2.1.0; archive inspected and every entry byte-compared with source.
- Production GitHub publishing boundary: PASS, 80 addon files plus README and LICENSE. Not skipped.
- git diff --check: PASS.
- Remaining-reference search: no GoldAdvisorMidnightDev, gamdev, -dev, IS_DEV_BUILD or DevDB in production source/TOC/README. The migration test intentionally references GoldAdvisorMidnightDevDB to prove it is untouched; historical local review documents also retain Dev references.

Package: ../releases/GoldAdvisorMidnight-2.1.0.zip.

Tests/tools are intentionally outside the public integration commit, as required by the existing repository publishing boundary. Their migrated versions and this report are committed separately on safety/2.1.0-verification. The prior Dev versions remain in c73d44e. Existing local cached audit dependencies remain in place; audits are not claims of fresh live-data verification.

## Live checks still needed

- Installed CraftSim queue schema, exact ranks/quantities, ownership/profession/gear/concentration/cooldown compatibility.
- Quick Buy: successful purchase, price guard, failure, close/reopen while pending.
- Scan click/Ctrl/Alt/Shift scope, combined modifiers and stop behavior at the AH.
- Refresh Recipe: correct stats, no protected-action error.
- Sterling Alloy: VI enabled/disabled, ingot producer ranks and consistent price basis when comparing CraftSim.
- Production saved settings through an actual reload; Comfortable at different UI scales; Details/full resize and position behavior in the WoW renderer.

No live validation was performed here. Offline-ready for review; no claim of in-game release signoff.

## Handoff

The only commit proposed for main is 2d9b16e. Main is unchanged. Original untracked archives/reports remain untouched and excluded from the release commit. Review this branch and perform live checks before authorizing a push/merge. Safety refs are local until explicitly pushed; no remote backup was created.
