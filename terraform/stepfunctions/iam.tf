###############################################################################
# iam.tf — IAM roles and policies for Step Functions module
#
# What this does:
# - Creates an IAM role that Step Functions can assume.
# - Attaches an inline policy granting access to Batch, EventBridge, Lambda,
#   S3 buckets, and CloudWatch Logs (as required by the workflow).
# - Sets up a CloudWatch log group for Step Functions logs.
###############################################################################

# ── Local Helpers ────────────────────────────────────────────────────────────
locals {
  ingest_bucket_arn  = "arn:aws:s3:::${var.ingest_bucket_name}"
  results_bucket_arn = "arn:aws:s3:::${var.results_bucket_name}"
}

# ── CloudWatch Logs ──────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "sf_logs" {
  name              = var.log_group_name
  retention_in_days = 30
}

# ── IAM Role Trust Policy ─────────────────────────────────────────────────────
# Defines trust relationship: allows Step Functions to assume this role.
data "aws_iam_policy_document" "sf_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# ── IAM Role for Step Functions ──────────────────────────────────────────────
resource "aws_iam_role" "sf_role" {
  name                  = "openai-whisper-transcribe-steps-role"
  assume_role_policy    = data.aws_iam_policy_document.sf_assume_role.json
  force_detach_policies = true
  tags = {
    Project = "nimbus-transcribe"
    Phase   = "4"
  }
}

# ── IAM Policy Document ──────────────────────────────────────────────────────
# Defines permissions granted to Step Functions.
data "aws_iam_policy_document" "sf_policy" {
  # Batch job submission & description
  statement {
    sid       = "BatchSubmitDescribe"
    effect    = "Allow"
    actions   = ["batch:SubmitJob", "batch:DescribeJobs"]
    resources = ["*"]
  }

  # Scale the Batch compute environment up/down
  statement {
    sid       = "BatchUpdateComputeEnvironment"
    effect    = "Allow"
    actions   = ["batch:UpdateComputeEnvironment"]
    resources = [var.compute_environment_arn]
  }

  # Allow Distributed Map to start a Map Run / child executions
  statement {
    sid     = "StartExecutionsForDistributedMap"
    effect  = "Allow"
    actions = ["states:StartExecution"]
    resources = [
      "arn:aws:states:${var.region}:${data.aws_caller_identity.current.account_id}:stateMachine:openai-whisper-transcribe-map"
    ]
  }

  # EventBridge access (needed for Step Functions .sync integration)
  statement {
    sid    = "EventsForSync"
    effect = "Allow"
    actions = [
      "events:PutTargets",
      "events:PutRule",
      "events:DescribeRule",
      "events:DeleteRule",
      "events:RemoveTargets"
    ]
    resources = ["*"]
  }

  # Lambda invoke (restricts to ARNs if provided, otherwise allows all)
  statement {
    sid       = "InvokeLambda"
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction", "lambda:InvokeAsync"]
    resources = length(var.lambda_function_arns) > 0 ? var.lambda_function_arns : ["*"]
  }

  # S3 read: ingest bucket
  statement {
    sid    = "S3ReadIngest"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectAttributes",
      "s3:GetObjectTagging",
      "s3:ListBucket"
    ]
    resources = [
      local.ingest_bucket_arn,
      "${local.ingest_bucket_arn}/*"
    ]
  }

  # S3 read: results bucket
  statement {
    sid    = "S3ReadResults"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectAttributes",
      "s3:GetObjectTagging",
      "s3:ListBucket"
    ]
    resources = [
      local.results_bucket_arn,
      "${local.results_bucket_arn}/*"
    ]
  }

  # CloudWatch Logs vended delivery permissions
  statement {
    sid    = "LogsVendedPermissions"
    effect = "Allow"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups"
    ]
    resources = ["*"]
  }
}

# ── IAM Role Policy Attachment ───────────────────────────────────────────────
resource "aws_iam_role_policy" "sf_inline" {
  name   = "openai-whisper-transcribe-steps-policy"
  role   = aws_iam_role.sf_role.id
  policy = data.aws_iam_policy_document.sf_policy.json
}
