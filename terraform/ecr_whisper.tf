###############################################################################
# ECR Repository + Lifecycle Policy for Openai Whisper Faster
#
# This configuration:
# - Creates an Amazon ECR repo with encryption, immutability, and scanning enabled
# - Defines a lifecycle policy to manage image retention
# - Exposes repository URL + ARN as Terraform outputs
###############################################################################
# Terraform + Provider
###############################################################################
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

provider "aws" {
  region = var.region
}



# ─────────────────────────────────────────────────────────────────────────────
# ECR Repository
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_ecr_repository" "openai_whisper_faster" {
  name                 = "openai-whisper-faster"
  image_tag_mutability = "IMMUTABLE" # Prevent overwriting existing tags

  image_scanning_configuration {
    scan_on_push = true # Automatically scan images on push
  }

  encryption_configuration {
    encryption_type = "AES256" # Basic AES256 encryption at rest
  }

  # Keep the repo even if it contains images.
  # If set true, terraform destroy will delete repo + contents.
  force_delete = false
}

# ─────────────────────────────────────────────────────────────────────────────
# Lifecycle Policy
# Keep last 10 tagged images and expire untagged ones after 7 days.
# Helps control storage costs while keeping recent builds.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_ecr_lifecycle_policy" "openai_whisper_faster" {
  repository = aws_ecr_repository.openai_whisper_faster.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "expire untagged after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "keep last 10 images (any tag)"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# Outputs
# Useful for referencing this repo in other modules/pipelines.
# ─────────────────────────────────────────────────────────────────────────────
output "ecr_repository_url" {
  value = aws_ecr_repository.openai_whisper_faster.repository_url
}

output "ecr_repository_arn" {
  value = aws_ecr_repository.openai_whisper_faster.arn
}
