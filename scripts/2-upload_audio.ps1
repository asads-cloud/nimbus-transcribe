# .\scripts\2-upload_audio.ps1

<#
.SYNOPSIS
  Upload a local audio/video file to S3, kick off the Step Functions transcription
  workflow, wait for completion, and download the final transcript to Desktop.

.DESCRIPTION
  Workflow:
    1) Picks a file from "Desktop\Nimbus Transcriber\Nimbus Ingest" (or uses -FileName).
    2) Uploads it to the ingest S3 bucket under audio/<JOBID>/<FileName>.
    3) Waits for the prepare step to emit a manifest at s3://<ingest>/manifests/<JOBID>.jsonl.
    4) Writes a UTF-8 (no BOM) task-input.json with the dynamic manifest_key.
    5) Starts the Step Functions execution.
    6) Polls the execution until it is not RUNNING.
    7) On success, downloads the transcript to "Desktop\Nimbus Transcriber\Nimbus Results".

.USAGE
  # Auto-pick newest eligible media from the ingest folder
  .\scripts\2-upload_audio.ps1

  # Or specify the exact file name (must already be in the ingest folder)
  .\scripts\2-upload_audio.ps1 -FileName "Lecture01.mp3"

.PARAMETERS
  -FileName       Optional. File name in Desktop\Nimbus Transcriber\Nimbus Ingest.
  -Region         AWS region (default: eu-west-1).
  -AccountId      AWS account ID used to compose S3 bucket names.
  -StateMachineArn ARN of your Step Functions state machine.
  -Model          Model name to pass to SFN (string).
  -BeamSize       Beam size for decoding (int).
  -ComputeType    "gpu" | "cpu" (whatever your SFN expects).
  -Vad            Boolean for VAD flag.

.NOTES
  - Requires AWS CLI configured with permissions for S3 and Step Functions.
  - The script removes the local source file after a successful S3 upload.
  - Uses UTF-8 without BOM for the SFN input file per your tooling requirement.
#>

# ─────────────────────────────────────────────
# Parameters (tunable inputs + SFN defaults)
# ─────────────────────────────────────────────
param(
  # Optional: the exact file name inside "Desktop\Nimbus Transcriber\Nimbus Ingest".
  # If omitted, the newest audio/video file in the Ingest folder is used.
  [string]$FileName,

  # ---- Tunables (override via -Region etc. if you want) ----
  [string]$Region = "eu-west-1",
  [string]$AccountId = "155186308102",
  [string]$StateMachineArn = "arn:aws:states:eu-west-1:155186308102:stateMachine:openai-whisper-transcribe-map",

  # Step Functions input defaults (adjust if needed)
  [string]$Model = "medium",
  [int]$BeamSize = 1,
  [string]$ComputeType = "gpu",      # gpu|cpu — whatever your SFN expects
  [bool]$Vad = $true
)

# ─────────────────────────────────────────────
# Derived S3 bucket names (once per account/region)
# ─────────────────────────────────────────────
$INGEST  = "nimbus-transcribe-ingest-$AccountId-$Region"
$RESULTS = "nimbus-transcribe-results-$AccountId-$Region"

# ─────────────────────────────────────────────
# Local working folders (Desktop, NOT OneDrive)
# ─────────────────────────────────────────────
$IngestDir  = Join-Path ([Environment]::GetFolderPath('Desktop')) "Nimbus Transcriber\Nimbus Ingest"
$ResultsDir = Join-Path ([Environment]::GetFolderPath('Desktop')) "Nimbus Transcriber\Nimbus Results"
New-Item -ItemType Directory -Path $IngestDir  -Force | Out-Null
New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null

