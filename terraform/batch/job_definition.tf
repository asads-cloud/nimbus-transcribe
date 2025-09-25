###############################################################################
# job_definition.tf — AWS Batch Job Definition
#
# What this does:
# - Defines a Batch job for Whisper transcription (GPU-enabled)
# - Uses container image from ECR
# - Configures resources, environment variables, and logging
# - Supports retries and timeouts
#
# Notes:
# - Command is left empty; it will be overridden at submission time.
# - Allocates 4 vCPUs, 16 GB memory, and 1 GPU.
###############################################################################

# ── Local values ─────────────────────────────────────────────────────────────
locals {
  job_definition_name = "openai-whisper-transcribe-job"
}

# ── Job Definition ───────────────────────────────────────────────────────────
resource "aws_batch_job_definition" "openai_whisper_job" {
  name                  = local.job_definition_name
  type                  = "container"
  platform_capabilities = ["EC2"]

  # Container settings (JSON-encoded block)
  container_properties = jsonencode({
    image      = var.ecr_image_uri
    jobRoleArn = aws_iam_role.batch_job_role.arn

    # Command left empty; override when submitting jobs
    command = []

    # Resource requests
    vcpus  = 4
    memory = 16000
    resourceRequirements = [
      { type = "GPU", value = "1" }
    ]

    # Default environment variables (can be overridden per job)
    environment = [
      { name = "MODEL",          value = "large-v3" },
      { name = "LANGUAGE",       value = "auto" },
      { name = "COMPUTE_TYPE",   value = "int8_float16" },
      { name = "CHUNK_S3_URI",   value = "" },
      { name = "RESULTS_BUCKET", value = "" },
      { name = "RESULTS_PREFIX", value = "chunks/" }
    ]

    # Logging configuration (CloudWatch Logs)
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/aws/batch/job"
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "openai-whisper"
      }
    }

    # Security settings
    readonlyRootFilesystem = false
    privileged             = false

    # Empty placeholders (can be extended later if needed)
    ulimits     = []
    volumes     = []
    mountPoints = []
  })

  # Retry strategy — retry once for host-level errors
  retry_strategy {
    attempts = 2
    evaluate_on_exit {
      on_status_reason = "Host EC2*"
      action           = "RETRY"
    }
  }

  # Timeout (2 hours max per attempt)
  timeout {
    attempt_duration_seconds = 7200
  }

  tags = {
    Project = "nimbus-transcribe"
    Phase   = "3-aws-batch-gpu"
  }
}
