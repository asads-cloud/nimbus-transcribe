###############################################################################
# outputs.tf — Module outputs for Step Functions
#
# What this does:
# - Exposes key values from this module so they can be referenced by
#   other Terraform configurations (e.g., root modules or other stacks).
###############################################################################

# ── IAM Role Output ──────────────────────────────────────────────────────────
output "step_functions_role_arn" {
  description = "ARN of the IAM role assumed by Step Functions"
  value       = aws_iam_role.sf_role.arn
}

# ── CloudWatch Logs Output ───────────────────────────────────────────────────
output "state_logs_group_name" {
  description = "Name of the CloudWatch Logs group for Step Functions executions"
  value       = aws_cloudwatch_log_group.sf_logs.name
}

# ── State Machine ARN ────────────────────────────────────────────────────────
output "state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.openai_whisper_map.arn
}

# ── State Machine Name ───────────────────────────────────────────────────────
output "state_machine_name" {
  description = "Name of the Step Functions state machine"
  value       = aws_sfn_state_machine.openai_whisper_map.name
}