###############################################################################
# submit-job.ps1 — Submit a Whisper transcription job to AWS Batch
#
# What this script does:
# - Prepares container overrides (vCPUs, memory, env vars, tokens, I/O URIs)
# - Writes overrides to a temporary JSON file (UTF-8, no BOM)
# - Resolves fresh ARNs for the job queue and job definition
# - Submits a Batch job with those overrides
# - Prints the submitted Job ID and verifies environment injection
#
# Prerequisites:
# - AWS CLI configured with credentials + region
# - Phase 3/4 infrastructure deployed (queue, job definition, buckets, etc.)
###############################################################################

# ── User-configurable values ─────────────────────────────────────────────────
$Region        = "eu-west-1"
$QueueName     = "openai-whisper-gpu-queue"
$JobDefName    = "openai-whisper-transcribe-job" # Active job definition name (not ARN)
$ResultsBucket = "nimbus-transcribe-results-155186308102-eu-west-1"
$ResultsPrefix = "chunks/task-0002/"             # trailing slash keeps outputs tidy
$InUri         = "s3://nimbus-transcribe-ingest-155186308102-eu-west-1/chunks/task-0002/001.wav"
$OutUri        = "s3://nimbus-transcribe-results-155186308102-eu-west-1/chunks/task-0002/out.json"
$HfToken       = "hugging face token"

# Model & runtime knobs
$Model       = "large-v3"
$Language    = ""                  # leave empty if not forcing
$ComputeType = "int8_float16"      # fastest/cheapest on a single GPU

# vCPU / memory (fits within g5.xlarge limits)
$vcpus  = 4
$memMiB = 10000

# ── Build container overrides (env vars + resources) ─────────────────────────
$Env = @(
  @{ name = "MODEL";                     value = $Model },
  @{ name = "LANGUAGE";                  value = $Language },
  @{ name = "COMPUTE_TYPE";              value = $ComputeType },
  @{ name = "HF_TOKEN";                  value = $HfToken },
  @{ name = "HUGGINGFACE_HUB_TOKEN";     value = $HfToken },
  @{ name = "HF_HUB_ENABLE_HF_TRANSFER"; value = "0" },  # prevent 403 retry loop
  @{ name = "IN_URI";                    value = $InUri },
  @{ name = "OUT_BUCKET";                value = $ResultsBucket }, # style A (bucket/prefix)
  @{ name = "OUT_PREFIX";                value = $ResultsPrefix },
  @{ name = "OUT_URI";                   value = $OutUri },        # style B (direct URI)
  @{ name = "HF_ENDPOINT";               value = "https://huggingface.co" },
  @{ name = "RESULTS_PREFIX";            value = $ResultsPrefix }
)

$OverridesObj = @{
  vcpus       = $vcpus
  memory      = $memMiB
  environment = $Env
}

# ── Write overrides to temp JSON (UTF-8 no BOM) ──────────────────────────────
$Stamp      = (Get-Date).ToString('yyyyMMdd-HHmmss')
$OverridesF = Join-Path $env:TEMP "overrides-$Stamp.json"
$utf8NoBom  = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OverridesF, ($OverridesObj | ConvertTo-Json -Depth 8 -Compress), $utf8NoBom)

# Sanity check: ensure file is BOM-free (first 3 bytes should NOT print)
(Get-Content -Encoding Byte -TotalCount 3 $OverridesF) -join ','

# ── Resolve ARNs for queue + job definition ──────────────────────────────────
$QueueArn = (aws batch describe-job-queues `
  --job-queues $QueueName --region $Region | ConvertFrom-Json).jobQueues[0].jobQueueArn

$JobDefArn = (aws batch describe-job-definitions `
  --job-definition-name $JobDefName --status ACTIVE --region $Region | ConvertFrom-Json).jobDefinitions |
  Sort-Object revision -Descending | Select-Object -First 1 -ExpandProperty jobDefinitionArn

if ([string]::IsNullOrWhiteSpace($QueueArn))  { throw "Queue ARN not found. Check name/region." }
if ([string]::IsNullOrWhiteSpace($JobDefArn)) { throw "Job definition ARN not found. Check name/region." }

# ── Submit job ───────────────────────────────────────────────────────────────
$JobName = "openai-whisper-test-job-$Stamp"
$args = @(
  "batch", "submit-job",
  "--region",         $Region,
  "--job-name",       $JobName,
  "--job-queue",      $QueueArn,
  "--job-definition", $JobDefArn,
  "--container-overrides", ("file://{0}" -f $OverridesF)
)

$SubmitOut = (& aws @args | ConvertFrom-Json)
$JobIdAws  = $SubmitOut.jobId
"Submitted: $JobName  (JobId: $JobIdAws)"

# ── Verify environment injection ─────────────────────────────────────────────
aws batch describe-jobs --jobs $JobIdAws --region $Region `
  --query "jobs[0].container.environment[?name=='IN_URI' || name=='OUT_BUCKET' || name=='OUT_PREFIX' || name=='OUT_URI' || name=='LANGUAGE' || name=='HF_HUB_ENABLE_HF_TRANSFER' || name=='MODEL']" | Out-String
