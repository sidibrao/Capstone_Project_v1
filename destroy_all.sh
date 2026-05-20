#!/usr/bin/env bash
# =============================================================================
# Capstone Project — Safe Teardown Script
# File    : scripts/utils/destroy_all.sh
# Version : 4.0
#
# PURPOSE
# -------
# Destroys BOTH Terraform stacks in the correct dependency order, preventing
# AWS API errors caused by removing core infrastructure while the ALB layer
# still holds active references to the VPC and EC2 instances.
#
# ── ARCHITECTURE NOTE ────────────────────────────────────────────────────────
#
#   Both Subnet A and Subnet B are owned by 01-IaC (not 02-web-ALB).
#   The 02-web-ALB module looks up subnets READ-ONLY via data source tag
#   filters — it never creates or destroys any subnet.
#
#   This means:
#     • terraform destroy on 02-web-ALB only removes:
#         ALB, Target Group, HTTP Listener, ALB Security Group
#     • terraform destroy on 01-IaC then removes:
#         EC2 fleet, Web-SG, IAM role/profile,
#         Subnet A, Subnet B, Route Table associations,
#         Route Table, Internet Gateway, VPC
#
#   Running 01-IaC destroy BEFORE 02-web-ALB would leave the ALB in a broken
#   state and generate AWS dependency errors. This script enforces the correct
#   order every time.
#
# ── DESTROY ORDER ────────────────────────────────────────────────────────────
#
#   Step 1 → 02-web-ALB   ALB · Target Group · Listener · ALB-SG
#   Step 2 → 01-IaC       EC2s · SGs · IAM · Subnets A+B · RT · IGW · VPC
#
# ── USAGE ────────────────────────────────────────────────────────────────────
#
#   Run from the repository root (folder containing 01-IaC/ and 02-web-ALB/):
#
#   chmod +x scripts/utils/destroy_all.sh
#   ./scripts/utils/destroy_all.sh                  # prompts for confirmation
#   ./scripts/utils/destroy_all.sh --auto-approve   # CI/CD non-interactive
#
# ── PREREQUISITES ────────────────────────────────────────────────────────────
#
#   • Terraform >= 1.3.0 on PATH
#   • AWS CLI configured with EC2, VPC, IAM, and ELB destroy permissions
#   • Run from the repository root
# =============================================================================

set -euo pipefail

# ── Colour helpers ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

# ── Parse flags ────────────────────────────────────────────────────────────────
AUTO_APPROVE=""
for arg in "$@"; do
  [[ "$arg" == "--auto-approve" ]] && AUTO_APPROVE="-auto-approve"
done

# ── Verify we are in the repo root ─────────────────────────────────────────────
if [[ ! -d "01-IaC" || ! -d "02-web-ALB" ]]; then
  error "Run from the repository root — must contain 01-IaC/ and 02-web-ALB/."
  exit 1
fi

# ── Verify Terraform is on PATH ────────────────────────────────────────────────
if ! command -v terraform &>/dev/null; then
  error "Terraform not found. Install: https://developer.hashicorp.com/terraform/downloads"
  exit 1
fi

# ── Verify AWS credentials ─────────────────────────────────────────────────────
if ! aws sts get-caller-identity --region us-east-2 &>/dev/null; then
  error "AWS credentials not configured or invalid. Run: aws configure"
  exit 1
fi

# ── Banner ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}   Capstone Project — Full Infrastructure Teardown      ${RESET}"
echo -e "${BOLD}════════════════════════════════════════════════════════${RESET}"
echo ""
warn "This will PERMANENTLY DESTROY all Capstone AWS resources."
warn "AWS charges will stop after teardown is complete."
echo ""

CALLER=$(aws sts get-caller-identity --region us-east-2 --query "Arn" --output text 2>/dev/null || echo "unknown")
info "Authenticated as: ${BOLD}${CALLER}${RESET}"
info "Target region:    us-east-2 (Ohio)"
echo ""

# ── Confirmation ───────────────────────────────────────────────────────────────
if [[ -z "$AUTO_APPROVE" ]]; then
  read -rp "$(echo -e "${YELLOW}Type 'yes' to confirm full teardown: ${RESET}")" CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    info "Teardown aborted by user. No resources were changed."
    exit 0
  fi
fi

echo ""
START_TIME=$(date +%s)

# ── Helper: destroy one stack ──────────────────────────────────────────────────
destroy_stack() {
  local dir="$1"
  local label="$2"
  local description="$3"

  echo -e "${BOLD}────────────────────────────────────────────────────────${RESET}"
  info "Destroying: ${BOLD}${label}${RESET}"
  info "Resources:  ${description}"
  echo -e "${BOLD}────────────────────────────────────────────────────────${RESET}"

  pushd "$dir" > /dev/null

  terraform init -input=false -reconfigure > /dev/null 2>&1 || {
    warn "terraform init had warnings — continuing with destroy."
  }

  if terraform destroy -input=false $AUTO_APPROVE; then
    success "${label} destroyed successfully."
  else
    error "${label} destroy FAILED. Review the output above before retrying."
    popd > /dev/null
    exit 1
  fi

  popd > /dev/null
  echo ""
}

# ── STEP 1 — ALB layer first (owns no subnets — clean destroy) ─────────────────
destroy_stack \
  "02-web-ALB" \
  "02-web-ALB  (ALB Layer)" \
  "ALB · Target Group · HTTP Listener · ALB Security Group"

# ── STEP 2 — Core infrastructure (owns both subnets, VPC, EC2s) ───────────────
destroy_stack \
  "01-IaC" \
  "01-IaC     (Core Infrastructure Layer)" \
  "EC2 fleet · Web-SG · IAM · Subnet A · Subnet B · Route Table · IGW · VPC"

# ── Summary ────────────────────────────────────────────────────────────────────
ELAPSED=$(( $(date +%s) - START_TIME ))
MINS=$(( ELAPSED / 60 ))
SECS=$(( ELAPSED % 60 ))

echo -e "${BOLD}════════════════════════════════════════════════════════${RESET}"
success "All Capstone infrastructure destroyed in ${MINS}m ${SECS}s."
echo -e "${BOLD}════════════════════════════════════════════════════════${RESET}"
echo ""
info "Post-teardown verification — check the AWS Console (us-east-2):"
info "  EC2  → Instances       all 5 servers show 'terminated'"
info "  VPC  → Your VPCs       Capstone-VPC is absent"
info "  VPC  → Subnets         Subnet A and Subnet B are absent"
info "  EC2  → Load Balancers  capstone-application-lb is absent"
info "  IAM  → Roles           EC2-SSM-WebServer-Role is absent"
info "  SSM  → Fleet Manager   no managed nodes remain"
echo ""
