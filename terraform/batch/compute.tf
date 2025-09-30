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

###############################################################################
# compute.tf — AWS Batch Compute Environment (GPU) with larger root EBS
###############################################################################

###############################################################################
# compute.tf — AWS Batch Compute Environment (GPU) + Launch Template (200 GiB)
###############################################################################

# ── Local values ─────────────────────────────────────────────────────────────
locals {
  compute_env_name_old = "openai-whisper-gpu-env"      # old CE
  compute_env_name_new = "openai-whisper-gpu-env-v2"   # new CE (with larger disk)
}

# ── AMI for ECS + NVIDIA ─────────────────────────────────────────────────────
# Batch uses this AMI family; LT still needs an ImageId.
data "aws_ssm_parameter" "ecs_al2_gpu_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/gpu/recommended/image_id"
}

# ── Launch Template with larger root EBS ─────────────────────────────────────
resource "aws_launch_template" "whisper_gpu_lt" {
  name_prefix = "whisper-gpu-"
  image_id    = data.aws_ssm_parameter.ecs_al2_gpu_ami.value

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 200      # <-- root disk size (GiB)
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }
}

# ── OLD Compute Environment ──────────────────────────────────

resource "aws_batch_compute_environment" "gpu_env" {
  compute_environment_name = local.compute_env_name_old
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
    max_vcpus     = 32

    # GPU-enabled EC2 instance type
    instance_type = ["g5.xlarge"]      # <-- plural

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

# ── NEW Compute Environment ──────────────────────────────────
resource "aws_batch_compute_environment" "gpu_env_v2" {
  compute_environment_name = local.compute_env_name_new
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

    # Auto-scaling range
    min_vcpus     = 0
    desired_vcpus = 0
    max_vcpus     = 32

    instance_type = ["g5.xlarge"]

    subnets            = data.aws_subnets.default.ids
    security_group_ids = [aws_security_group.batch_instances.id]

    ec2_configuration { image_type = "ECS_AL2_NVIDIA" }

    launch_template {
      launch_template_id = aws_launch_template.whisper_gpu_lt.id
      version            = "$Latest"
    }

    instance_role = aws_iam_instance_profile.ecs_instance_profile.arn
  }
}
