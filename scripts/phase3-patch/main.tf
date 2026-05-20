# =============================================================================
# CAPSTONE PROJECT — PHASE 3 : PATCH MANAGEMENT (Terraform)
# Module   : scripts/phase3-patch
# File     : scripts/phase3-patch/main.tf
# Region   : us-east-2
# Version  : 3.0
#
# ── WHAT THIS FILE OWNS ──────────────────────────────────────────────────────
#
#   • Custom SSM Patch Baseline  (Ubuntu — CriticalUpdates + SecurityUpdates)
#   • Patch Group registration   (links tag Patch=enabled to the baseline)
#   • SSM Maintenance Window     (runs every Sunday at 02:00 UTC, 2-hr window)
#   • Maintenance Window Target  (tag-based: Environment=Capstone)
#   • Maintenance Window Task    (AWS-RunPatchBaseline — Install mode)
#
# ── WHY TERRAFORM FOR PHASE 3 ────────────────────────────────────────────────
#
#   Defining patching in Terraform means:
#   • The patch policy is version-controlled alongside the infrastructure
#   • Re-deployments always restore the exact same baseline + schedule
#   • No manual console clicks are needed for a new environment stand-up
#
# ── ALTERNATIVE (console / bash) ─────────────────────────────────────────────
#
#   If you prefer a one-shot on-demand patch, use the companion script:
#     scripts/phase3-patch/patch_now.sh
#   That script uses the AWS CLI to trigger patching immediately without
#   waiting for the maintenance window schedule.
#
# ── PREREQUISITES ────────────────────────────────────────────────────────────
#
#   Run AFTER 01-IaC has been applied.  This module reads the 01-IaC
#   state to find the SSM Role ARN required by the maintenance window task.
#
# ── DEPLOY ───────────────────────────────────────────────────────────────────
#
#   cd scripts/phase3-patch
#   terraform init
#   terraform plan
#   terraform apply
# =============================================================================

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

# ── Read 01-IaC state for the SSM role ARN ────────────────────────────────────
data "terraform_remote_state" "infra" {
  backend = "local"
  config = {
    path = "../../01-IaC/terraform.tfstate"
  }
  # S3 backend variant (when remote backend is enabled):
  # backend = "s3"
  # config = {
  #   bucket = "capstone-tf-state-<YOUR-ACCOUNT-ID>"
  #   key    = "capstone/01-IaC/terraform.tfstate"
  #   region = "us-east-2"
  # }
}

locals {
  required_tags = {
    Environment = "Capstone"
    Project     = "LinuxAutomation"
    Role        = "WebServer"
    ManagedBy   = "SSM"
  }
}

# =============================================================================
# SECTION 1 — CUSTOM PATCH BASELINE
# Targets Ubuntu (DEBIAN) OS.  Approves Critical + Security patches
# automatically after a 7-day delay to allow vendor testing to settle.
# =============================================================================

resource "aws_ssm_patch_baseline" "capstone_baseline" {
  name             = "Capstone-Ubuntu-PatchBaseline"
  description      = "Capstone patch baseline — Ubuntu Critical + Security (7-day auto-approval)"
  operating_system = "UBUNTU"

  # Auto-approve Critical and Security patches after 7 days
  approval_rule {
    approve_after_days  = 7
    enable_non_security = false

    patch_filter {
      key    = "PRIORITY"
      values = ["Critical", "High", "Medium"]
    }
  }

  tags = merge(local.required_tags, {
    Name  = "Capstone-Ubuntu-PatchBaseline"
    Layer = "PatchManagement"
  })
}

# =============================================================================
# SECTION 2 — PATCH GROUP
# Links the tag "Patch=enabled" on every EC2 to this baseline.
# Instances tagged Patch=enabled will be patched by this baseline automatically.
# =============================================================================

resource "aws_ssm_patch_group" "capstone_patch_group" {
  baseline_id = aws_ssm_patch_baseline.capstone_baseline.id
  patch_group = "enabled" # matches tag Patch=enabled on EC2 instances
}

# =============================================================================
# SECTION 3 — MAINTENANCE WINDOW
# Every Sunday at 02:00 UTC — 2-hour window — max 5 concurrent targets.
# =============================================================================

resource "aws_ssm_maintenance_window" "capstone_mw" {
  name              = "Capstone-Sunday-PatchWindow"
  description       = "Weekly patching window for the Capstone web fleet"
  schedule          = "cron(0 2 ? * SUN *)" # every Sunday 02:00 UTC
  duration          = 2                      # hours
  cutoff            = 1                      # stop registering new tasks 1 hr before end
  allow_unassociated_targets = false

  tags = merge(local.required_tags, {
    Name  = "Capstone-Sunday-PatchWindow"
    Layer = "PatchManagement"
  })
}

# =============================================================================
# SECTION 4 — MAINTENANCE WINDOW TARGET
# Tag-based: targets all instances where Environment=Capstone
# =============================================================================

resource "aws_ssm_maintenance_window_target" "capstone_mw_target" {
  window_id     = aws_ssm_maintenance_window.capstone_mw.id
  name          = "Capstone-Fleet-Target"
  description   = "All EC2 instances tagged Environment=Capstone"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:Environment"
    values = ["Capstone"]
  }
}

# =============================================================================
# SECTION 5 — MAINTENANCE WINDOW TASK
# Runs AWS-RunPatchBaseline (Install mode) against the target group above.
# The IAM Role ARN comes from 01-IaC remote state — no hardcoding.
# =============================================================================

resource "aws_ssm_maintenance_window_task" "capstone_patch_task" {
  window_id        = aws_ssm_maintenance_window.capstone_mw.id
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  priority         = 1
  service_role_arn = data.terraform_remote_state.infra.outputs.ssm_role_arn
  max_concurrency  = "5"   # patch all 5 servers in parallel
  max_errors       = "1"   # abort window if more than 1 failure

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.capstone_mw_target.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      comment              = "Capstone weekly patch — Install mode"
      timeout_seconds      = 3600

      parameter {
        name   = "Operation"
        values = ["Install"]
      }

      parameter {
        name   = "RebootOption"
        values = ["RebootIfNeeded"]
      }
    }
  }
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "patch_baseline_id" {
  description = "Custom patch baseline ID"
  value       = aws_ssm_patch_baseline.capstone_baseline.id
}

output "maintenance_window_id" {
  description = "Maintenance Window ID — view in SSM → Maintenance Windows"
  value       = aws_ssm_maintenance_window.capstone_mw.id
}
