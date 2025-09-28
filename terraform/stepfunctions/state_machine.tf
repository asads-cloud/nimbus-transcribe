###############################################################################
# state_machine.tf — Step Functions state machine resource
#
# What this does:
# - Renders the state machine ASL (Amazon States Language) definition template.
# - Creates a Step Functions state machine using that definition.
# - Configures logging to CloudWatch with execution data included.
#
# Notes:
# - State machine logic is defined in state_machine.asl.json.tftpl.
# - Uses IAM role from iam.tf for execution permissions.
###############################################################################

# ── Local Variables ──────────────────────────────────────────────────────────
# Render the ASL JSON definition from template with provided variables.
locals {
  asl_definition = templatefile("${path.module}/state_machine.asl.json.tftpl", {
    batch_job_queue_arn      = var.batch_job_queue_arn
    batch_job_definition_arn = var.batch_job_definition_arn
    map_max_concurrency      = var.map_max_concurrency
    batch_override_vcpus      = var.batch_override_vcpus
    batch_override_memory_mib = var.batch_override_memory_mib
    stitcher_lambda_arn       = var.openai_stitcher_lambda_arn
    ingest_bucket_name        = var.ingest_bucket_name
    results_bucket_name       = var.results_bucket_name
  })
}

# ── Step Functions State Machine ─────────────────────────────────────────────
resource "aws_sfn_state_machine" "openai_whisper_map" {
  name       = var.state_machine_name
  role_arn   = aws_iam_role.sf_role.arn
  definition = local.asl_definition
  type       = "STANDARD"

  # Configure CloudWatch vended logs for visibility into executions
  logging_configuration {
    include_execution_data = true
    level                  = "ALL"
    log_destination        = "${aws_cloudwatch_log_group.sf_logs.arn}:*"
  }

  tags = {
    Project = "nimbus-transcribe"
    Phase   = "4"
  }
}

# ── Caller Identity Data Source ──────────────────────────────────────────────
# Used for referencing AWS account ID in log destination ARN.
data "aws_caller_identity" "current" {}
