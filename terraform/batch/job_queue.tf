###############################################################################
# job_queue.tf — AWS Batch Job Queue
#
# What this does:
# - Defines a Batch job queue for GPU-based transcription jobs
# - Associates the queue with the GPU compute environment
#
# Notes:
# - Jobs submitted here will be placed into the linked compute environment(s)
# - Priority is 1 (increase if you add multiple queues later)
###############################################################################

# ── Local values ─────────────────────────────────────────────────────────────
locals {
  job_queue_name = "openai-whisper-gpu-queue"
}

# ── Job Queue ────────────────────────────────────────────────────────────────
resource "aws_batch_job_queue" "gpu_queue" {
  name     = local.job_queue_name
  state    = "ENABLED"
  priority = 1

  # v5.x provider syntax for compute environment ordering
  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.gpu_env_v2.arn           #     gpu_env.arn for previous one
  }

  tags = {
    Project = "nimbus-trancsribe"
    Phase   = "3-aws-batch-gpu"
  }
}
