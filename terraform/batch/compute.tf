###############################################################################
# compute.tf — AWS Batch Compute Environment
#
# What this does:
# - Creates a managed AWS Batch compute environment for GPU workloads
# - Uses EC2 instances (g5.xlarge) with NVIDIA GPU support
# - Connects to default VPC subnets + a security group for egress
#
# Notes:
# - Uses BEST_FIT_PROGRESSIVE allocation (gradually expands pool)
# - Scales between 0 and 16 vCPUs
# - Must reference *instance profile* ARN for EC2 hosts
###############################################################################

# ── Local values ─────────────────────────────────────────────────────────────
locals {
  compute_env_name = "openai-whisper-gpu-env"
}

# ── Compute Environment ──────────────────────────────────────────────────────
resource "aws_batch_compute_environment" "gpu_env" {
  compute_environment_name = local.compute_env_name
  type                     = "MANAGED"
  state                    = "ENABLED"
  service_role             = aws_iam_role.batch_service.arn

  tags = {
    Project = "nimbus-transcribe"
    Phase   = "3-aws-batch-gpu"
  }

  compute_resources {
    type                = "EC2"
    allocation_strategy = "BEST_FIT_PROGRESSIVE"

    # Auto-scaling range (vCPUs)
    min_vcpus     = 0
    desired_vcpus = 0
    max_vcpus     = 16

    # GPU-enabled EC2 instance type
    instance_type = ["g5.xlarge"]

    # Networking
    subnets            = data.aws_subnets.default.ids
    security_group_ids = [aws_security_group.batch_instances.id]

    # Ensure ECS AMI with NVIDIA GPU drivers
    ec2_configuration {
      image_type = "ECS_AL2_NVIDIA"
    }

    # Must use the *instance profile* ARN (not just the role ARN)
    instance_role = aws_iam_instance_profile.ecs_instance_profile.arn
  }
}
