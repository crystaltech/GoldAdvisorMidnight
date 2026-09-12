@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem Usage: tools\release.bat [MAJOR.MINOR.PATCH] [--dry-run]

cd /d "%~dp0.." || exit /b 1

where git >nul 2>&1 || (
    echo ERROR: git is not installed or is not on PATH.
    exit /b 1
)
where gh >nul 2>&1 || (
    echo ERROR: GitHub CLI ^(gh^) is not installed or is not on PATH.
    exit /b 1
)
where python >nul 2>&1 || (
    echo ERROR: Python is not installed or is not on PATH.
    exit /b 1
)

for /f "tokens=3" %%V in ('findstr /B /C:"## Version:" "GoldAdvisorMidnight\GoldAdvisorMidnight.toc"') do set "RELEASE_VERSION=%%V"
if not defined RELEASE_VERSION (
    echo ERROR: Could not read the addon version from GoldAdvisorMidnight.toc.
    exit /b 1
)
if not "%~1"=="" if /I not "%~1"=="!RELEASE_VERSION!" (
    echo ERROR: Requested version %~1 does not match TOC version !RELEASE_VERSION!.
    exit /b 1
)
if /I "%~2"=="--dry-run" set "DRY_RUN=1"

powershell -NoProfile -Command "if ($env:RELEASE_VERSION -notmatch '^\d+\.\d+\.\d+$') { exit 1 }"
if errorlevel 1 (
    echo ERROR: Version !RELEASE_VERSION! must use MAJOR.MINOR.PATCH.
    exit /b 1
)

set "RELEASE_TAG=v!RELEASE_VERSION!"
set "RELEASE_DIR=output\releases"
set "RELEASE_ZIP=!RELEASE_DIR!\GoldAdvisorMidnight-!RELEASE_VERSION!.zip"
set "RELEASE_NOTES=!RELEASE_DIR!\GoldAdvisorMidnight-!RELEASE_VERSION!-notes.md"

for /f "delims=" %%F in ('git ls-files --others --exclude-standard -- GoldAdvisorMidnight') do (
    echo ERROR: Untracked addon file would not be committed: %%F
    echo Add an intentional runtime file to Git first, or move a stray file out of the addon folder.
    exit /b 1
)

for /f "delims=" %%B in ('git branch --show-current') do set "CURRENT_BRANCH=%%B"
if /I not "!CURRENT_BRANCH!"=="main" (
    echo ERROR: Releases must be created from main, not !CURRENT_BRANCH!.
    exit /b 1
)

for /f "delims=" %%R in ('git remote get-url origin') do set "ORIGIN_URL=%%R"
if not defined ORIGIN_URL (
    echo ERROR: Git remote origin is not configured.
    exit /b 1
)

echo.
echo Verifying Gold Advisor Midnight !RELEASE_VERSION!...
python tools\extract_release_notes.py "!RELEASE_VERSION!" "!RELEASE_NOTES!" || exit /b 1
python tools\verify.py || exit /b 1

pushd GoldAdvisorMidnight || exit /b 1
python ..\tools\package_release.py
set "PACKAGE_RESULT=!ERRORLEVEL!"
popd
if not "!PACKAGE_RESULT!"=="0" exit /b !PACKAGE_RESULT!
if not exist "!RELEASE_ZIP!" (
    echo ERROR: Release zip was not created: !RELEASE_ZIP!
    exit /b 1
)

if defined DRY_RUN (
    echo.
    echo PASS: Dry run built and verified Gold Advisor Midnight !RELEASE_VERSION!.
    echo No commit, tag, push, or GitHub Release was created.
    exit /b 0
)

gh auth status || exit /b 1
git fetch origin main || exit /b 1
for /f "tokens=1,2" %%A in ('git rev-list --left-right --count HEAD...origin/main') do (
    set "AHEAD_COUNT=%%A"
    set "BEHIND_COUNT=%%B"
)
if not "!BEHIND_COUNT!"=="0" (
    echo ERROR: Local main is behind origin/main by !BEHIND_COUNT! commit^(s^). Update it before releasing.
    exit /b 1
)

gh release view "!RELEASE_TAG!" >nul 2>&1
if not errorlevel 1 (
    echo ERROR: GitHub Release !RELEASE_TAG! already exists.
    exit /b 1
)

echo.
echo Destination: !ORIGIN_URL!
echo Branch:      main
echo Tag:         !RELEASE_TAG!
echo Asset:       !RELEASE_ZIP!
echo Notes:       CHANGELOG.md section [!RELEASE_VERSION!]
echo.
choice /C YN /N /M "Commit, tag, push, and publish this release? [Y/N] "
if errorlevel 2 (
    echo Release cancelled. No commit, tag, push, or GitHub Release was created.
    exit /b 0
)

git add -u -- README.md LICENSE GoldAdvisorMidnight || exit /b 1
git diff --quiet || (
    echo ERROR: Tracked changes remain unstaged.
    exit /b 1
)

git diff --cached --quiet
if errorlevel 1 (
    git commit -m "Release Gold Advisor Midnight !RELEASE_VERSION!" || exit /b 1
) else (
    echo No public file changes to commit; releasing the current HEAD.
)

for /f "delims=" %%H in ('git rev-parse HEAD') do set "HEAD_COMMIT=%%H"
git show-ref --verify --quiet "refs/tags/!RELEASE_TAG!"
if errorlevel 1 (
    git tag -a "!RELEASE_TAG!" -m "Gold Advisor Midnight !RELEASE_VERSION!" || exit /b 1
) else (
    for /f "delims=" %%H in ('git rev-list -n 1 "!RELEASE_TAG!"') do set "TAG_COMMIT=%%H"
    if /I not "!TAG_COMMIT!"=="!HEAD_COMMIT!" (
        echo ERROR: Existing tag !RELEASE_TAG! points to !TAG_COMMIT!, not !HEAD_COMMIT!.
        exit /b 1
    )
    echo Reusing local tag !RELEASE_TAG! at !HEAD_COMMIT!.
)

git push --atomic origin HEAD:main "!RELEASE_TAG!" || exit /b 1
gh release create "!RELEASE_TAG!" "!RELEASE_ZIP!" --verify-tag --latest --title "Gold Advisor Midnight !RELEASE_VERSION!" --notes-file "!RELEASE_NOTES!" || exit /b 1

echo.
echo PASS: Published Gold Advisor Midnight !RELEASE_VERSION! to !ORIGIN_URL!.
exit /b 0
