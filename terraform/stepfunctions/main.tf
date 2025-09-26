###############################################################################
# main.tf — AWS Provider setup for Step Functions module
#
# What this does:
# - Pins Terraform + AWS provider versions
# - Configures the AWS provider using a region variable
#
# Notes:
# - Keep provider version in sync with other modules to avoid drift.
###############################################################################

# ── Terraform + Provider Requirements ────────────────────────────────────────
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.55"
    }
  }
}

# ── AWS Provider ─────────────────────────────────────────────────────────────
# Uses var.region
provider "aws" {
  region = var.region
}
