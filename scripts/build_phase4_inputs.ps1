###############################################################################
# Phase 3 → Phase 4 Inputs Converter (PowerShell)
#
# What this script does:
# - Reads Phase 3 outputs from artifacts/phase3.json
# - Extracts and organizes values into a structured Phase 4 inputs file
# - Writes artifacts/phase4_inputs.json in UTF-8 (no BOM)
#
# Usage:
#   Run after completing Phase 3 Terraform apply.
#   Requires artifacts/phase3.json to exist.
###############################################################################

# ── Paths ────────────────────────────────────────────────────────────────────
$Phase3 = "artifacts/phase3.json"
$Out    = "artifacts/phase4_inputs.json"

# Ensure Phase 3 output exists before continuing
if (-not (Test-Path $Phase3)) {
  throw "Missing $Phase3 — complete Step 6 first."
}

# ── Load Phase 3 JSON ────────────────────────────────────────────────────────
$P3 = Get-Content $Phase3 -Raw | ConvertFrom-Json

# ── Build Phase 4 Inputs Object ──────────────────────────────────────────────
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

    # Canonical names (handy for orchestration + readability)
    job_definition_name = "openai-whisper-transcribe-job"
    job_queue_name      = "openai-whisper-gpu-queue"
    compute_environment = "openai-whisper-gpu-env"
  }
  iam = @{
    batch_service_role_arn   = $P3.batch_service_role
    ecs_instance_profile_arn = $P3.ecs_instance_profile
    batch_job_role_arn       = $P3.batch_job_role
  }
  logging = @{
    cloudwatch_log_group = $P3.log_group
  }
  defaults = @{
    # Phase 4 safe defaults (tested + recommended)
    model                     = "large-v3"
    language                  = "en"          # ← DO NOT use "auto" with faster-whisper
    compute_type              = "int8_float16"
    chunk_overlap             = "1s"
    chunk_length              = "600s"
    hf_hub_enable_hf_transfer = "0"           # ← prevents the 403 retry loop
    out_filename              = "out.json"    # ← standardized JSON output name
  }
}

# ── Write JSON Output ────────────────────────────────────────────────────────
# Save as UTF-8 without BOM for compatibility
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText(
  $Out,
  ($Phase4 | ConvertTo-Json -Depth 10),
  $utf8NoBom
)

"Saved: $Out"
