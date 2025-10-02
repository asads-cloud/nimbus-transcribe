###############################################################################
# terraform.tfvars — Nimbus Transcribe overrides
###############################################################################

# ── Core settings ────────────────────────────────────────────────────────────
region = "eu-west-1"

# ── S3 buckets (must be unique per AWS account/region) ────────────────────────
ingest_bucket_name  = "nimbus-transcribe-ingest-155186308102-eu-west-1"
results_bucket_name = "nimbus-transcribe-results-155186308102-eu-west-1"

# ── Additional tags applied to resources ─────────────────────────────────────
extra_tags = {
  Environment = "prod"
  Phase       = "3-aws-batch-gpu"
}

# ── Container image for Batch jobs ───────────────────────────────────────────
# Full ECR URI of the whisper-faster image to run inside Batch jobs
ecr_image_uri = "155186308102.dkr.ecr.eu-west-1.amazonaws.com/openai-whisper-faster"

ecr_account_id = "155186308102"
ecr_repo       = "openai-whisper-faster"
ecr_tag        = "latest"