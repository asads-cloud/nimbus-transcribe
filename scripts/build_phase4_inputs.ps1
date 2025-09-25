# Paths
$Phase3 = "artifacts/phase3.json"
$Out    = "artifacts/phase4_inputs.json"

if (-not (Test-Path $Phase3)) { throw "Missing $Phase3 — complete Step 6 first." }

$P3 = Get-Content $Phase3 -Raw | ConvertFrom-Json

$Phase4 = [ordered]@{
  region  = $P3.region
  buckets = @{
    ingest  = $P3.ingest_bucket
    results = $P3.results_bucket
  }
  batch = @{
    compute_environment_arn = $P3.compute_environment
    job_queue_arn           = $P3.job_queue
    job_definition_arn      = $P3.job_definition
    # Keep the canonical names handy for Phase 4 orchestration
    job_definition_name     = "openai-whisper-transcribe-job"
    job_queue_name          = "openai-whisper-gpu-queue"
    compute_environment     = "openai-whisper-gpu-env"
  }
  iam = @{
    batch_service_role_arn   = $P3.batch_service_role
    ecs_instance_profile_arn = $P3.ecs_instance_profile
    batch_job_role_arn       = $P3.batch_job_role
  }
  logging = @{
    cloudwatch_log_group = $P3.log_group
  }
  # Phase 4 defaults (safe + what worked for you)
  defaults = @{
    model                     = "large-v3"
    language                  = "en"          # ← DO NOT use "auto" with faster-whisper
    compute_type              = "int8_float16"
    chunk_overlap             = "1s"
    chunk_length              = "600s"
    hf_hub_enable_hf_transfer = "0"           # ← prevents the 403 retry loop
    out_filename              = "out.json"    # ← standardized JSON output object name
  }
}

# Write UTF-8 w/o BOM
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Out, ($Phase4 | ConvertTo-Json -Depth 10), $utf8NoBom)
"Saved: $Out"
