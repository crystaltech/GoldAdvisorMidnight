# Gold Advisor Midnight - GitHub Setup (macOS + Windows 11)

## 1. Create the GitHub repository
1. In GitHub, create a new **private** repository (empty: no README/gitignore/license).
2. Copy the SSH URL (example: `git@github.com:<user>/<repo>.git`).

## 2. Local setup on macOS (this machine)
1. Set git identity:
```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```
2. Create SSH key (if needed):
```bash
ssh-keygen -t ed25519 -C "you@example.com"
```
3. Add key to GitHub:
```bash
cat ~/.ssh/id_ed25519.pub
```
Copy output into GitHub -> Settings -> SSH and GPG keys.
4. Verify auth:
```bash
ssh -T git@github.com
```
5. Initialize and push repo:
```bash
git init
git branch -M main
git add .
git commit -m "chore: initialize repository"
git remote add origin git@github.com:<user>/<repo>.git
git push -u origin main
```

## 3. Setup on Windows 11 (home PC)
1. Install Git for Windows.
2. Set git identity:
```powershell
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```
3. Generate SSH key:
```powershell
ssh-keygen -t ed25519 -C "you@example.com"
```
4. Copy key and add to GitHub:
```powershell
Get-Content $HOME\.ssh\id_ed25519.pub
```
5. Verify auth:
```powershell
ssh -T git@github.com
```
6. Clone repository:
```powershell
git clone git@github.com:<user>/<repo>.git
```

## 4. IDE setup (VS Code / VSCodium / Antigravity)
- Open the cloned repository root folder.
- Ensure built-in Git integration is enabled.
- Use SSH remote URL for all push/pull operations.
- Antigravity: use the same repo folder and system Git (SSH), keep terminal workflow as fallback.

## 5. Memory snapshot sync
- Mac:
```bash
chmod +x scripts/sync_memory_mac.sh
./scripts/sync_memory_mac.sh
```
- Windows 11:
```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\sync_memory_win.ps1
```

Snapshots are written to:
- `GoldAdvisorMidnight/memory/snapshots/mac/`
- `GoldAdvisorMidnight/memory/snapshots/win11/`

Commit snapshot updates when needed:
```bash
git add GoldAdvisorMidnight/memory/snapshots
git commit -m "chore(memory): update snapshots"
git push
```
