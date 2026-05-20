#!/usr/bin/env bash
# =============================================================================
# Capstone Project — Phase 3 : On-Demand Patch Script
# File    : scripts/phase3-patch/patch_now.sh
#
# PURPOSE
# -------
# Triggers an IMMEDIATE patch scan-and-install on all 5 EC2 instances
# using SSM Run Command + AWS-RunPatchBaseline, without waiting for the
# scheduled maintenance window defined in main.tf.
#
# Use this for:
#   • Emergency patch runs outside the weekly schedule
#   • Validating that patching works before the first maintenance window
#   • Capstone project demonstration / deliverable evidence
#
# USAGE
#   chmod +x scripts/phase3-patch/patch_now.sh
#   ./scripts/phase3-patch/patch_now.sh
#
# PREREQUISITES
#   • AWS CLI v2 installed and configured (aws configure)
#   • IAM permissions: ssm:SendCommand, ssm:GetCommandInvocation
#   • EC2 instances are running and visible in SSM Fleet Manager
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
fail()    { echo -e "${RED}[FAIL]${RESET}  $*" >&2; exit 1; }

REGION="us-east-2"
TAG_KEY="tag:Environment"
TAG_VAL="Capstone"

echo ""
echo -e "${BOLD}=====================================================${RESET}"
echo -e "${BOLD}  Capstone Phase 3 — On-Demand Patch Run             ${RESET}"
echo -e "${BOLD}=====================================================${RESET}"
echo ""

# ── Verify AWS CLI is available ───────────────────────────────────────────────
command -v aws &>/dev/null || fail "AWS CLI not found. Install from https://aws.amazon.com/cli/"

# ── Confirm caller identity ───────────────────────────────────────────────────
info "Verifying AWS credentials..."
aws sts get-caller-identity --region "$REGION" --output table
echo ""

# ── Send patch command (tag-based — hits all 5 servers simultaneously) ─────────
info "Sending AWS-RunPatchBaseline (Install) to all instances tagged ${TAG_KEY}=${TAG_VAL}..."

COMMAND_ID=$(aws ssm send-command \
  --region "$REGION" \
  --document-name "AWS-RunPatchBaseline" \
  --targets "Key=${TAG_KEY},Values=${TAG_VAL}" \
  --parameters "Operation=Install,RebootOption=RebootIfNeeded" \
  --comment "Capstone Phase 3 — on-demand patch run" \
  --timeout-seconds 3600 \
  --output text \
  --query "Command.CommandId")

success "Command dispatched. Command ID: ${BOLD}${COMMAND_ID}${RESET}"
echo ""

# ── Poll for completion ───────────────────────────────────────────────────────
info "Waiting for patch command to complete (this takes 5–15 minutes)..."
info "Polling every 30 seconds. Press Ctrl+C to stop polling (patching continues in AWS)."
echo ""

POLL_INTERVAL=30
MAX_POLLS=40  # 20 minutes max polling
POLL_COUNT=0

while true; do
  POLL_COUNT=$((POLL_COUNT + 1))
  if [[ $POLL_COUNT -gt $MAX_POLLS ]]; then
    warn "Polling timeout reached. Check status manually:"
    warn "  aws ssm list-command-invocations --command-id ${COMMAND_ID} --region ${REGION} --details"
    break
  fi

  STATUS=$(aws ssm list-commands \
    --command-id "$COMMAND_ID" \
    --region "$REGION" \
    --query "Commands[0].StatusDetails" \
    --output text 2>/dev/null || echo "Pending")

  echo -e "  [$(date '+%H:%M:%S')]  Status: ${BOLD}${STATUS}${RESET}"

  case "$STATUS" in
    "Success")
      echo ""
      success "All instances patched successfully!"
      break
      ;;
    "Failed"|"Cancelled"|"TimedOut")
      echo ""
      fail "Patch command ended with status: ${STATUS}. Check SSM Run Command console for details."
      ;;
    *)
      sleep "$POLL_INTERVAL"
      ;;
  esac
done

echo ""

# ── Show per-instance results ─────────────────────────────────────────────────
info "Per-instance patch results:"
aws ssm list-command-invocations \
  --command-id "$COMMAND_ID" \
  --region "$REGION" \
  --details \
  --query "CommandInvocations[*].{InstanceId:InstanceId,Status:StatusDetails}" \
  --output table

echo ""

# ── Show compliance summary ───────────────────────────────────────────────────
info "Compliance summary (may take 2-3 min to update after patching):"
aws ssm list-compliance-summaries \
  --filters "Key=ComplianceType,Values=Patch" \
  --region "$REGION" \
  --output table 2>/dev/null || warn "Compliance data not yet available — check SSM Patch Manager console."

echo ""
echo -e "${BOLD}=====================================================${RESET}"
success "Phase 3 patch run complete."
echo -e "${BOLD}=====================================================${RESET}"
echo ""
info "Next steps:"
info "  1. Open SSM → Patch Manager → Compliance reporting"
info "  2. Verify all 5 instances show 'Compliant'"
info "  3. Screenshot this as your Phase 3 deliverable"
echo ""
