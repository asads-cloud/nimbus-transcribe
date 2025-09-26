###############################################################################
# terraform.tfvars — Variable values for Step Functions module
#
# What this does:
# - Provides concrete values for variables defined in variables.tf.
# - Sets region, S3 bucket names, Lambda ARNs, Batch ARNs, and state machine
#   settings.
###############################################################################

# ── AWS Region ───────────────────────────────────────────────────────────────
region = "eu-west-1"

# ── S3 Buckets ───────────────────────────────────────────────────────────────
ingest_bucket_name  = "nimbus-transcribe-ingest-155186308102-eu-west-1"
results_bucket_name = "nimbus-transcribe-results-155186308102-eu-west-1"

# ── Lambda Function ARNs ─────────────────────────────────────────────────────
# Restrict Step Functions to specific Lambda functions if needed.
# Leave empty list [] for permissive access.
lambda_function_arns = []

# ── AWS Batch Integration ────────────────────────────────────────────────────
batch_job_queue_arn      = "arn:aws:batch:eu-west-1:155186308102:job-queue/openai-whisper-gpu-queue"
batch_job_definition_arn = "arn:aws:batch:eu-west-1:155186308102:job-definition/openai-whisper-transcribe-job:1" # note :2
batch_override_vcpus     = 4
batch_override_memory_mib= 10000

# ── State Machine Settings ───────────────────────────────────────────────────
map_max_concurrency = 10
state_machine_name  = "openai-whisper-transcribe-map"