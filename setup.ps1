# Claude Dir Switch - Installer
# Adds a 'claude' function to your PowerShell profile that:
#   1. Syncs Claude Code project data between old and new directories
#   2. Sets the working directory to the configured target
#   3. After exit, syncs new data back (keeps both locations in sync)
#
# Usage: .\setup.ps1 [-TargetDir <path>] [-OldDir <path>]
#   -TargetDir: New default working directory (default: E:\claude\202605)
#   -OldDir:    Previous working directory (default: current user profile)

param(
    [string]$TargetDir = "E:\claude\202605",
    [string]$OldDir = $env:USERPROFILE
)

$ErrorActionPreference = "Stop"

# Sanitize paths for Claude Code project directory naming
function Get-ProjectDirName {
    param([string]$Path)
    ($Path -replace '^([A-Za-z]):', '$1-') -replace '[\\/]', '-'
}

$oldProject = "$env:USERPROFILE\.claude\projects\$(Get-ProjectDirName $OldDir)"
$newProject = "$env:USERPROFILE\.claude\projects\$(Get-ProjectDirName $TargetDir)"

$functionCode = @"
function claude {
    `$oldProject = "$oldProject"
    `$newProject = "$newProject"
    `$targetDir = "$TargetDir"

    # Ensure target directory exists
    if (-not (Test-Path `$targetDir)) {
        New-Item -ItemType Directory -Path `$targetDir -Force | Out-Null
    }

    # Sync old project data -> new project data before launch
    if (Test-Path `$oldProject) {
        robocopy `$oldProject `$newProject /E /R:2 /W:1 /NDL /NFL /NJH /NJS
    }

    Set-Location `$targetDir
    & claude.exe @args

    # Sync new project data -> old project data after exit
    if (Test-Path `$newProject) {
        robocopy `$newProject `$oldProject /E /R:2 /W:1 /NDL /NFL /NJH /NJS
    }
}
"@

# Ensure profile directory exists
$profileDir = Split-Path $PROFILE -Parent
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

# Check if function already exists in profile
if (Test-Path $PROFILE) {
    $existing = Get-Content $PROFILE -Raw
    if ($existing -match 'function claude\s*{') {
        Write-Output "Existing 'claude' function found in profile. Overwriting..."
        $existing = $existing -replace '(?s)function claude\s*\{.*?^\}', ''
        $existing = $existing.TrimEnd() + "`n`n$functionCode`n"
        Set-Content -Path $PROFILE -Value $existing -Encoding UTF8
    } else {
        Add-Content -Path $PROFILE -Value "`n$functionCode`n" -Encoding UTF8
    }
} else {
    Set-Content -Path $PROFILE -Value "$functionCode`n" -Encoding UTF8
}

Write-Output "Installed to $PROFILE"
Write-Output "Target: $TargetDir"
Write-Output "Run '. `$PROFILE' to reload, then 'claude' to start."
