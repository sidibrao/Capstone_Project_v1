# Capstone Project — AWS SSM · Bash · Linux Fleet Automation

> **Role:** Cloud Systems Engineer  
> **Region:** AWS us-east-2 (Ohio)  
> **Stack:** Terraform · AWS EC2 · IAM · Systems Manager · ALB · Bash  
> **Version:** 4.0

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [Repository Structure](#3-repository-structure)
4. [Prerequisites](#4-prerequisites)
   - [4.1 AWS Account & IAM User](#41-aws-account--iam-user)
   - [4.2 Configure AWS CLI in VS Code](#42-configure-aws-cli-in-vs-code)
   - [4.3 Install Terraform](#43-install-terraform)
   - [4.4 Install Git](#44-install-git)
5. [Resource Tag Reference](#5-resource-tag-reference)
6. [Phase 1 — Core Infrastructure (Terraform)](#6-phase-1--core-infrastructure-terraform)
7. [Phase 2 — IAM & SSM (Terraform)](#7-phase-2--iam--ssm-terraform)
8. [Phase 3 — Patch Management (Terraform + Bash)](#8-phase-3--patch-management-terraform--bash)
9. [Phase 4 — OS Update & Upgrade (Bash / SSM)](#9-phase-4--os-update--upgrade-bash--ssm)
10. [Phase 5 — Web Server Setup (Bash / SSM)](#10-phase-5--web-server-setup-bash--ssm)
11. [Phase 6 — Users & Permissions (Bash / SSM)](#11-phase-6--users--permissions-bash--ssm)
12. [Phase 7 — SSM Run Command at Scale](#12-phase-7--ssm-run-command-at-scale)
13. [Bonus — Application Load Balancer (Terraform)](#13-bonus--application-load-balancer-terraform)
14. [Cross-Stack Design & Subnet Ownership](#14-cross-stack-design--subnet-ownership)
15. [Validation & Testing](#15-validation--testing)
16. [Safe Destroy Guide](#16-safe-destroy-guide)
17. [Push to GitHub](#17-push-to-github)
18. [Challenges & Solutions](#18-challenges--solutions)

---

## 1. Project Overview

This capstone simulates a real-world Cloud/DevOps engineering scenario. The goal is to **fully automate** the deployment, configuration, patching, and management of a fleet of five Linux web servers using AWS-native tooling — with zero manual per-server SSH configuration.

**Core constraint:** All server configuration goes through **AWS Systems Manager Run Command** using tag-based targeting. Manually SSH-ing into servers individually is not permitted.

**Tool assignment by phase:**

| Phase | Tool | Description |
|---|---|---|
| Phase 1 | **Terraform** | VPC, both subnets, EC2 fleet |
| Phase 2 | **Terraform** | IAM Role, Instance Profile, SSM registration |
| Phase 3 | **Terraform + Bash** | Patch Baseline (TF), on-demand trigger (bash) |
| Phase 4 | **Bash / SSM** | OS update and upgrade |
| Phase 5 | **Bash / SSM** | Apache installation and firewall |
| Phase 6 | **Bash / SSM** | cloudadmin user, directory, HTML page, permissions |
| Phase 7 | **SSM** | Tag-based fleet targeting rule |
| Bonus | **Terraform** | Application Load Balancer |

---

## 2. Architecture

```
                          Internet
                             │
                    ┌────────▼────────┐
                    │ Internet Gateway │  ← owned by 01-IaC
                    └────────┬────────┘
                             │
               ┌─────────────▼──────────────┐
               │         Capstone VPC        │  ← owned by 01-IaC
               │         10.0.0.0/16         │
               │                             │
               │   ┌─────────────────────┐   │
               │   │  Application Load   │   │  ← owned by 02-web-ALB
               │   │  Balancer (ALB)     │   │
               │   │  capstone-alb-sg    │   │
               │   └──────┬──────┬───────┘   │
               │          │      │            │
               │  ┌───────▼──┐ ┌─▼────────┐  │
               │  │ Subnet A │ │ Subnet B │  │  ← BOTH owned by 01-IaC
               │  │10.0.1.0  │ │10.0.2.0  │  │  02-web-ALB reads by tag
               │  │/24       │ │/24       │  │
               │  │us-east-2a│ │us-east-2b│  │
               │  └────┬─────┘ └──────────┘  │
               │       │  (ALB AZ only)       │
               │  ┌────▼─────────────────┐   │
               │  │  Target Group        │   │
               │  │  EC2-1 · EC2-2       │   │
               │  │  EC2-3 · EC2-4       │   │
               │  │  EC2-5               │   │
               │  └──────────────────────┘   │
               └─────────────────────────────┘
                             │
                AWS Systems Manager (SSM)
            Fleet Manager · Run Command · Patch Manager
```

---

## 3. Repository Structure

```
Capstone_Project_v2/
│
├── 01-IaC/
│   └── main.tf                        # Phase 1+2: VPC, Subnet A, Subnet B,
│                                      #   EC2 fleet, IAM/SSM Role
│
├── 02-web-ALB/
│   └── main.tf                        # Bonus: ALB, ALB-SG, Target Group,
│                                      #   Listener — reads subnets by tag
│
├── scripts/
│   ├── phase3-patch/
│   │   ├── main.tf                    # Patch Baseline + Maintenance Window (TF)
│   │   └── patch_now.sh               # On-demand patch trigger (bash)
│   │
│   ├── phase4-os-update/
│   │   └── os_update.sh               # apt update + upgrade via SSM
│   │
│   ├── phase5-webserver/
│   │   └── webserver_setup.sh         # Apache + UFW ports 80/443 via SSM
│   │
│   ├── phase6-users/
│   │   └── users_permissions.sh       # cloudadmin + HTML page via SSM
│   │
│   └── utils/
│       └── destroy_all.sh             # Safe ordered teardown script
│
└── README.md
```

---

## 4. Prerequisites

### 4.1 AWS Account & IAM User

You need an active AWS account and a dedicated IAM user with programmatic access.

---

#### Step 1 — Sign in to the AWS Console

Go to [https://console.aws.amazon.com](https://console.aws.amazon.com) and sign in.

---

#### Step 2 — Open IAM

Search `IAM` in the top bar → **Users** → **Create user**.

---

#### Step 3 — Create the IAM User

| Field | Value |
|---|---|
| User name | `capstone-terraform-user` |
| Console access | Optional (not needed for CLI-only) |

Click **Next**.

---

#### Step 4 — Attach Permissions

Select **Attach policies directly** and check each policy:

| Policy | Purpose |
|---|---|
| `AmazonEC2FullAccess` | EC2 instances, security groups |
| `AmazonVPCFullAccess` | VPC, subnets, route tables, IGW |
| `IAMFullAccess` | IAM roles and instance profiles |
| `ElasticLoadBalancingFullAccess` | Application Load Balancer |
| `AmazonSSMFullAccess` | Fleet Manager, Run Command, Patch Manager |
| `AmazonS3FullAccess` | *(Optional)* Remote Terraform state backend |

Click **Next** → **Create user**.

---

#### Step 5 — Create Access Keys

1. Click `capstone-terraform-user` → **Security credentials** tab
2. Scroll to **Access keys** → **Create access key**
3. Select **Command Line Interface (CLI)** → confirm → **Create access key**
4. ⚠️ **Download the `.csv` file immediately** — the secret key is shown only once
5. **Never commit this file to any repository**

---

### 4.2 Configure AWS CLI in VS Code

#### Step 1 — Install the AWS CLI

**Windows:**
```powershell
# Download: https://awscli.amazonaws.com/AWSCLIV2.msi
# Run the installer, then open a new terminal and verify:
aws --version
```

**macOS:**
```bash
brew install awscli
aws --version
```

**Linux (Ubuntu/Debian):**
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version
```

---

#### Step 2 — Install AWS Toolkit in VS Code

1. Open VS Code → press `Ctrl+Shift+X`
2. Search **AWS Toolkit** → install the extension by **Amazon Web Services**
3. Click the **AWS icon** in the left activity bar after installing

---

#### Step 3 — Configure Credentials

Open the VS Code integrated terminal (`Ctrl+`` `):

```bash
aws configure
```

Enter when prompted:

```
AWS Access Key ID:       <from the downloaded .csv>
AWS Secret Access Key:   <from the downloaded .csv>
Default region name:     us-east-2
Default output format:   json
```

---

#### Step 4 — Verify the Connection

```bash
aws sts get-caller-identity
```

Expected:
```json
{
    "UserId": "AIDA...",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/capstone-terraform-user"
}
```

---

#### Step 5 — Connect AWS Toolkit in VS Code

1. Click the **AWS icon** in the sidebar
2. **Connect to AWS** → **Use a profile from credentials file** → **default**
3. Your account and region appear in the AWS Explorer panel

---

### 4.3 Install Terraform

**Windows (Chocolatey):**
```powershell
choco install terraform
terraform -version
```

**macOS:**
```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
terraform -version
```

**Linux (Ubuntu/Debian):**
```bash
wget -O- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt update && sudo apt install terraform -y
terraform -version
```

Minimum required: **Terraform >= 1.3.0**

---

### 4.4 Install Git

**Windows:** [https://git-scm.com/download/win](https://git-scm.com/download/win)

**macOS:**
```bash
brew install git
```

**Linux:**
```bash
sudo apt install git -y
```

**Configure your identity:**
```bash
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
```

---

## 5. Resource Tag Reference

All resources carry the four required capstone tags via `merge(local.required_tags, {...})`.

### Required Tags (applied to every resource)

| Tag Key | Tag Value |
|---|---|
| `Environment` | `Capstone` |
| `Project` | `LinuxAutomation` |
| `Role` | `WebServer` |
| `ManagedBy` | `SSM` |

### Per-Resource Tag Summary

| Resource | Name Tag | Additional Tags |
|---|---|---|
| VPC | `Capstone-VPC` | `Layer=Networking`, `CIDR=10.0.0.0/16` |
| Internet Gateway | `Capstone-IGW` | `Layer=Networking` |
| **Subnet A** | `Capstone-Public-Subnet-A` | `Layer=Networking`, `AvailabilityZone=us-east-2a`, `Tier=Public` |
| **Subnet B** | `Capstone-Public-Subnet-B` | `Layer=Networking`, `AvailabilityZone=us-east-2b`, `Tier=Public` |
| Route Table | `Capstone-Public-RouteTable` | `Layer=Networking` |
| EC2 Security Group | `Capstone-Web-SG` | `Layer=Security` |
| ALB Security Group | `Capstone-ALB-SG` | `Layer=Security` |
| IAM Role | `EC2-SSM-WebServer-Role` | `Layer=IAM` |
| IAM Instance Profile | `Capstone-EC2-SSM-InstanceProfile` | `Layer=IAM` |
| EC2 Servers 1–5 | `Capstone-EC2-WebServer-1…5` | `SSMManaged=true`, `Patch=enabled`, `ServerIndex=1–5` |
| ALB | `Capstone-ALB` | `Layer=LoadBalancing` |
| Target Group | `Capstone-Web-TargetGroup` | `Layer=LoadBalancing` |
| ALB Listener | `Capstone-ALB-HTTP-Listener` | `Layer=LoadBalancing` |
| Patch Baseline | `Capstone-Ubuntu-PatchBaseline` | `Layer=PatchManagement` |
| Maintenance Window | `Capstone-Sunday-PatchWindow` | `Layer=PatchManagement` |

> **Both Subnet A and Subnet B are owned by `01-IaC`.** The `02-web-ALB` module looks them up read-only via `data "aws_subnet"` filtered by Name tag — it never creates, modifies, or destroys them.

---

## 6. Phase 1 — Core Infrastructure (Terraform)

**File:** `01-IaC/main.tf`

Provisions the complete network and compute layer including **both subnets**:

| Resource | Detail |
|---|---|
| VPC | `10.0.0.0/16`, DNS hostnames enabled |
| Internet Gateway | Attached to VPC |
| Subnet A | `10.0.1.0/24`, `us-east-2a`, EC2 fleet |
| Subnet B | `10.0.2.0/24`, `us-east-2b`, ALB second AZ (no EC2s) |
| Route Table | `0.0.0.0/0 → IGW`, associated with Subnet A **and** Subnet B |
| Security Group | `80/tcp`, `22/tcp` inbound; all egress |
| 5 × EC2 | Ubuntu 20.04, `t3.micro`, 20 GB gp3, all in Subnet A |

**Deploy:**
```bash
cd 01-IaC
terraform init
terraform plan
terraform apply
```

**Verify:**
```bash
terraform output fleet_public_ips
terraform output subnet_a_id
terraform output subnet_b_id
```

---

## 7. Phase 2 — IAM & SSM (Terraform)

**File:** `01-IaC/main.tf` (same apply as Phase 1)

| Resource | Name |
|---|---|
| IAM Role | `EC2-SSM-WebServer-Role` |
| Managed Policy | `AmazonSSMManagedInstanceCore` |
| Instance Profile | `Capstone-EC2-SSM-InstanceProfile` |

The instance profile is attached to all 5 EC2s at launch. No console steps required.

**Verify SSM registration (2–3 min after apply):**
```bash
aws ssm describe-instance-information \
  --filters "Key=tag:Environment,Values=Capstone" \
  --region us-east-2 \
  --query "InstanceInformationList[*].{ID:InstanceId,Status:PingStatus}" \
  --output table
```

All 5 should show `PingStatus: Online`.

---

## 8. Phase 3 — Patch Management (Terraform + Bash)

**Terraform:** `scripts/phase3-patch/main.tf`  
**Bash:** `scripts/phase3-patch/patch_now.sh`

### Deploy the Terraform patch configuration
```bash
cd scripts/phase3-patch
terraform init
terraform plan
terraform apply
```

Creates: Custom Ubuntu Patch Baseline (Critical/High/Medium, 7-day approval) · Patch Group (tag `Patch=enabled`) · Maintenance Window (Sunday 02:00 UTC) · Window Target (`Environment=Capstone`) · Window Task (`AWS-RunPatchBaseline`, Install mode, 5 parallel).

### Trigger immediate on-demand patching
```bash
chmod +x scripts/phase3-patch/patch_now.sh
./scripts/phase3-patch/patch_now.sh
```

### Verify compliance
```bash
aws ssm list-compliance-summaries \
  --filters "Key=ComplianceType,Values=Patch" \
  --region us-east-2 --output table
```

---

## 9. Phase 4 — OS Update & Upgrade (Bash / SSM)

**File:** `scripts/phase4-os-update/os_update.sh`

Runs `apt-get update`, `apt-get upgrade`, `autoremove`, `autoclean` and checks for reboot requirement on all 5 servers simultaneously.

**Deploy via SSM Console:**
1. **Systems Manager → Run Command → AWS-RunShellScript**
2. Targets → **Specify instance tags** → `Environment = Capstone`
3. Commands → paste `scripts/phase4-os-update/os_update.sh`
4. **Run**

**Or via AWS CLI:**
```bash
aws ssm send-command \
  --region us-east-2 \
  --document-name "AWS-RunShellScript" \
  --targets "Key=tag:Environment,Values=Capstone" \
  --parameters commands=["$(cat scripts/phase4-os-update/os_update.sh)"] \
  --comment "Phase 4 — OS update" \
  --output table
```

---

## 10. Phase 5 — Web Server Setup (Bash / SSM)

**File:** `scripts/phase5-webserver/webserver_setup.sh`

Installs Apache2, starts and enables it on boot, opens UFW ports 80 and 443 on all 5 servers simultaneously.

**Deploy via SSM Console:**
1. **Systems Manager → Run Command → AWS-RunShellScript**
2. Targets → `Environment = Capstone`
3. Commands → paste `scripts/phase5-webserver/webserver_setup.sh`
4. **Run**

**Or via AWS CLI:**
```bash
aws ssm send-command \
  --region us-east-2 \
  --document-name "AWS-RunShellScript" \
  --targets "Key=tag:Environment,Values=Capstone" \
  --parameters commands=["$(cat scripts/phase5-webserver/webserver_setup.sh)"] \
  --comment "Phase 5 — Apache setup" \
  --output table
```

---

## 11. Phase 6 — Users & Permissions (Bash / SSM)

**File:** `scripts/phase6-users/users_permissions.sh`

Creates user `cloudadmin`, adds to `sudo`, creates `/var/www/internal-app/`, deploys the styled HTML status page, and sets secure permissions — on all 5 servers simultaneously.

| Item | Detail |
|---|---|
| User | `cloudadmin`, `/bin/bash` shell |
| Group | `sudo` |
| Directory | `/var/www/internal-app/` — `750`, owner `cloudadmin:www-data` |
| HTML file | `/var/www/internal-app/index.html` — `644` |
| Page content | Hostname, timestamp, environment, project, team name |

**Deploy via SSM Console:**
1. **Systems Manager → Run Command → AWS-RunShellScript**
2. Targets → `Environment = Capstone`
3. Commands → paste `scripts/phase6-users/users_permissions.sh`
4. **Run**

---

## 12. Phase 7 — SSM Run Command at Scale

> All server configuration must use SSM Run Command with tag-based targeting. No manual per-server SSH is permitted.

The flag `--targets "Key=tag:Environment,Values=Capstone"` in every CLI command above is how this is enforced — all 5 servers receive commands in parallel from a single call.

**Check results across all instances:**
```bash
aws ssm list-command-invocations \
  --filters "key=DocumentName,value=AWS-RunShellScript" \
  --region us-east-2 \
  --details \
  --query "CommandInvocations[*].{Instance:InstanceId,Status:StatusDetails}" \
  --output table
```

---

## 13. Bonus — Application Load Balancer (Terraform)

**File:** `02-web-ALB/main.tf`

This module owns only the ALB layer. It discovers the network resources from `01-IaC` using tag-based data source lookups — it does not create or manage any subnets.

| Resource | Owned by |
|---|---|
| Subnet A | `01-IaC` (looked up by `02-web-ALB` via tag) |
| Subnet B | `01-IaC` (looked up by `02-web-ALB` via tag) |
| ALB Security Group | `02-web-ALB` |
| Application Load Balancer | `02-web-ALB` |
| Target Group | `02-web-ALB` |
| HTTP Listener | `02-web-ALB` |

**Deploy (01-IaC must be applied first):**
```bash
cd 02-web-ALB
terraform init
terraform plan
terraform apply
terraform output alb_dns_name
```

Paste the DNS name into a browser — each refresh routes to a different server (hostname visible in the HTML page).

---

## 14. Cross-Stack Design & Subnet Ownership

### Design decision: why Subnet B lives in `01-IaC`

**Previous approach (v3.0):** Subnet B was created inside `02-web-ALB`. This caused destroy errors because when `terraform destroy` ran against `02-web-ALB`, Terraform attempted to delete Subnet B while the ALB (still being destroyed in the same run) was still referencing it — producing an AWS API dependency violation.

**Current approach (v4.0):** Both subnets are owned by `01-IaC`. The `02-web-ALB` module never touches subnets — it only reads them.

### How `02-web-ALB` finds the subnets

Instead of `terraform_remote_state`, the ALB module uses **tag-based data source lookups** — the HashiCorp-recommended pattern for sharing resources across independent root modules:

```hcl
# In 02-web-ALB/main.tf — READ ONLY, no ownership

data "aws_vpc" "capstone" {
  filter {
    name   = "tag:Name"
    values = ["Capstone-VPC"]
  }
}

data "aws_subnet" "subnet_a" {
  filter {
    name   = "tag:Name"
    values = ["Capstone-Public-Subnet-A"]
  }
}

data "aws_subnet" "subnet_b" {
  filter {
    name   = "tag:Name"
    values = ["Capstone-Public-Subnet-B"]
  }
}

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
```

### Why this is better than `terraform_remote_state`

| Aspect | `terraform_remote_state` | Tag-based data sources (v4.0) |
|---|---|---|
| State coupling | Both modules must use the same backend type | None — reads directly from AWS API |
| Destroy safety | ALB module state contains subnet references | ALB module state has NO subnet resources |
| After redeploy of 01-IaC | May need `terraform refresh` to update IDs | Automatically resolves to live IDs on next plan |
| Backend portability | Must update both modules if switching backends | No change needed in 02-web-ALB |

### Clean destroy flow (v4.0)

```
terraform destroy (02-web-ALB)
  → destroys: ALB, ALB-SG, Target Group, Listener
  → data sources: removed from plan (read-only, nothing to delete)
  → subnets: NOT in this module's state → AWS never asked to delete them ✓

terraform destroy (01-IaC)
  → destroys: EC2 fleet, Subnet A, Subnet B, Route Table, VPC, IGW, IAM
  → ALB is already gone → no dependency violations ✓
```

---

## 15. Validation & Testing

```bash
# ── Phase 2: All 5 servers registered in SSM ──────────────────────────────
aws ssm describe-instance-information \
  --filters "Key=tag:Environment,Values=Capstone" \
  --region us-east-2 \
  --query "InstanceInformationList[*].{ID:InstanceId,Status:PingStatus,OS:PlatformName}" \
  --output table

# ── Phase 3: Patch compliance ─────────────────────────────────────────────
aws ssm list-compliance-summaries \
  --filters "Key=ComplianceType,Values=Patch" \
  --region us-east-2 --output table

# ── Phase 5: Apache active on all servers ────────────────────────────────
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "Key=tag:Environment,Values=Capstone" \
  --parameters 'commands=["systemctl is-active apache2 && ss -tlnp | grep :80"]' \
  --region us-east-2 --output text

# ── Phase 6: cloudadmin + directory + permissions ────────────────────────
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "Key=tag:Environment,Values=Capstone" \
  --parameters 'commands=["id cloudadmin && stat -c \"%a %U:%G\" /var/www/internal-app /var/www/internal-app/index.html"]' \
  --region us-east-2 --output text

# ── Phase 6: HTTP response ────────────────────────────────────────────────
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "Key=tag:Environment,Values=Capstone" \
  --parameters 'commands=["curl -s -o /dev/null -w \"%{http_code} $(hostname)\" http://localhost/"]' \
  --region us-east-2 --output text

# ── Bonus: ALB round-robin verification ──────────────────────────────────
ALB_DNS=$(cd 02-web-ALB && terraform output -raw alb_dns_name)
for i in 1 2 3 4 5; do
  curl -s http://$ALB_DNS/ | grep -o "Hostname.*</div>" || true
  sleep 1
done
```

---

## 16. Safe Destroy Guide

> ⚠️ Always destroy `02-web-ALB` **before** `01-IaC`. The ALB references Subnet A and Subnet B — if the subnets are deleted first, AWS returns a dependency error.

**Option A — Automated script (recommended):**
```bash
chmod +x scripts/utils/destroy_all.sh
./scripts/utils/destroy_all.sh
```

**Option B — Manual:**
```bash
# Step 1 — remove the ALB layer first
cd 02-web-ALB
terraform destroy

# Step 2 — remove core infrastructure (subnets, VPC, EC2s)
cd ../01-IaC
terraform destroy
```

**What each destroy removes:**

| Stack | Resources destroyed |
|---|---|
| `02-web-ALB` | ALB, ALB-SG, Target Group, HTTP Listener |
| `01-IaC` | EC2 × 5, Subnet A, Subnet B, Route Table, VPC, IGW, IAM Role, Instance Profile, Web-SG |

**Post-destroy checks in AWS Console (us-east-2):**

| Service | Expected |
|---|---|
| EC2 → Instances | All 5 show `terminated` |
| VPC → Your VPCs | `Capstone-VPC` absent |
| EC2 → Load Balancers | `capstone-application-lb` absent |
| IAM → Roles | `EC2-SSM-WebServer-Role` absent |
| SSM → Fleet Manager | No managed nodes |

---

## 17. Push to GitHub

### Step 1 — Create a GitHub Repository

1. Go to [https://github.com/new](https://github.com/new)
2. Set:
   - **Repository name:** `capstone-aws-ssm-linux`
   - **Description:** `AWS SSM · Bash · Linux Fleet Automation — Capstone Project v4.0`
   - **Visibility:** Public or Private
3. Do **not** initialise with README, `.gitignore`, or licence
4. Click **Create repository** and copy the HTTPS URL

---

### Step 2 — Initialise Git Locally

```bash
cd /path/to/Capstone_Project_v2
git init
git branch -M main
```

---

### Step 3 — Create .gitignore

```bash
cat > .gitignore << 'EOF'
# Terraform state — never commit
*.tfstate
*.tfstate.backup
*.tfstate.lock.info
.terraform/
.terraform.lock.hcl
terraform.tfvars
override.tf
override.tf.json

# AWS credentials — never commit
.aws/
*.pem
*.csv

# OS / editor
.DS_Store
Thumbs.db
.vscode/
*.swp
EOF
```

---

### Step 4 — Stage and Commit

```bash
git add .
git status    # confirm no .tfstate or .csv files are staged

git commit -m "feat: Capstone v4.0 — Subnet B moved to 01-IaC, tag-based ALB lookups

Architecture change (v4.0):
- Both Subnet A and Subnet B now owned by 01-IaC (foundational network layer)
- 02-web-ALB uses tag-based data sources (aws_subnet, aws_vpc, aws_instances)
  instead of terraform_remote_state — eliminates state coupling and destroy errors
- destroy_all.sh updated to reflect new ownership model
- README updated: Section 14 documents the full cross-stack design decision

Files:
- 01-IaC/main.tf           : Subnet B added, route table assoc for both subnets
- 02-web-ALB/main.tf       : Subnet resource removed, replaced with data sources
- scripts/utils/destroy_all.sh : Updated destroy order comments
- README.md                : Full rewrite of sections 3, 6, 13, 14, 16"
```

---

### Step 5 — Add Remote and Push

```bash
git remote add origin https://github.com/<your-username>/capstone-aws-ssm-linux.git
git push -u origin main
```

When prompted for a password, use a **Personal Access Token**:
1. GitHub → **Settings → Developer settings → Personal access tokens → Tokens (classic)**
2. **Generate new token (classic)** → scope: `repo` → **Generate token**
3. Copy and paste it as your password

---

### Step 6 — Verify

Open `https://github.com/<your-username>/capstone-aws-ssm-linux` — all folders and the README should be visible.

**Future updates:**
```bash
git add .
git commit -m "fix: <description>"
git push
```

---

## 18. Challenges & Solutions

| Challenge | Root Cause | Solution in v4.0 |
|---|---|---|
| Destroy error: subnet dependency violation | Subnet B was owned by `02-web-ALB` — deleted while ALB still referenced it | Moved Subnet B to `01-IaC`. `02-web-ALB` no longer owns any subnets |
| Subnet A conflict on `terraform plan` | Hardcoded subnet ID in `02-web-ALB` not recognised as managed by `01-IaC` | Replaced with `data "aws_subnet"` lookup by Name tag |
| State coupling between modules | `terraform_remote_state` requires both modules to share the same backend type | Switched to tag-based data sources — reads from AWS API, no state dependency |
| After redeploy of `01-IaC`, ALB plan shows ID drift | Hardcoded or remote-state IDs become stale after EC2/subnet recreation | Tag-based data sources always resolve to live IDs on next `terraform plan` |
| EC2s not appearing in SSM Fleet Manager | Missing IAM instance profile at launch | `EC2-SSM-WebServer-Role` with `AmazonSSMManagedInstanceCore` attached in Terraform at instance creation |
| Inconsistent tags across resources | Tags defined individually per resource | Centralised `locals.required_tags` block merged into every resource |
| Manual server config violating Phase 7 | Per-server SSH temptation | All bash scripts deployed via SSM Run Command with `tag:Environment=Capstone` |

---

*Capstone Project v4.0 — AWS SSM · Bash · Linux Fleet Automation*
