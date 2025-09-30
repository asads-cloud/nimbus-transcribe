<#
.SYNOPSIS
  Watch a local "ingest" folder and trigger the uploader for any new/changed files.

.DESCRIPTION
  This script uses a FileSystemWatcher (event-driven) plus a light polling fallback to
  reliably detect files dropped into the Nimbus Ingest folder and then calls the
  companion uploader script (2-upload_audio.ps1) for each file. It also tracks the
  last processed write-timestamp per file to avoid duplicate uploads when multiple
  change events fire.

.USAGE
  # From the repo root (or wherever this script lives):
  .\scripts\1-watch-ingest.ps1

  - Drop audio files into:  ~/Desktop/Nimbus Transcriber/Nimbus Ingest
  - The script prints detections and calls 2-upload_audio.ps1 -FileName <name>

.NOTES
  - Requires PowerShell with access to .NET FileSystemWatcher.
  - The ingest folder is created on first run if missing.
  - Event storms and partial writes are handled by:
      * Wait-FileReady (size-stability + share-open test)
      * A processed-ticks cache to de-duplicate
      * A periodic scan (polling) to catch missed events

.ENV
  Uses $env:USERPROFILE to build the default Desktop path.
#>

# ─────────────────────────────────────────────
# Resolve paths
# ─────────────────────────────────────────────

# Path to the uploader helper script (invoked for each detected file)
$UploaderPath = Join-Path $PSScriptRoot "2-upload_audio.ps1"

# Canonical ingest directory on the user's Desktop
$IngestDir    = Join-Path (Join-Path $env:USERPROFILE "Desktop") "Nimbus Transcriber\Nimbus Ingest"


# ─────────────────────────────────────────────
# Validate prerequisites (script + folder)
# ─────────────────────────────────────────────

# Ensure the uploader exists; fail fast if not found
if (-not (Test-Path $UploaderPath)) { throw "Uploader not found: $UploaderPath" }

# Ensure the ingest directory exists; create if missing
if (-not (Test-Path $IngestDir))    { New-Item -ItemType Directory -Path $IngestDir -Force | Out-Null }


# ─────────────────────────────────────────────
# Clean up any old event subscriptions / jobs
# ─────────────────────────────────────────────

# Avoid duplicate handlers from previous runs
Unregister-Event -SourceIdentifier IngestCreated -ErrorAction SilentlyContinue
Unregister-Event -SourceIdentifier IngestRenamed -ErrorAction SilentlyContinue
Unregister-Event -SourceIdentifier IngestChanged -ErrorAction SilentlyContinue

# Remove orphaned background jobs tied to prior watchers
Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue


# ─────────────────────────────────────────────
# Script state (shared with event actions)
# ─────────────────────────────────────────────

# Tracks: full path => last processed LastWriteTimeUtc.Ticks
# Prevents reprocessing when multiple change events occur for the same write
$script:processed = @{}  # path -> last processed LastWriteTimeUtc ticks


# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

function Wait-FileReady {
    <#
      Purpose:
        Blocks until a file appears "stable" (size stops changing) and can be
        opened for read-share. This protects against uploading partially written files.

      Input:
        - Path: Full path to the candidate file.

      Behavior:
        - Polls file length until it stops changing.
        - Attempts to open the file with read access; retries briefly on failure.
    #>
    param([string]$Path)

    $lastLen = -1
    while ($true) {
        try {
            $fi = Get-Item -LiteralPath $Path -ErrorAction Stop
            if ($fi.Length -eq $lastLen) { break }    # size stable -> proceed
            $lastLen = $fi.Length
        } catch { }
        Start-Sleep -Milliseconds 600                 # gentle backoff to reduce churn
    }

    # Final readiness check: ensure no exclusive lock
    for ($i=0; $i -lt 10; $i++) {
        try { $fs = [IO.File]::Open($Path,'Open','Read','None'); $fs.Close(); break }
        catch { Start-Sleep -Milliseconds 400 }
    }
}

