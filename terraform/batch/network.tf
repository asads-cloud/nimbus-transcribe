###############################################################################
# network.tf — Networking for AWS Batch
#
# What this does:
# - Uses the default VPC and its subnets in eu-west-1
# - Defines a security group for Batch instances:
#     - Allows all outbound traffic
#     - No inbound rules (instances don’t need to be reached directly)
###############################################################################

# ── Default VPC + all subnets ────────────────────────────────────────────────
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Pull details (AZ) for each subnet so we can pick one per AZ
data "aws_subnet" "details" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.key
}

# Route tables in this VPC (for the S3 Gateway endpoint)
data "aws_route_tables" "for_vpc" {
  vpc_id = data.aws_vpc.default.id
}

# Choose up to 3 subnets in DISTINCT AZs (guarantee multi-AZ spread)
locals {
  subnet_details      = [for s in values(data.aws_subnet.details) : { id = s.id, az = s.availability_zone }]
  azs                 = distinct([for s in local.subnet_details : s.az])
  first_subnet_per_az = [for az in local.azs : (tolist([for s in local.subnet_details : s.id if s.az == az]))[0]]
  batch_subnet_ids    = slice(local.first_subnet_per_az, 0, 3) # pick 2–3 AZs
}

# ── Security Group for Batch instances ───────────────────────────────────────
resource "aws_security_group" "batch_instances" {
  name        = "batch-gpu-sg"
  description = "Security group for AWS Batch GPU instances"
  vpc_id      = data.aws_vpc.default.id

  # Outbound to anywhere (ECR/S3/image pulls etc.)
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = { Name = "batch-gpu-sg" }
}

# ── Security Group for VPC Interface Endpoints (allow HTTPS from Batch nodes)
resource "aws_security_group" "vpce" {
  name        = "batch-vpc-endpoints-sg"
  description = "Allow HTTPS from Batch instances to VPC interface endpoints"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "HTTPS from Batch instances"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.batch_instances.id]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "batch-vpce-sg" }
}

# ── VPC Endpoints (speed up first image pulls) ───────────────────────────────
# ECR API (Interface)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = local.batch_subnet_ids
  security_group_ids  = [aws_security_group.vpce.id]
  tags                = { Name = "vpce-ecr-api" }
}

# ECR DKR (Interface)
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = local.batch_subnet_ids
  security_group_ids  = [aws_security_group.vpce.id]
  tags                = { Name = "vpce-ecr-dkr" }
}

# S3 (Gateway)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = data.aws_vpc.default.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = data.aws_route_tables.for_vpc.ids
  tags              = { Name = "vpce-s3" }
}
