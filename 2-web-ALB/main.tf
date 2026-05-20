# =============================================================================
# CAPSTONE PROJECT — BONUS : APPLICATION LOAD BALANCER
# Module   : 02-web-ALB
# File     : 02-web-ALB/main.tf
# Region   : us-east-2  (US East — Ohio)
# Version  : 4.0
#
# ── WHAT THIS FILE OWNS ──────────────────────────────────────────────────────
#
#   BONUS — ALB layer only
#     • ALB Security Group        (ports 80 + 443 inbound)
#     • Application Load Balancer (internet-facing, multi-AZ)
#     • Target Group              (HTTP, port 80, health check on /)
#     • HTTP Listener             (port 80 → forward to target group)
#     • Target Group Attachments  (all 5 EC2 instances)
#
# ── WHAT THIS FILE DOES NOT OWN ──────────────────────────────────────────────
#
#   Subnet A and Subnet B are owned by 01-IaC.
#   This module looks them up READ-ONLY using data sources keyed on Name tags.
#   It never creates, modifies, or destroys any subnet or route table.
#
# ── CROSS-STACK LOOKUP STRATEGY (Terraform best practice) ───────────────────
#
#   HashiCorp recommendation for sharing network resources across independent
#   root modules: use DATA SOURCES filtered by tags rather than
#   terraform_remote_state. Reasons:
#
#   1. NO STATE COUPLING — this module works even if 01-IaC uses a different
#      backend (local vs S3). The lookup goes to the AWS API directly.
#
#   2. CLEAN DESTROY — `terraform destroy` on this module removes only what
#      this module created (ALB, TG, Listener, ALB-SG). The subnets are
#      never in this module's state, so AWS never attempts to delete them
#      here — eliminating the destroy dependency error entirely.
#
#   3. IDEMPOTENT — re-running plan/apply after a partial failure always
#      resolves to the correct live state without manual state surgery.
#
#   Data sources used:
#     data "aws_vpc"     — looks up VPC by tag Name=Capstone-VPC
#     data "aws_subnet"  — looks up Subnet A by tag Name=Capstone-Public-Subnet-A
#     data "aws_subnet"  — looks up Subnet B by tag Name=Capstone-Public-Subnet-B
#     data "aws_instances" — looks up all 5 EC2s by tag Environment=Capstone
#
# ── PREREQUISITE ─────────────────────────────────────────────────────────────
#
#   01-IaC must be fully applied before running this module.
#   The data sources will fail if the tagged resources do not yet exist.
#
# ── DEPLOY ───────────────────────────────────────────────────────────────────
#
#   cd 02-web-ALB
#   terraform init
#   terraform plan
#   terraform apply
#   terraform output alb_dns_name
#
# ── SAFE DESTROY ORDER ───────────────────────────────────────────────────────
#
#   1.  cd 02-web-ALB  &&  terraform destroy   ← this module first (ALB only)
#   2.  cd 01-IaC      &&  terraform destroy   ← then subnets, EC2s, VPC
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
  #   key            = "capstone/02-web-ALB/terraform.tfstate"
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
# LOCALS
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
# SECTION 1 — DATA SOURCE LOOKUPS  (read-only — no resources created here)
#
# All network resources are owned by 01-IaC and looked up by tag.
# Terraform never attempts to create or destroy these objects from this module.
# =============================================================================

# Look up the VPC by its Name tag
data "aws_vpc" "capstone" {
  filter {
    name   = "tag:Name"
    values = ["Capstone-VPC"]
  }
}

# Look up Subnet A (us-east-2a) by its Name tag
data "aws_subnet" "subnet_a" {
  filter {
    name   = "tag:Name"
    values = ["Capstone-Public-Subnet-A"]
  }
}

# Look up Subnet B (us-east-2b) by its Name tag
data "aws_subnet" "subnet_b" {
  filter {
    name   = "tag:Name"
    values = ["Capstone-Public-Subnet-B"]
  }
}

# Look up all 5 EC2 instances by the Environment=Capstone tag
# Returns a list of instance IDs used for target group attachment
data "aws_instances" "web_fleet" {
  filter {
    name   = "tag:Environment"
    values = ["Capstone"]
  }

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

# =============================================================================
# SECTION 2 — ALB SECURITY GROUP
#
# Owned by this module — distinct from the EC2 security group in 01-IaC.
# Port 443 is pre-opened for a future ACM certificate / HTTPS listener.
# =============================================================================

resource "aws_security_group" "alb_sg" {
  name        = "capstone-alb-sg"
  description = "Public HTTP (80) and HTTPS (443) inbound to the ALB"
  vpc_id      = data.aws_vpc.capstone.id

  ingress {
    description = "HTTP — internet traffic to ALB"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS — attach ACM certificate to HTTPS listener to activate"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound — ALB to EC2 health checks and forwarded traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.required_tags, {
    Name  = "Capstone-ALB-SG"
    Layer = "Security"
  })
}

# =============================================================================
# SECTION 3 — APPLICATION LOAD BALANCER
#
# Internet-facing, spanning both AZs:
#   Subnet A (us-east-2a) — looked up from data source above
#   Subnet B (us-east-2b) — looked up from data source above
#
# Neither subnet is created or destroyed by this module.
# =============================================================================

resource "aws_lb" "capstone_alb" {
  name               = "capstone-application-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]

  subnets = [
    data.aws_subnet.subnet_a.id, # Subnet A — owned by 01-IaC, looked up by tag
    data.aws_subnet.subnet_b.id, # Subnet B — owned by 01-IaC, looked up by tag
  ]

  enable_deletion_protection = false

  tags = merge(local.required_tags, {
    Name  = "Capstone-ALB"
    Layer = "LoadBalancing"
  })
}

# =============================================================================
# SECTION 4 — TARGET GROUP + HEALTH CHECK
# =============================================================================

resource "aws_lb_target_group" "web_tg" {
  name        = "capstone-web-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.capstone.id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200"
  }

  tags = merge(local.required_tags, {
    Name  = "Capstone-Web-TargetGroup"
    Layer = "LoadBalancing"
  })
}

# =============================================================================
# SECTION 5 — HTTP LISTENER
# =============================================================================

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.capstone_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }

  tags = merge(local.required_tags, {
    Name  = "Capstone-ALB-HTTP-Listener"
    Layer = "LoadBalancing"
  })
}

# =============================================================================
# SECTION 6 — TARGET GROUP ATTACHMENT
#
# Registers all EC2 instances (returned by the aws_instances data source)
# into the target group. Using the data source rather than hardcoded IDs
# means this automatically picks up the correct instances after any redeploy
# of 01-IaC without needing to update this file.
# =============================================================================

resource "aws_lb_target_group_attachment" "fleet_attach" {
  count = length(data.aws_instances.web_fleet.ids)

  target_group_arn = aws_lb_target_group.web_tg.arn
  target_id        = data.aws_instances.web_fleet.ids[count.index]
  port             = 80
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "alb_dns_name" {
  description = "Paste into a browser — each refresh routes to a different server"
  value       = aws_lb.capstone_alb.dns_name
}

output "alb_arn" {
  description = "ALB ARN — use to attach WAF or an HTTPS listener with ACM"
  value       = aws_lb.capstone_alb.arn
}

output "target_group_arn" {
  description = "Target Group ARN — for CloudWatch alarms or manual registration"
  value       = aws_lb_target_group.web_tg.arn
}

output "registered_instance_ids" {
  description = "EC2 instance IDs registered in the target group"
  value       = data.aws_instances.web_fleet.ids
}