function Process-One {
    <#
      Purpose:
        Safely process a single file event: check stability, de-duplicate by last-write ticks,
        and invoke the uploader with the file name.

      Input:
        - Path: Full path to the detected file.

      Output:
        - None (side-effect: runs 2-upload_audio.ps1; updates $script:processed).

      Notes:
        - If the uploader deletes the file on success, we still record the ticks
          so subsequent events for that timestamp are ignored.
    #>
    param([string]$Path)

    # File may disappear between event and handling; bail quietly
    if (-not (Test-Path -LiteralPath $Path)) { return }

    # Resolve file info (silently ignore races)
    $fi = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $fi) { return }

    $key = $fi.FullName
    $ticks = $fi.LastWriteTimeUtc.Ticks

    # Skip if we've already handled this exact LastWrite (de-dup protection)
    if ($script:processed.ContainsKey($key) -and $script:processed[$key] -eq $ticks) { return }

    # Wait until the file is fully written and unlocked
    Wait-FileReady $key

    # Re-check after the readiness wait in case the file was moved/deleted
    $fi = Get-Item -LiteralPath $key -ErrorAction SilentlyContinue
    if (-not $fi) { return }

    # Invoke the uploader with only the file name (script resolves the ingest dir itself)
    Write-Host "`nDetected: $($fi.Name) -> uploading..."
    & $UploaderPath -FileName $fi.Name

    # Record the processed ticks whether the file still exists or was removed by the uploader
    if (Test-Path -LiteralPath $key) {
        $script:processed[$key] = (Get-Item -LiteralPath $key).LastWriteTimeUtc.Ticks
    } else {
        # File deleted by uploader (success) — remember the ticks we processed
        $script:processed[$key] = $ticks
    }
}


# ─────────────────────────────────────────────
# Initial sweep (catch files already present)
# ─────────────────────────────────────────────

Get-ChildItem -Path (Join-Path $IngestDir '*') -File -ErrorAction SilentlyContinue |
    ForEach-Object { Process-One $_.FullName }


# ─────────────────────────────────────────────
# Event-driven watcher (primary detection)
# ─────────────────────────────────────────────

# Construct watcher for file creates/renames/changes in the ingest directory
$fsw = New-Object IO.FileSystemWatcher
$fsw.Path                  = $IngestDir
$fsw.Filter                = '*'
$fsw.IncludeSubdirectories = $false
$fsw.NotifyFilter          = [IO.NotifyFilters]'FileName, LastWrite'
$fsw.EnableRaisingEvents   = $true

# Wire up event handlers; each calls Process-One with the affected path
Register-ObjectEvent -InputObject $fsw -EventName Created -SourceIdentifier IngestCreated -Action {
    Process-One $EventArgs.FullPath
} | Out-Null
Register-ObjectEvent -InputObject $fsw -EventName Renamed -SourceIdentifier IngestRenamed -Action {
    Process-One $EventArgs.FullPath
} | Out-Null
Register-ObjectEvent -InputObject $fsw -EventName Changed -SourceIdentifier IngestChanged -Action {
    Process-One $EventArgs.FullPath
} | Out-Null


# ─────────────────────────────────────────────
# Operator messaging
# ─────────────────────────────────────────────

Write-Host "Watching: $IngestDir"
Write-Host "Uploader: $UploaderPath"
Write-Host "Drop files into the folder. Press Ctrl+C to stop."


# ─────────────────────────────────────────────
# Light polling fallback (every 3s)
# ─────────────────────────────────────────────

# Polling catches edge cases the watcher might miss (e.g., network shares, editor quirks)
$pollSeconds = 3
while ($true) {
    Start-Sleep -Seconds $pollSeconds
    Get-ChildItem -Path (Join-Path $IngestDir '*') -File -ErrorAction SilentlyContinue |
        ForEach-Object { Process-One $_.FullName }
}
