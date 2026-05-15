# Claude Dir Switch

Switch Claude Code's default working directory without losing settings, conversation history, or memory.

## Problem

Claude Code stores project-specific data (conversation transcripts, memory, tasks, file history) under `~/.claude/projects/<sanitized-cwd>/`. When you change the working directory, Claude Code treats it as a different project - your old conversations and memory appear to be gone.

## Solution

This tool wraps `claude.exe` in a PowerShell function that:

1. **Syncs** project data from your old directory to the new one before launch
2. **Changes** the working directory to your preferred location
3. **Syncs back** new data after Claude exits (keeps both locations in sync)

Both directories always have the complete, up-to-date project data.

## Install

```powershell
# Quick install (defaults: TargetDir=E:\claude\202605, OldDir=$env:USERPROFILE)
.\setup.ps1

# Custom paths
.\setup.ps1 -TargetDir "D:\my-projects\claude-work" -OldDir "C:\old-project-dir"
```

Then reload your profile:

```powershell
. $PROFILE
```

## Usage

Just type `claude` as usual:

```powershell
claude           # opens in target dir with synced data
claude --print "hello"  # additional args forwarded to claude.exe
```

## How It Works

```
claude (function)
  ├─ robocopy: old-project-data/ → new-project-data/
  ├─ cd E:\claude\202605
  ├─ claude.exe @args  (runs interactively)
  ├─ robocopy: new-project-data/ → old-project-data/
  └─ return
```

The sync uses `robocopy /E` which only copies changed files, so it's fast after the first run.

## Files

- `setup.ps1` - One-click installer
- Your PowerShell profile gets a `claude` function (the actual logic)

## Requirements

- Windows with PowerShell 5.1+
- [Claude Code](https://claude.ai/code) installed and in PATH
- `robocopy` (built into Windows)
