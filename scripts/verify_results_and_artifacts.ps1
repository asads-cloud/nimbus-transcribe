# --- Inputs you already have (adjust only the lines marked '<< set me' ) ---
$Region        = "eu-west-1"
$AccountId     = (aws sts get-caller-identity | ConvertFrom-Json).Account   # auto-resolve
$IngestBucket  = "nimbus-transcribe-ingest-$AccountId-eu-west-1"
$ResultsBucket = "nimbus-transcribe-results-$AccountId-eu-west-1"

# The folder you wrote results to in Step 5. If you used the tutorial job id value, set it here.
# Example from your last success: test-job-0002
$JobIdValue    = "task-0002"     # << set me if different
$ResultsPrefix = "chunks/$JobIdValue/"

Write-Host "Results prefix: s3://$ResultsBucket/$ResultsPrefix"

# --- 1) Verify at least one transcript exists (accepts both styles) -----------------------------

# Use s3api so we get exact keys back (not just pretty listings)
$resp = aws s3api list-objects-v2 --bucket $ResultsBucket --prefix $ResultsPrefix --region $Region | ConvertFrom-Json
$keys = @()
if ($resp.Contents) { $keys = $resp.Contents | ForEach-Object { $_.Key } }

if (-not $keys -or $keys.Count -eq 0) {
  Write-Host "No objects found under s3://$ResultsBucket/$ResultsPrefix"
} else {
  Write-Host "Found objects:"; $keys | ForEach-Object { " - $_" }
}

# Prefer a real .json object; otherwise fall back to the 'directory key' that equals the prefix
$JsonKey = $keys | Where-Object { $_ -match '\.json$' } | Select-Object -First 1
if (-not $JsonKey -and ($keys -contains $ResultsPrefix)) { $JsonKey = $ResultsPrefix }

if ($JsonKey) {
  Write-Host "Using result key: $JsonKey"
} else {
  Write-Host "No JSON result found and no fallback object equals the prefix." ; return
}

# --- 2) Preview the first result locally (rename sensibly if the key is just the prefix) --------

$leaf = (Split-Path $JsonKey -Leaf)
if ([string]::IsNullOrWhiteSpace($leaf) -or $leaf -eq "/") { $leaf = "out.json" }   # handle the slash-object case
$LocalPath = Join-Path $env:TEMP $leaf

aws s3 cp "s3://$ResultsBucket/$JsonKey" $LocalPath --region $Region | Out-Null
Write-Host "Preview of $leaf (first 50 lines):"
Get-Content $LocalPath -TotalCount 50

# --- helpers that work on Windows PowerShell 5.1 ---
function Try-Json($scriptBlock) {
  try { & $scriptBlock } catch { $null }
}

# --- 3) Capture Batch / roles / logs metadata into artifacts/phase3.json ---

$CE  = Try-Json { aws batch describe-compute-environments --compute-environments openai-whisper-gpu-env --region $Region | ConvertFrom-Json }
$JQ  = Try-Json { aws batch describe-job-queues         --job-queues          openai-whisper-gpu-queue      --region $Region | ConvertFrom-Json }
$JD  = Try-Json { aws batch describe-job-definitions    --job-definition-name openai-whisper-transcribe-job  --status ACTIVE --region $Region | ConvertFrom-Json }
$BSR = Try-Json { aws iam get-role --role-name AWSBatchServiceRole | ConvertFrom-Json }
$EIP = Try-Json { aws iam get-instance-profile --instance-profile-name ecsInstanceRole | ConvertFrom-Json }
$JRR = Try-Json { aws iam get-role --role-name batch_job_role | ConvertFrom-Json }

# Defensive extraction (no ?.)
$computeEnvArn   = $null
if ($CE -and $CE.computeEnvironments -and $CE.computeEnvironments.Count -gt 0) {
  $computeEnvArn = $CE.computeEnvironments[0].computeEnvironmentArn
}

$jobQueueArn     = $null
if ($JQ -and $JQ.jobQueues -and $JQ.jobQueues.Count -gt 0) {
  $jobQueueArn = $JQ.jobQueues[0].jobQueueArn
}

$jobDefArn       = $null
if ($JD -and $JD.jobDefinitions -and $JD.jobDefinitions.Count -gt 0) {
  $jobDefArn = $JD.jobDefinitions[0].jobDefinitionArn
}

$batchServiceRoleArn   = if ($BSR) { $BSR.Role.Arn } else { $null }
$instanceProfileArn    = if ($EIP) { $EIP.InstanceProfile.Arn } else { $null }
$batchJobRoleArn       = if ($JRR) { $JRR.Role.Arn } else { $null }

$Out = [ordered]@{
  phase                 = "3-aws-batch-gpu"
  timestamp_utc         = (Get-Date).ToUniversalTime().ToString("o")
  region                = $Region
  account_id            = $AccountId
  ingest_bucket         = $IngestBucket
  results_bucket        = $ResultsBucket
  job_id_example        = $JobIdValue
  results_prefix        = $ResultsPrefix
  result_key_captured   = $JsonKey

  compute_environment   = $computeEnvArn
  job_queue             = $jobQueueArn
  job_definition        = $jobDefArn
  batch_service_role    = $batchServiceRoleArn
  ecs_instance_profile  = $instanceProfileArn
  batch_job_role        = $batchJobRoleArn
  log_group             = "/aws/batch/job"
}

$ArtifactsDir = Join-Path (Get-Location) "artifacts"
New-Item -ItemType Directory -Force -Path $ArtifactsDir | Out-Null
$OutPath = Join-Path $ArtifactsDir "phase3.json"
($Out | ConvertTo-Json -Depth 8) | Set-Content $OutPath -Encoding UTF8
Write-Host "Saved artifacts to: $OutPath"

# --- 4) (Optional) Show a few recent SUCCEEDED jobs ---
$Jobs = Try-Json { aws batch list-jobs --job-queue whisper-gpu-queue --job-status SUCCEEDED --region $Region | ConvertFrom-Json }
if ($Jobs -and $Jobs.jobSummaryList) {
  $Jobs.jobSummaryList |
    Sort-Object -Property createdAt -Descending |
    Select-Object -First 3 -Property jobId,jobName,createdAt,stoppedAt
}