# ─────────────────────────────────────────────
# Pick source file (use newest if -FileName not provided)
# ─────────────────────────────────────────────
if (-not $FileName) {
  $candidate = Get-ChildItem -Path (Join-Path $IngestDir '*') -File `
               -Include *.mp3,*.wav,*.m4a,*.mp4,*.mkv,*.webm |
               Sort-Object LastWriteTime -Descending |
               Select-Object -First 1
  if (-not $candidate) { Write-Error "No audio/video files found in '$IngestDir'."; exit 1 }
  $FileName = $candidate.Name
}
$LocalPath = Join-Path $IngestDir $FileName
if (-not (Test-Path $LocalPath)) { Write-Error "File not found: $LocalPath"; exit 1 }

# ─────────────────────────────────────────────
# Derive JOBID and destination S3 key
# ─────────────────────────────────────────────
$JOBID  = [IO.Path]::GetFileNameWithoutExtension($FileName)
$SRCKEY = "audio/$JOBID/$FileName"

# ─────────────────────────────────────────────
# Simple MIME detection (extension + quick header sniff)
# ─────────────────────────────────────────────
$ext  = [IO.Path]::GetExtension($LocalPath).TrimStart('.').ToLower()
switch ($ext) {
  'mp3'  { $Mime = 'audio/mpeg' }
  'wav'  { $Mime = 'audio/wav' }
  'm4a'  { $Mime = 'audio/mp4' }
  'mp4'  { $Mime = 'video/mp4' }
  'webm' { $Mime = 'video/webm' }
  default {
    $Mime = 'application/octet-stream'
    try {
      $fs = [System.IO.File]::Open($LocalPath, 'Open', 'Read', 'Read')
      $br = New-Object System.IO.BinaryReader($fs)
      $bytes = $br.ReadBytes(4); $fs.Close()
      if ($bytes.Length -ge 3 -and ($bytes[0..2] -join ',') -eq '73,68,51') { $Mime = 'audio/mpeg' } # 'ID3'
      elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and ($bytes[1] -band 0xE0) -eq 0xE0) { $Mime = 'audio/mpeg' }
    } catch { }
  }
}

# ─────────────────────────────────────────────
# Upload to S3 (then remove local on success)
# ─────────────────────────────────────────────
Write-Host "`nUploading..."
Write-Host "  Local : $LocalPath"
Write-Host "  S3    : s3://$INGEST/$SRCKEY"
aws s3 cp "$LocalPath" "s3://$INGEST/$SRCKEY" --content-type "$Mime"
if ($LASTEXITCODE -ne 0) { Write-Error "Upload failed."; exit 1 }

# Delete local only after success
Remove-Item -Path $LocalPath -Force
Write-Host "Upload complete. Deleted: $LocalPath"

# ─────────────────────────────────────────────
# Wait for manifest (emitted by prepare Lambda)
# ─────────────────────────────────────────────
$ManifestKey = "manifests/$JOBID.jsonl"
$maxWaitSecs = 600   # 10 min
$elapsed = 0
Write-Host "`nWaiting for manifest: s3://$INGEST/$ManifestKey"
while ($true) {
  $exists = aws s3 ls "s3://$INGEST/$ManifestKey" 2>$null
  if ($LASTEXITCODE -eq 0 -and $exists) { break }
  Start-Sleep -Seconds 5
  $elapsed += 5
  if ($elapsed -ge $maxWaitSecs) { Write-Error "Timed out waiting for manifest."; exit 1 }
}
Write-Host "Manifest found."

# ─────────────────────────────────────────────
# Build task-input.json (UTF-8 no BOM) with dynamic manifest_key
# ─────────────────────────────────────────────
$AccountId = "155186308102"
$Region    = "eu-west-1"

$INGEST_BUCKET  = "nimbus-transcribe-ingest-$AccountId-$Region"
$RESULTS_BUCKET = "nimbus-transcribe-results-$AccountId-$Region"

# Where to write the JSON (projectRoot\artifacts\task-input.json)
$scriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot  = Split-Path $scriptDir -Parent
$artifactsDir = Join-Path $projectRoot "artifacts"
New-Item -ItemType Directory -Path $artifactsDir -Force | Out-Null
$TaskInputPath = Join-Path $artifactsDir "task-input.json"

# Exact payload expected by your state machine (values mirror current task-input.json)
$taskInputObj = [ordered]@{
  manifest_bucket = $INGEST_BUCKET
  manifest_key    = "manifests/$JOBID.jsonl"     # dynamic!
  results_bucket  = $RESULTS_BUCKET
  model           = "large-v3"
  language        = ""                           # empty string
  compute_type    = "int8_float16"
  beam_size       = 5
  vad             = $true
}

# Write as UTF-8 *without BOM*
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($TaskInputPath, ($taskInputObj | ConvertTo-Json -Depth 5), $utf8NoBom)

Write-Host "`nWrote Step Functions input to: $TaskInputPath (UTF-8 no BOM)"

# ─────────────────────────────────────────────
# Start Step Functions execution with input file
# ─────────────────────────────────────────────
$StateMachineArn = "arn:aws:states:eu-west-1:155186308102:stateMachine:openai-whisper-transcribe-map"

Write-Host "Starting Step Function..."
$start = aws stepfunctions start-execution --state-machine-arn $StateMachineArn --input ("file://{0}" -f $TaskInputPath) | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $start.executionArn) {
  throw "Failed to start execution."
}
$EXEC_ARN = $start.executionArn
Write-Host "ExecutionArn: $EXEC_ARN"

