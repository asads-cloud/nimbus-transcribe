###############################################################################
# outputs.tf — Exported values for AWS Batch Module
#
# These outputs expose key ARNs and names from the Batch IAM + logging setup.
# They can be consumed by other modules (e.g., job definitions, pipelines).
###############################################################################

# ── IAM Roles / Instance Profile ─────────────────────────────────────────────
output "batch_service_role_arn" {
  description = "ARN of the AWS Batch service role (used by Batch control plane)"
  value       = aws_iam_role.batch_service.arn
}

output "ecs_instance_profile_arn" {
  description = "ARN of the ECS instance profile (used by EC2 compute environments)"
  value       = aws_iam_instance_profile.ecs_instance_profile.arn
}

output "batch_job_role_arn" {
  description = "ARN of the IAM role used by Batch jobs/containers (grants S3 access)"
  value       = aws_iam_role.batch_job_role.arn
}

# ── CloudWatch Logging ───────────────────────────────────────────────────────
output "log_group_name" {
  description = "Name of the CloudWatch Logs group used by Batch jobs (awslogs driver)"
  value       = aws_cloudwatch_log_group.batch_jobs.name
}

# ── Job Queue ────────────────────────────────────────────────────────────────
output "job_queue_arn" {
  description = "ARN of the Batch job queue for GPU-based jobs"
  value       = aws_batch_job_queue.gpu_queue.arn
}

# ── Job Definition ───────────────────────────────────────────────────────────
output "job_definition_arn" {
  description = "ARN of the Batch job definition for Whisper transcription"
  value       = aws_batch_job_definition.openai_whisper_job.arn
}
