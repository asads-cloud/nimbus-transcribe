###############################################################################
# main.tf — AWS Batch: Base Infrastructure
#
# What this does:
# - Sets up Terraform + AWS provider
# - Defines project tags
# - Creates a CloudWatch Log Group for AWS Batch jobs
#
# Notes:
# - Batch jobs using the awslogs driver will write logs here.
# - Retains logs for 14 days by default.
###############################################################################

# ── Terraform + Provider Setup ───────────────────────────────────────────────
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
}

provider "aws" {
  region = var.region
}

# ── Locals ───────────────────────────────────────────────────────────────────
locals {
  project = "nimbus-transcribe"

  # Tags applied to all resources in this module
  tags = merge({
    Project = local.project
    Owner   = "nimbus-transcribe"
  }, var.extra_tags)
}

# ── CloudWatch Log Group ─────────────────────────────────────────────────────
# Used by AWS Batch jobs via awslogs driver.
# Provides centralized logging and retention policy.
resource "aws_cloudwatch_log_group" "batch_jobs" {
  name              = "/aws/batch/job"
  retention_in_days = 14
  tags              = local.tags
}
