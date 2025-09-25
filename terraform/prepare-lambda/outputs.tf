###############################################################################
# outputs.tf — Useful values exported by the Prepare Lambda module
#
# These outputs allow other modules, stacks, or users to reference
# the key resources created here (S3 buckets, Lambda, Layer).
###############################################################################

# ── S3 Buckets ───────────────────────────────────────────────────────────────
output "ingest_bucket_id" {
  description = "ID of the ingest bucket (holds input audio, chunks, and manifests)"
  value       = aws_s3_bucket.ingest.id
}

output "results_bucket_id" {
  description = "ID of the results bucket (downstream transcription results)"
  value       = aws_s3_bucket.results.id
}

# ── Lambda + Layer ───────────────────────────────────────────────────────────
output "openai_prepare_lambda_arn" {
  description = "ARN of the Prepare Lambda function (audio chunking)"
  value       = aws_lambda_function.openai_prepare.arn
}

output "ffmpeg_layer_arn" {
  description = "ARN of the FFmpeg Lambda Layer"
  value       = aws_lambda_layer_version.ffmpeg.arn
}
