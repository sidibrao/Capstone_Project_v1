# =============================================================================
# CAPSTONE PROJECT — PHASE 1 & 2 : CORE INFRASTRUCTURE + IAM / SSM
# Module   : 01-IaC
# File     : 01-IaC/main.tf
# Region   : us-east-2  (US East — Ohio)
# Version  : 4.0
#
# ── WHAT THIS FILE OWNS ──────────────────────────────────────────────────────
#
#   PHASE 1 — Network & Compute
#     • VPC                 10.0.0.0/16
#     • Internet Gateway
#     • Public Subnet A     10.0.1.0/24  us-east-2a   (EC2 web fleet)
#     • Public Subnet B     10.0.2.0/24  us-east-2b   (ALB second AZ — no EC2s)
#     • Route Table + associations for BOTH subnets
#     • Security Group      ports 80, 22 inbound | all egress for SSM
#     • 5 × EC2 Ubuntu 20.04 instances
#
#   PHASE 2 — IAM / SSM
#     • IAM Role            EC2-SSM-WebServer-Role
#     • Managed Policy      AmazonSSMManagedInstanceCore
#     • Instance Profile    attached to all 5 EC2s at launch
#
# ── WHY BOTH SUBNETS LIVE HERE ───────────────────────────────────────────────
#
#   HashiCorp best practice: "All foundational / shared network resources
#   belong in one root module. Consumers reference them — they don't own them."
#
#   Subnet B is a networking resource, not an ALB resource. Keeping it here:
#
#   1. CLEAN DESTROY — when `terraform destroy` runs on 02-web-ALB, no subnet
#      deletion is attempted. The ALB is removed cleanly; subnets remain until
#      01-IaC is destroyed. This eliminates the dependency-order destroy error.
#
#   2. SINGLE NETWORK OWNER — one state file owns the entire VPC topology.
#      No cross-stack subnet creation or route table associations.
#
#   3. TAG-BASED LOOKUP — 02-web-ALB finds both subnets using
#      `data "aws_subnet"` filtered by Name tag. It never manages them.
#
# ── OUTPUTS ──────────────────────────────────────────────────────────────────
#
#   vpc_id, subnet_a_id, subnet_b_id, route_table_id,
#   web_sg_id, fleet_instance_ids, fleet_public_ips, ssm_role_arn
#
# ── SAFE DESTROY ORDER ───────────────────────────────────────────────────────
#
#   1.  cd 02-web-ALB  &&  terraform destroy   (ALB, TG, Listener, ALB-SG only)
#   2.  cd 01-IaC      &&  terraform destroy   (EC2s, SGs, IAM, Subnets, VPC)
#   Or:  bash scripts/utils/destroy_all.sh
# =============================================================================

terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # --------------------------------------------------------------------------
  # OPTIONAL — S3 Remote Backend
  # Uncomment AFTER creating the S3 bucket and DynamoDB lock table.
  # Then run: terraform init -reconfigure
  #
  # backend "s3" {
  #   bucket         = "capstone-tf-state-<YOUR-ACCOUNT-ID>"
  #   key            = "capstone/01-IaC/terraform.tfstate"
  #   region         = "us-east-2"
  #   dynamodb_table = "capstone-tf-state-lock"
  #   encrypt        = true
  # }
  # --------------------------------------------------------------------------
}

provider "aws" {
  region = "us-east-2"
}

# =============================================================================
# VARIABLES
# Override with -var="name=value" or a terraform.tfvars file.
# =============================================================================

variable "fleet_size" {
  description = "Number of EC2 web servers (capstone spec = 5)"
  type        = number
  default     = 5
}

variable "instance_type" {
  description = "EC2 instance type for the web fleet"
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "Ubuntu 20.04 LTS AMI ID for us-east-2 (Ohio)"
  type        = string
  default     = "ami-00a9f44477dd83e3d"
}

# =============================================================================
# LOCALS
# Single source of truth for the four required capstone tags.
# Every resource calls merge(local.required_tags, { Name = "...", ... }).
# =============================================================================

locals {
  required_tags = {
    Environment = "Capstone"
    Project     = "LinuxAutomation"
    Role        = "WebServer"
    ManagedBy   = "SSM"
  }
}

# =============================================================================
# PHASE 1 — SECTION 1 : VPC & INTERNET GATEWAY
# =============================================================================

resource "aws_vpc" "capstone_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.required_tags, {
    Name  = "Capstone-VPC"
    Layer = "Networking"
    CIDR  = "10.0.0.0/16"
  })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.capstone_vpc.id

  tags = merge(local.required_tags, {
    Name  = "Capstone-IGW"
    Layer = "Networking"
  })
}

# =============================================================================
# PHASE 1 — SECTION 2 : SUBNETS A & B
#
#   Subnet A  10.0.1.0/24  us-east-2a  ← EC2 web fleet lives here
#   Subnet B  10.0.2.0/24  us-east-2b  ← ALB second AZ (no EC2s)
#
# Both subnets are part of the VPC networking layer. 02-web-ALB reads
# them with data source lookups (by tag) — read-only, no ownership.
# =============================================================================

resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.capstone_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-2a"
  map_public_ip_on_launch = true

  tags = merge(local.required_tags, {
    Name             = "Capstone-Public-Subnet-A"
    Layer            = "Networking"
    AvailabilityZone = "us-east-2a"
    Tier             = "Public"
  })
}

resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.capstone_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-2b"
  map_public_ip_on_launch = true

  tags = merge(local.required_tags, {
    Name             = "Capstone-Public-Subnet-B"
    Layer            = "Networking"
    AvailabilityZone = "us-east-2b"
    Tier             = "Public"
  })
}

# =============================================================================
# PHASE 1 — SECTION 3 : ROUTE TABLE
# One shared public route table associated with BOTH subnets.
# =============================================================================

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.capstone_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(local.required_tags, {
    Name  = "Capstone-Public-RouteTable"
    Layer = "Networking"
  })
}

resource "aws_route_table_association" "public_assoc_a" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_assoc_b" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public_rt.id
}

# =============================================================================
# PHASE 1 — SECTION 4 : SECURITY GROUP
#
# Inbound:  80/tcp (HTTP) | 22/tcp (SSH — lock down CIDR in production)
# Outbound: all — SSM Agent requires outbound 443 to *.amazonaws.com
# =============================================================================

resource "aws_security_group" "web_sg" {
  name        = "capstone-web-sg"
  description = "HTTP + SSH inbound | all egress for SSM Agent"
  vpc_id      = aws_vpc.capstone_vpc.id

  ingress {
    description = "HTTP — Phase 5 required port 80/tcp"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH — restrict to a known CIDR in production environments"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound — required for SSM Agent endpoint communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.required_tags, {
    Name  = "Capstone-Web-SG"
    Layer = "Security"
  })
}

# =============================================================================
# PHASE 2 — IAM ROLE + INSTANCE PROFILE FOR AWS SYSTEMS MANAGER
#
# Role name matches the capstone spec exactly: EC2-SSM-WebServer-Role
#
# AmazonSSMManagedInstanceCore grants each EC2 permission to:
#   • Register with SSM → Fleet Manager → Managed Nodes
#   • Receive SSM Run Command documents  (Phases 4, 5, 6, 7)
#   • Report patch compliance            (Phase 3)
# =============================================================================

resource "aws_iam_role" "ssm_role" {
  name        = "EC2-SSM-WebServer-Role"
  description = "Grants EC2 fleet access to AWS Systems Manager"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Principal = { Service = "ec2.amazonaws.com" }
      }
    ]
  })

  tags = merge(local.required_tags, {
    Name  = "EC2-SSM-WebServer-Role"
    Layer = "IAM"
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "Capstone-EC2-SSM-InstanceProfile"
  role = aws_iam_role.ssm_role.name

  tags = merge(local.required_tags, {
    Name  = "Capstone-EC2-SSM-InstanceProfile"
    Layer = "IAM"
  })
}

# =============================================================================
# PHASE 1 — SECTION 5 : COMPUTE FLEET  (5 web servers — all in Subnet A)
#
# EC2s are placed in Subnet A only.
# Subnet B is intentionally empty — reserved for ALB second AZ.
#
# Tags SSMManaged=true and Patch=enabled power tag-based targeting
# in SSM Run Command and Patch Manager with zero extra configuration.
# =============================================================================

resource "aws_instance" "web_fleet" {
  count = var.fleet_size

  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_subnet_a.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = false
  }

  tags = merge(local.required_tags, {
    Name        = "Capstone-EC2-WebServer-${count.index + 1}"
    ServerIndex = tostring(count.index + 1)
    SSMManaged  = "true"
    Patch       = "enabled"
  })
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.capstone_vpc.id
}

output "subnet_a_id" {
  description = "Subnet A ID (us-east-2a) — EC2 fleet subnet"
  value       = aws_subnet.public_subnet_a.id
}

output "subnet_b_id" {
  description = "Subnet B ID (us-east-2b) — ALB second AZ"
  value       = aws_subnet.public_subnet_b.id
}

output "route_table_id" {
  description = "Public Route Table ID"
  value       = aws_route_table.public_rt.id
}

output "web_sg_id" {
  description = "Web Security Group ID"
  value       = aws_security_group.web_sg.id
}

output "fleet_instance_ids" {
  description = "All 5 EC2 instance IDs"
  value       = aws_instance.web_fleet[*].id
}

output "fleet_public_ips" {
  description = "Map of server name to public IP"
  value       = { for inst in aws_instance.web_fleet : inst.tags["Name"] => inst.public_ip }
}

output "ssm_role_arn" {
  description = "SSM IAM Role ARN — used by Phase 3 maintenance window task"
  value       = aws_iam_role.ssm_role.arn
}