# ─────────────────────────────────────────────
# Poll execution status until finished (with timeout)
# ─────────────────────────────────────────────
$timeoutMins = 120
$begin = Get-Date
do {
  Start-Sleep -Seconds 15
  $status = aws stepfunctions describe-execution --execution-arn $EXEC_ARN --query status --output text
  Write-Host ("Status: {0}  ({1:T})" -f $status, (Get-Date))
  if ((Get-Date) - $begin -gt (New-TimeSpan -Minutes $timeoutMins)) {
    throw "Timed out waiting for Step Function."
  }
} while ($status -eq "RUNNING")

if ($status -ne "SUCCEEDED") {
  $details = aws stepfunctions describe-execution --execution-arn $EXEC_ARN | ConvertFrom-Json
  Write-Host "`nExecution finished with status: $status"
  Write-Host ($details | ConvertTo-Json -Depth 10)
  throw "Transcription pipeline failed."
}

# ─────────────────────────────────────────────
# Download transcript (txt + json) into Desktop\Nimbus Transcriber\Nimbus Results\<JOBID>\
# ─────────────────────────────────────────────
$ResultsRoot   = Join-Path ([Environment]::GetFolderPath('Desktop')) "Nimbus Transcriber\Nimbus Results"
$JobResultsDir = Join-Path $ResultsRoot $JOBID
New-Item -ItemType Directory -Path $JobResultsDir -Force | Out-Null

$TxtKey  = "final/$JOBID/transcript.txt"
$JsonKey = "final/$JOBID/transcript.json"

$TxtDest  = Join-Path $JobResultsDir "transcript.txt"
$JsonDest = Join-Path $JobResultsDir "transcript.json"

Write-Host "`nDownloading transcript files..."

# TXT
aws s3 cp ("s3://{0}/{1}" -f $RESULTS_BUCKET, $TxtKey) "$TxtDest"
if ($LASTEXITCODE -ne 0) { throw "Could not download TXT from s3://$RESULTS_BUCKET/$TxtKey" }
Write-Host "Saved TXT to: $TxtDest"

# JSON (warn if missing rather than fail the whole run)
aws s3 cp ("s3://{0}/{1}" -f $RESULTS_BUCKET, $JsonKey) "$JsonDest"
if ($LASTEXITCODE -ne 0) {
  Write-Warning "JSON not found at s3://$RESULTS_BUCKET/$JsonKey"
} else {
  Write-Host "Saved JSON to: $JsonDest"
}

