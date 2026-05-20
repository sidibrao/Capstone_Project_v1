#!/usr/bin/env bash
# =============================================================================
# Capstone Project — Phase 6 : Linux User & Permission Management
# File    : scripts/phase6-users/users_permissions.sh
#
# PURPOSE
# -------
# Creates the cloudadmin user, assigns admin privileges, creates the
# application directory, deploys the HTML status page, and sets correct
# Linux file permissions — on ALL 5 servers simultaneously via SSM.
#
# PHASE 6 REQUIREMENTS (from capstone spec)
#   ✓ Create user: cloudadmin
#   ✓ cloudadmin exists on all servers
#   ✓ cloudadmin has administrative privileges
#   ✓ cloudadmin added to correct Linux admin group (sudo)
#   ✓ Create application path: /var/www/internal-app
#   ✓ Create HTML file displaying hostname, success message, date/time, team name
#   ✓ Configure secure Linux file permissions
#
# HOW TO DEPLOY (two options — pick one)
#
#   Option A — AWS CLI:
#     aws ssm send-command \
#       --region us-east-2 \
#       --document-name "AWS-RunShellScript" \
#       --targets "Key=tag:Environment,Values=Capstone" \
#       --parameters "commands=$(cat scripts/phase6-users/users_permissions.sh | base64 | tr -d '\n' | xargs -I{} echo 'echo {} | base64 -d | bash')" \
#       --comment "Phase 6 — Users and permissions" \
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

HOSTNAME_VAL=$(hostname)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')

echo ""
echo -e "${BOLD}============================================================${RESET}"
echo -e "${BOLD}  Capstone Phase 6 — Users & Permissions                   ${RESET}"
echo -e "${BOLD}  Host: ${HOSTNAME_VAL} | Started: ${TIMESTAMP}${RESET}"
echo -e "${BOLD}============================================================${RESET}"
echo ""

[[ $EUID -eq 0 ]] || fail "Run as root via SSM Run Command."

# =============================================================================
# STEP 1 — Create User: cloudadmin
# =============================================================================
info "Step 1/5 — Creating user 'cloudadmin'..."

if id "cloudadmin" &>/dev/null; then
  warn "User 'cloudadmin' already exists — skipping useradd."
else
  useradd \
    --create-home \
    --shell /bin/bash \
    --comment "Capstone Administrative User" \
    cloudadmin || fail "useradd failed"
  success "User 'cloudadmin' created."
fi

# =============================================================================
# STEP 2 — Grant Administrative Privileges (sudo group)
# =============================================================================
info "Step 2/5 — Adding 'cloudadmin' to sudo group..."

usermod -aG sudo cloudadmin || fail "usermod -aG sudo failed"

# Verify membership
if groups cloudadmin | grep -qw sudo; then
  success "cloudadmin is a member of: $(groups cloudadmin | cut -d: -f2 | xargs)"
else
  fail "cloudadmin was not added to sudo."
fi

# =============================================================================
# STEP 3 — Create Application Directory
# =============================================================================
info "Step 3/5 — Creating /var/www/internal-app..."

mkdir -p /var/www/internal-app || fail "mkdir failed"

success "Directory /var/www/internal-app created."

# =============================================================================
# STEP 4 — Deploy HTML Status Page
# Displays: hostname, success message, date/time, team name
# =============================================================================
info "Step 4/5 — Deploying internal-app HTML status page..."

