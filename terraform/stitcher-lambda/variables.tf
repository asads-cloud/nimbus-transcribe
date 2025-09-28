###############################################################################
# variables.tf — Input Variables for Whisper Stitcher Lambda
#
# Defines configuration inputs for the Terraform module that deploys the Lambda.
# Adjust these values when consuming this module in higher-level infrastructure.
###############################################################################

# ─────────────────────────────────────────────
# Core AWS settings
# ─────────────────────────────────────────────
variable "region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "project" {
  type    = string
  default = "nimbus-transcribe"
}

# ─────────────────────────────────────────────
# S3 buckets
# ─────────────────────────────────────────────
variable "manifest_bucket" {
  type = string
}

variable "results_bucket" {
  type = string
}

# ─────────────────────────────────────────────
# S3 prefixes (with trailing slashes)
# ─────────────────────────────────────────────
variable "manifest_prefix" {
  type    = string
  default = "manifests/"
}

variable "chunks_prefix" {
  type    = string
  default = "chunks/"
}

variable "final_prefix" {
  type    = string
  default = "final/"
}

# ─────────────────────────────────────────────
# Later integrations
# ─────────────────────────────────────────────
variable "job_table_name" {
  type    = string
  default = ""
}

variable "sns_topic_arn" {
  type    = string
  default = ""
}

# ─────────────────────────────────────────────
# Step Functions integration (optional)
# ─────────────────────────────────────────────
variable "state_machine_arn" {
  type    = string
  default = ""
}

