###############################################################################
# network.tf — Networking for AWS Batch
#
# What this does:
# - Uses the default VPC and its subnets in eu-west-1
# - Defines a security group for Batch instances:
#     - Allows all outbound traffic
#     - No inbound rules (instances don’t need to be reached directly)
###############################################################################

# ── Data sources: Default VPC + subnets ──────────────────────────────────────
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ── Security Group for Batch instances ───────────────────────────────────────
resource "aws_security_group" "batch_instances" {
  name        = "batch-gpu-sg"
  description = "Security group for AWS Batch GPU instances"
  vpc_id      = data.aws_vpc.default.id

  # Allow all outbound traffic (needed for pulling images, S3 access, etc.)
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # No inbound rules — Batch containers don’t need direct external access.

  tags = {
    Name = "batch-gpu-sg"
  }
}
