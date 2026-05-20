#!/usr/bin/env bash
# =============================================================================
# Capstone Project — Phase 4 : OS Update & Upgrade
# File    : scripts/phase4-os-update/os_update.sh
#
# PURPOSE
# -------
# Updates and upgrades the operating system on ALL 5 EC2 instances
# simultaneously via AWS Systems Manager Run Command (tag-based targeting).
#
# This script MUST be deployed via SSM — not manually SSH'd per-server.
# That would violate the Phase 7 "no manual per-server configuration" rule.
#
# WHAT IT DOES
#   1. apt-get update      — refresh package index
#   2. apt-get upgrade     — apply all available upgrades
#   3. apt-get autoremove  — remove obsolete packages
#   4. apt-get autoclean   — clear package cache
#   5. Reboot check        — reports if a reboot is needed
#
# HOW TO DEPLOY (two options — pick one)
#
#   Option A — AWS CLI (recommended, scriptable):
#     aws ssm send-command \
#       --region us-east-2 \
#       --document-name "AWS-RunShellScript" \
#       --targets "Key=tag:Environment,Values=Capstone" \
#       --parameters "commands=$(cat scripts/phase4-os-update/os_update.sh | base64 | tr -d '\n' | xargs -I{} echo 'echo {} | base64 -d | bash')" \
#       --comment "Phase 4 — OS update" \
#       --output text
#
#   Option B — SSM Console:
#     1. SSM → Run Command → AWS-RunShellScript
#     2. Targets: tag Environment=Capstone
#     3. Paste this entire script into the Commands box
#     4. Run
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
fail()    { echo -e "${RED}[FAIL]${RESET}  $*"; exit 1; }

echo ""
echo -e "${BOLD}============================================================${RESET}"
echo -e "${BOLD}  Capstone Phase 4 — OS Update & Upgrade                   ${RESET}"
echo -e "${BOLD}  Host: $(hostname) | Started: $(date '+%Y-%m-%d %H:%M:%S %Z')${RESET}"
echo -e "${BOLD}============================================================${RESET}"
echo ""

# ── Ensure we are running as root (SSM Run Command always does) ───────────────
[[ $EUID -eq 0 ]] || fail "This script must run as root. Deploy via SSM Run Command."

export DEBIAN_FRONTEND=noninteractive

# =============================================================================
# STEP 1 — Refresh Package Index
# =============================================================================
info "Step 1/4 — Refreshing package index (apt-get update)..."

apt-get update -y 2>&1 | tail -5
success "Package index refreshed."

# =============================================================================
# STEP 2 — Apply All Available Upgrades
# =============================================================================
info "Step 2/4 — Applying upgrades (apt-get upgrade)..."

apt-get upgrade -y \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold" \
  2>&1 | tail -10

success "OS packages upgraded."

# =============================================================================
# STEP 3 — Remove Orphaned Packages
# =============================================================================
info "Step 3/4 — Removing orphaned packages (autoremove + autoclean)..."

apt-get autoremove -y >/dev/null 2>&1
apt-get autoclean    >/dev/null 2>&1

success "Orphaned packages removed."

# =============================================================================
# STEP 4 — Reboot Check
# =============================================================================
info "Step 4/4 — Checking if a reboot is required..."

if [[ -f /var/run/reboot-required ]]; then
  warn "REBOOT REQUIRED — schedule a maintenance window reboot for this instance."
  warn "Packages requiring reboot: $(cat /var/run/reboot-required.pkgs 2>/dev/null | tr '\n' ' ')"
else
  success "No reboot required."
fi

echo ""
echo -e "${BOLD}============================================================${RESET}"
success "Phase 4 complete on $(hostname) at $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo -e "${BOLD}============================================================${RESET}"
echo ""
