###############################################################################
# main.tf — Openai Whisper Stitcher Lambda Deployment
#
# This Terraform module packages and deploys the "stitcher" Lambda function.
# It handles:
# - Zipping the Python source in `lambdas/stitcher`
# - Creating an IAM role with S3 (required), DynamoDB/SNS (future proofing) permissions
# - Deploying the Lambda with environment variables
# - Granting Step Functions permission to invoke it
###############################################################################

# ─────────────────────────────────────────────
# Terraform & Providers
# ─────────────────────────────────────────────
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ─────────────────────────────────────────────
# Locals (tags and artifact path)
# ─────────────────────────────────────────────
locals {
  tags = {
    Project = var.project
    Stack   = "stitcher-lambda"
  }

  # Path to prebuilt zip in artifacts/lambda/
  function_zip_abs = abspath("${path.module}/../../artifacts/lambda/stitcher.zip")
}
# ─────────────────────────────────────────────
# IAM Role & Trust
# ─────────────────────────────────────────────
data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "openai_stitcher_role" {
  name               = "openai-whisper-stitcher-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

# Basic execution role (logs)
resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.openai_stitcher_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ─────────────────────────────────────────────
# S3 Access Policy
# ─────────────────────────────────────────────
data "aws_iam_policy_document" "s3_access" {
  statement {
    sid = "ReadManifest"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::${var.manifest_bucket}",
      "arn:aws:s3:::${var.manifest_bucket}/${var.manifest_prefix}*"
    ]
  }

  statement {
    sid = "ReadChunks"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:HeadObject"
    ]
    resources = [
      "arn:aws:s3:::${var.results_bucket}",
      "arn:aws:s3:::${var.results_bucket}/${var.chunks_prefix}*"
    ]
  }

  statement {
    sid = "WriteFinals"
    actions = [
      "s3:PutObject",
      "s3:AbortMultipartUpload",
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::${var.results_bucket}",
      "arn:aws:s3:::${var.results_bucket}/${var.final_prefix}*"
    ]
  }
}

resource "aws_iam_policy" "s3_access" {
  name   = "openai-whisper-stitcher-s3-access"
  policy = data.aws_iam_policy_document.s3_access.json
}

resource "aws_iam_role_policy_attachment" "s3_attach" {
  role       = aws_iam_role.openai_stitcher_role.name
  policy_arn = aws_iam_policy.s3_access.arn
}

# ─────────────────────────────────────────────
# Later versions: DynamoDB Access
# ─────────────────────────────────────────────
data "aws_iam_policy_document" "ddb_access" {
  count = var.job_table_name == "" ? 0 : 1

  statement {
    actions = [
      "dynamodb:UpdateItem",
      "dynamodb:PutItem",
      "dynamodb:GetItem"
    ]
    resources = [
      "arn:aws:dynamodb:${var.region}:${var.account_id}:table/${var.job_table_name}"
    ]
  }
}

resource "aws_iam_policy" "ddb_access" {
  count  = var.job_table_name == "" ? 0 : 1
  name   = "openai-whisper-stitcher-ddb-access"
  policy = data.aws_iam_policy_document.ddb_access[0].json
}

resource "aws_iam_role_policy_attachment" "ddb_attach" {
  count      = var.job_table_name == "" ? 0 : 1
  role       = aws_iam_role.openai_stitcher_role.name
  policy_arn = aws_iam_policy.ddb_access[0].arn
}

# ─────────────────────────────────────────────
# Later versions: SNS Access
# ─────────────────────────────────────────────
data "aws_iam_policy_document" "sns_access" {
  count = var.sns_topic_arn == "" ? 0 : 1

  statement {
    actions = [
      "sns:Publish"
    ]
    resources = [var.sns_topic_arn]
  }
}

resource "aws_iam_policy" "sns_access" {
  count  = var.sns_topic_arn == "" ? 0 : 1
  name   = "openai-whisper-stitcher-sns-access"
  policy = data.aws_iam_policy_document.sns_access[0].json
}

resource "aws_iam_role_policy_attachment" "sns_attach" {
  count      = var.sns_topic_arn == "" ? 0 : 1
  role       = aws_iam_role.openai_stitcher_role.name
  policy_arn = aws_iam_policy.sns_access[0].arn
}

# ─────────────────────────────────────────────
# Lambda Function Definition
# ─────────────────────────────────────────────
resource "aws_lambda_function" "openai_stitcher" {
  function_name = "openai-whisper-stitcher"
  role          = aws_iam_role.openai_stitcher_role.arn
  runtime       = "python3.11"
  handler       = "handler.handler"

  filename         = local.function_zip_abs
  source_code_hash = filebase64sha256(local.function_zip_abs)

  timeout     = 900
  memory_size = 1024
  publish     = true

  environment {
    variables = {
      OVERLAP_SECONDS     = "2.0"
      MIN_SEGMENT_SECONDS = "0.3"
      JOB_TABLE_NAME      = var.job_table_name
      SNS_TOPIC_ARN       = var.sns_topic_arn
    }
  }

  tags = local.tags
}

# Async invoke settings (disable retries, limit event age)
resource "aws_lambda_function_event_invoke_config" "stitcher_async" {
  function_name                = aws_lambda_function.openai_stitcher.function_name
  maximum_retry_attempts       = 0
  maximum_event_age_in_seconds = 60
}

# ─────────────────────────────────────────────
# Step Functions Permission (optional)
# ─────────────────────────────────────────────
resource "aws_lambda_permission" "allow_sfn" {
  count         = var.state_machine_arn == "" ? 0 : 1
  statement_id  = "AllowSFNInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.openai_stitcher.function_name
  principal     = "states.amazonaws.com"
  source_arn    = var.state_machine_arn
}
