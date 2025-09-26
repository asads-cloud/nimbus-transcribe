###############################################################################
# variables.tf — Input variables for Step Functions module
#
# What this does:
# - Defines configurable variables for AWS region, S3 buckets, Lambda ARNs
# logging, state machine settings, and Batch integration.
# - Provides defaults for region and log group where sensible.
###############################################################################

# ── AWS Region ───────────────────────────────────────────────────────────────
variable "region" {
  description = "AWS region to deploy into (default: eu-west-1)"
  type        = string
  default     = "eu-west-1"
}

# ── S3 Buckets ───────────────────────────────────────────────────────────────
variable "results_bucket_name" {
  description = "S3 bucket for Step Function results (e.g., nimbus-transcribe-results-<acct>-eu-west-1)"
  type        = string
}

variable "ingest_bucket_name" {
  description = "S3 bucket for audio ingestion (e.g., nimbus-transcribe-ingest-<acct>-eu-west-1)"
  type        = string
}

# ── Lambda Functions ─────────────────────────────────────────────────────────
variable "lambda_function_arns" {
  description = "List of Lambda function ARNs the Step Function may call. Can be empty."
  type        = list(string)
  default     = []
}

# ── CloudWatch Logging ───────────────────────────────────────────────────────
variable "log_group_name" {
  description = "CloudWatch Logs group for Step Functions execution logs (default path provided)"
  type        = string
  default     = "/aws/vendedlogs/states/openai-whisper-transcribe"
}

# ── State Machine Settings ───────────────────────────────────────────────────
variable "state_machine_name" {
  description = "Name of the Step Functions state machine"
  type        = string
  default     = "openai-whisper-transcribe-map"
}

variable "map_max_concurrency" {
  description = "Maximum number of child workflows to run in parallel in the Distributed Map state"
  type        = number
  default     = 10
}

# ── AWS Batch Integration ────────────────────────────────────────────────────
variable "batch_job_queue_arn" {
  description = "ARN of the AWS Batch Job Queue (from Phase 3 setup)"
  type        = string
}

variable "batch_job_definition_arn" {
  description = "ARN of the AWS Batch Job Definition (from Phase 3 setup)"
  type        = string
}

variable "batch_override_vcpus" {
  description = "Container vCPU override for Batch job"
  type        = number
  default     = 4
}

variable "batch_override_memory_mib" {
  description = "Container memory MiB override for Batch job"
  type        = number
  default     = 10000
}
