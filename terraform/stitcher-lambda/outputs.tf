###############################################################################
# outputs.tf — Module Outputs for Whisper Stitcher Lambda
#
# Exposes key attributes of the deployed Lambda function so that
# other Terraform modules (e.g., Step Functions) can reference them.
###############################################################################

# ─────────────────────────────────────────────
# Lambda outputs
# ─────────────────────────────────────────────
output "lambda_name" {
  value = aws_lambda_function.openai_stitcher.function_name
}

output "lambda_arn" {
  value = aws_lambda_function.openai_stitcher.arn
}
