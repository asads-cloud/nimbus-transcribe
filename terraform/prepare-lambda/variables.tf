###############################################################################
# variables.tf — Inputs for Prepare Lambda module
#
# This file defines configurable inputs for the Terraform module that provisions
# the "prepare" Lambda. Defaults are sensible for dev/demo but can be overridden.
###############################################################################

# ── Core project settings ─────────────────────────────────────────────────────
variable "region" {
  type    = string
  default = "eu-west-1" # Default AWS region
}

variable "project" {
  type    = string
  default = "nimbus-transcribe" # Project prefix for resource naming
}

# ── S3 buckets ───────────────────────────────────────────────────────────────
# Bucket names must be globally unique in AWS.
# Change these if conflicts occur in another AWS account/region.
variable "ingest_bucket_name" {
  type    = string
  default = "openai-whisper-xcribe-ingest"
}

variable "results_bucket_name" {
  type    = string
  default = "openai-whisper-xcribe-results"
}

# ── Artifact paths (local) ───────────────────────────────────────────────────
# Paths are relative to this module dir.
# - layer_zip_path    : Zip of Lambda Layer containing ffmpeg/ffprobe binaries
# - function_zip_path : Zip of the Lambda function code (prepare.zip)
variable "layer_zip_path" {
  type    = string
  default = "../../artifacts/layers/ffmpeg/ffmpeg-layer.zip"
}

variable "function_zip_path" {
  type    = string
  default = "../../artifacts/lambda/prepare.zip"
}

# ── S3 event filtering ───────────────────────────────────────────────────────
# Optional list of file suffixes to restrict Lambda S3 triggers.
# Only files with these extensions will trigger the Lambda.
variable "audio_suffixes" {
  type = list(string)
  default = [
    ".mp3", ".wav", ".m4a", ".mp4", ".mov", ".mkv",
    ".flac", ".ogg", ".opus"
  ]
}
