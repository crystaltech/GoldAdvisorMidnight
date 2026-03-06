param(
    [string]$SourceDir = ""
)

$ErrorActionPreference = "Stop"

# Usage:
#   pwsh -ExecutionPolicy Bypass -File .\scripts\sync_memory_win.ps1
#   pwsh -ExecutionPolicy Bypass -File .\scripts\sync_memory_win.ps1 -SourceDir "C:\path\to\memory"
#
# Files are copied into:
#   GoldAdvisorMidnight\memory\snapshots\win11

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir "..")

if ([string]::IsNullOrWhiteSpace($SourceDir)) {
    $SourceDir = Join-Path $RepoRoot "GoldAdvisorMidnight\memory"
}

$DestDir = Join-Path $RepoRoot "GoldAdvisorMidnight\memory\snapshots\win11"

if (-not (Test-Path -LiteralPath $SourceDir)) {
    throw "Source directory does not exist: $SourceDir"
}

New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

$includeExt = @(".md", ".txt", ".lua", ".json")
$sourceRootResolved = (Resolve-Path $SourceDir).Path

Get-ChildItem -Path $sourceRootResolved -Recurse -File | ForEach-Object {
    $full = $_.FullName
    $ext = $_.Extension.ToLowerInvariant()
    if ($includeExt -notcontains $ext) {
        return
    }
    if ($full -match "[\\/]snapshots[\\/]") {
        return
    }

    $relative = $full.Substring($sourceRootResolved.Length).TrimStart('\','/')
    $target = Join-Path $DestDir $relative
    $targetDir = Split-Path -Parent $target
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    Copy-Item -LiteralPath $full -Destination $target -Force
}

Write-Host "Memory sync complete (win11):"
Write-Host "  Source: $SourceDir"
Write-Host "  Dest:   $DestDir"
