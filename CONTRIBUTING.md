# Contributing / Daily Workflow

## Branch strategy
- `main`: stable branch.
- Feature branches for active work:
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
- Commit in small logical chunks.
- Keep release artifacts (`*.zip`) out of commits.
- Keep memory snapshots in dedicated commits when practical.

## End-of-session checklist
```bash
git status
git add -A
git commit -m "type(scope): short description"
git push -u origin <branch>
```

## Suggested commit message style
- `feat(ui): align main window columns`
- `fix(stratdetail): reserve scrollbar gutter for row buttons`
- `chore(memory): update win11 snapshot`
- `chore(repo): add github bootstrap files`

## Cross-computer rule
- Always push before switching computers.
- On the other computer, always `git pull --ff-only` before starting work.
