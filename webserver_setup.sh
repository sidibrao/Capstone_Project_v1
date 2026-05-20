#!/usr/bin/env bash
# =============================================================================
# Capstone Project — Phase 5 : Web Server Installation & Configuration
# File    : scripts/phase5-webserver/webserver_setup.sh
#
# PURPOSE
# -------
# Installs, starts, and enables Apache on all 5 EC2 instances simultaneously
# via AWS Systems Manager Run Command (tag-based targeting).
#
# PHASE 5 REQUIREMENTS (from capstone spec)
#   ✓ Install Apache
#   ✓ Ensure service starts automatically on boot
#   ✓ Verify service is running
#   ✓ Configure access for HTTP (80/tcp) and HTTPS (443/tcp)
#
# HOW TO DEPLOY (two options — pick one)
#
#   Option A — AWS CLI:
#     aws ssm send-command \
#       --region us-east-2 \
#       --document-name "AWS-RunShellScript" \
#       --targets "Key=tag:Environment,Values=Capstone" \
#       --parameters "commands=$(cat scripts/phase5-webserver/webserver_setup.sh | base64 | tr -d '\n' | xargs -I{} echo 'echo {} | base64 -d | bash')" \
#       --comment "Phase 5 — Apache setup" \
#       --output text
#
#   Option B — SSM Console:
#     SSM → Run Command → AWS-RunShellScript → tag Environment=Capstone
#     Paste this script → Run
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
echo -e "${BOLD}  Capstone Phase 5 — Web Server Setup                      ${RESET}"
echo -e "${BOLD}  Host: $(hostname) | Started: $(date '+%Y-%m-%d %H:%M:%S %Z')${RESET}"
echo -e "${BOLD}============================================================${RESET}"
echo ""

[[ $EUID -eq 0 ]] || fail "Run as root via SSM Run Command."

export DEBIAN_FRONTEND=noninteractive

# =============================================================================
# STEP 1 — Install Apache2
# =============================================================================
info "Step 1/5 — Installing Apache2..."

apt-get update -y >/dev/null 2>&1
apt-get install -y apache2 >/dev/null 2>&1 || fail "Apache installation failed"

success "Apache2 installed. Version: $(apache2 -v 2>&1 | head -1)"

# =============================================================================
# STEP 2 — Start Apache
# =============================================================================
info "Step 2/5 — Starting Apache service..."

systemctl start apache2 || fail "Failed to start Apache"

success "Apache service started."

# =============================================================================
# STEP 3 — Enable Apache on Boot
# =============================================================================
info "Step 3/5 — Enabling Apache to start on boot..."

systemctl enable apache2 || fail "Failed to enable Apache"

success "Apache enabled on boot."

# =============================================================================
# STEP 4 — Configure Firewall (ports 80 and 443)
# The EC2 Security Group already allows these ports from outside AWS.
# UFW is the host-level firewall inside the OS.
# =============================================================================
info "Step 4/5 — Configuring UFW firewall for ports 80/tcp and 443/tcp..."

# Check if ufw is installed
if command -v ufw &>/dev/null; then
  ufw --force enable   >/dev/null 2>&1 || warn "ufw enable returned non-zero"
  ufw allow 80/tcp     >/dev/null 2>&1
  ufw allow 443/tcp    >/dev/null 2>&1
  ufw reload           >/dev/null 2>&1 || true
  success "UFW rules applied: 80/tcp and 443/tcp open."
else
  warn "ufw not found — using iptables fallback"
  iptables -I INPUT -p tcp --dport 80  -j ACCEPT
  iptables -I INPUT -p tcp --dport 443 -j ACCEPT
  success "iptables rules applied: 80/tcp and 443/tcp open."
fi

# =============================================================================
# STEP 5 — Verify Service is Running
# =============================================================================
info "Step 5/5 — Verifying Apache is running..."

if systemctl is-active --quiet apache2; then
  success "Apache service: ACTIVE"
else
  fail "Apache service is NOT running after setup."
fi

if systemctl is-enabled --quiet apache2; then
  success "Apache on-boot: ENABLED"
else
  warn "Apache is not enabled on boot — check systemd output."
fi

# Port check
if ss -tlnp 2>/dev/null | grep -q ':80 '; then
  success "Port 80/tcp: LISTENING"
else
  warn "Port 80/tcp not detected in ss output (Apache may still be starting)"
fi

# HTTP response check
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost/ 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
  success "HTTP response: 200 OK — Apache serving traffic"
else
  warn "HTTP response code: ${HTTP_CODE} (expected 200 — check Apache error log)"
fi

echo ""
echo -e "${BOLD}============================================================${RESET}"
success "Phase 5 complete on $(hostname) at $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo -e "${BOLD}============================================================${RESET}"
echo ""