cat > /var/www/internal-app/index.html << HTMLPAGE
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>Capstone — Internal Application</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      font-family: 'Segoe UI', system-ui, Arial, sans-serif;
      background: #0d1117;
      color: #c9d1d9;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 2rem;
    }

    .card {
      background: #161b22;
      border: 1px solid #30363d;
      border-radius: 16px;
      padding: 2.5rem 3rem;
      max-width: 640px;
      width: 100%;
      box-shadow: 0 16px 48px rgba(0,0,0,0.6);
    }

    .header { display: flex; align-items: center; gap: 1rem; margin-bottom: 2rem; }

    .status-dot {
      width: 14px; height: 14px;
      background: #3fb950;
      border-radius: 50%;
      box-shadow: 0 0 0 4px rgba(63,185,80,0.2);
      animation: pulse 2s infinite;
      flex-shrink: 0;
    }
    @keyframes pulse {
      0%, 100% { box-shadow: 0 0 0 4px rgba(63,185,80,0.2); }
      50%       { box-shadow: 0 0 0 8px rgba(63,185,80,0.05); }
    }

    h1 { font-size: 1.4rem; font-weight: 700; color: #f0f6fc; }
    .subtitle { color: #8b949e; font-size: 0.875rem; margin-top: 0.2rem; }

    .divider { border: none; border-top: 1px solid #21262d; margin: 0 0 1.5rem; }

    .grid { display: grid; gap: 0.6rem; }

    .row {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 0.7rem 1rem;
      background: #0d1117;
      border-radius: 8px;
      border-left: 3px solid #1f6feb;
      gap: 1rem;
    }

    .label {
      font-size: 0.78rem;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.07em;
      color: #8b949e;
      white-space: nowrap;
    }

    .value {
      font-size: 0.9rem;
      color: #e6edf3;
      font-weight: 500;
      text-align: right;
      word-break: break-all;
    }

    .value.green { color: #3fb950; font-weight: 700; }

    .footer {
      margin-top: 1.8rem;
      padding-top: 1.2rem;
      border-top: 1px solid #21262d;
      text-align: center;
      font-size: 0.78rem;
      color: #6e7681;
    }
    .footer span { color: #8b949e; }
  </style>
</head>
<body>
  <div class="card">
    <div class="header">
      <div class="status-dot"></div>
      <div>
        <h1>Internal Application Server</h1>
        <div class="subtitle">AWS SSM + Bash + Linux Fleet Automation — Capstone Project</div>
      </div>
    </div>
    <hr class="divider"/>
    <div class="grid">
      <div class="row">
        <span class="label">Status</span>
        <span class="value green">&#10003; Deployment Successful</span>
      </div>
      <div class="row">
        <span class="label">Hostname</span>
        <span class="value">${HOSTNAME_VAL}</span>
      </div>
      <div class="row">
        <span class="label">Deployed At</span>
        <span class="value">${TIMESTAMP}</span>
      </div>
      <div class="row">
        <span class="label">Environment</span>
        <span class="value">Capstone</span>
      </div>
      <div class="row">
        <span class="label">Project</span>
        <span class="value">LinuxAutomation</span>
      </div>
      <div class="row">
        <span class="label">Managed By</span>
        <span class="value">AWS Systems Manager</span>
      </div>
      <div class="row">
        <span class="label">Team</span>
        <span class="value">Capstone Engineering Team</span>
      </div>
    </div>
    <div class="footer">
      Deployed via <span>SSM Run Command</span> &nbsp;·&nbsp;
      Phase 6 — User &amp; Permission Management &nbsp;·&nbsp;
      <span>Capstone v3.0</span>
    </div>
  </div>
</body>
</html>
HTMLPAGE

# Symlink so Apache default vhost also serves this page
ln -sf /var/www/internal-app/index.html /var/www/html/index.html 2>/dev/null || true

success "HTML status page deployed at /var/www/internal-app/index.html"

# =============================================================================
# STEP 5 — Set Secure Linux File Permissions
#
#   /var/www/internal-app/           cloudadmin:www-data   750
#     drwxr-x---  owner=cloudadmin, group=www-data, others=none
#
#   /var/www/internal-app/index.html cloudadmin:www-data   644
#     -rw-r--r--  owner=cloudadmin, group+others=read only
# =============================================================================
info "Step 5/5 — Setting secure permissions..."

chown -R cloudadmin:www-data /var/www/internal-app || fail "chown failed"
chmod 750                    /var/www/internal-app || fail "chmod dir failed"
chmod 644                    /var/www/internal-app/index.html || fail "chmod file failed"

# Verify
DIR_PERM=$(stat -c "%a" /var/www/internal-app)
FILE_PERM=$(stat -c "%a" /var/www/internal-app/index.html)
DIR_OWNER=$(stat -c "%U:%G" /var/www/internal-app)
FILE_OWNER=$(stat -c "%U:%G" /var/www/internal-app/index.html)

success "Directory:  /var/www/internal-app          → ${DIR_PERM}  (${DIR_OWNER})"
success "HTML file:  /var/www/internal-app/index.html → ${FILE_PERM} (${FILE_OWNER})"

echo ""
echo -e "${BOLD}──────────── Validation ─────────────────────────────────────${RESET}"

# User exists
id cloudadmin &>/dev/null && success "cloudadmin: EXISTS" || fail "cloudadmin: MISSING"

# Sudo membership
groups cloudadmin | grep -qw sudo && success "cloudadmin in sudo: YES" || warn "cloudadmin in sudo: NO"

# Directory exists
[[ -d /var/www/internal-app ]] && success "/var/www/internal-app: EXISTS" || fail "directory MISSING"

# Permissions correct
[[ "$DIR_PERM"  == "750" ]] && success "Dir permissions: 750 (correct)"  || warn "Dir permissions: ${DIR_PERM} (expected 750)"
[[ "$FILE_PERM" == "644" ]] && success "File permissions: 644 (correct)" || warn "File permissions: ${FILE_PERM} (expected 644)"

# Apache can serve the page
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost/ 2>/dev/null || echo "000")
[[ "$HTTP_CODE" == "200" ]] && success "HTTP localhost: 200 OK" || warn "HTTP localhost: ${HTTP_CODE}"

echo ""
echo -e "${BOLD}============================================================${RESET}"
success "Phase 6 complete on ${HOSTNAME_VAL} at $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo -e "${BOLD}============================================================${RESET}"
echo ""
