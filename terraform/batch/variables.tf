###############################################################################
# variables.tf — Inputs for AWS Batch Module
#
# These variables configure the Batch module. Some have defaults, while others
# (like S3 bucket names) must be provided externally (e.g., via terraform.tfvars).
###############################################################################

# ── Core settings ────────────────────────────────────────────────────────────
variable "region" {
  description = "AWS region where Batch resources will be deployed"
  type        = string
  default     = "eu-west-1"
}

# ── S3 buckets ───────────────────────────────────────────────────────────────
variable "ingest_bucket_name" {
  description = "Name of the S3 ingest bucket (holds input audio and chunks)"
  type        = string
}

variable "results_bucket_name" {
  description = "Name of the S3 results bucket (stores transcription results)"
  type        = string
}

# ── Tagging ──────────────────────────────────────────────────────────────────
variable "extra_tags" {
  description = "Optional extra tags to merge with defaults"
  type        = map(string)
  default     = {}
}

# ── Container image ──────────────────────────────────────────────────────────
variable "ecr_image_uri" {
  description = "Full ECR image URI for openai-whisper-faster:latest"
  type        = string
}
