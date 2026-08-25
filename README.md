# AWS SSM Linux Fleet Automation Capstone

Automate deployment, patching, configuration, and validation of a Linux web-server fleet on AWS using Terraform, AWS Systems Manager, Bash, IAM, and an optional Application Load Balancer.

This capstone simulates a real cloud operations project: build infrastructure with Terraform, manage servers without manual SSH, and use AWS-native fleet automation for repeatable operations.

## Business Case

Small cloud teams often start by configuring servers manually. That does not scale and makes patching, access control, and troubleshooting harder. This project demonstrates how to:

- Deploy a repeatable EC2 fleet with Terraform
- Register instances with AWS Systems Manager
- Patch Linux servers centrally
- Run OS updates and application setup at scale
- Manage users and permissions consistently
- Publish web servers behind an Application Load Balancer
- Avoid manual per-instance SSH administration

The result is a practical AWS operations baseline for Linux fleet management.

## Architecture

```text
Internet
   |
Application Load Balancer
   |
Capstone VPC 10.0.0.0/16
   |
+-----------------------------+
| Public Subnet A 10.0.1.0/24 |
| Public Subnet B 10.0.2.0/24 |
+-----------------------------+
   |
EC2 Linux Web Fleet
   |
AWS Systems Manager
Run Command | Patch Manager | Fleet Manager
```

## What This Builds

| Area | Resources |
|---|---|
| Infrastructure | VPC, subnets, route table, internet gateway |
| Compute | Five Linux EC2 web servers |
| IAM | SSM instance role and instance profile |
| Operations | Patch baseline, run command scripts, OS update automation |
| Application | Apache/web server setup and sample content |
| Access | `cloudadmin` user and Linux permissions workflow |
| Load Balancing | Optional public Application Load Balancer |

## Project Phases

| Phase | Tooling | Outcome |
|---|---|---|
| 1 | Terraform | VPC, subnets, EC2 fleet |
| 2 | Terraform | IAM role, instance profile, SSM registration |
| 3 | Terraform + Bash | Patch baseline and patch trigger |
| 4 | Bash + SSM | OS update and upgrade |
| 5 | Bash + SSM | Web server installation and firewall rules |
| 6 | Bash + SSM | User, permissions, and web content |
| 7 | SSM | Tag-based fleet targeting |
| Bonus | Terraform | Application Load Balancer |

## Repository Map

| Path | Purpose |
|---|---|
| `01-IaC/main.tf` | Core VPC, subnet, EC2, IAM, and SSM resources |
| `2-web-ALB/main.tf` | Optional ALB, target group, listener, and security group |
| `scripts/phase3-patch/main.tf` | Patch Manager baseline and maintenance window |
| `patch_now.sh` | On-demand patch command trigger |
| `os_update.sh` | OS update/upgrade through SSM |
| `webserver_setup.sh` | Apache and firewall setup through SSM |
| `users_permissions.sh` | User and permission configuration through SSM |
| `destroy_all.sh` | Ordered teardown helper |
| `Project Requirments/` | Original project requirement document |

## Prerequisites

- AWS account with permissions for EC2, VPC, IAM, SSM, and ELB
- AWS CLI configured for `us-east-2`
- Terraform installed
- Git installed
- EC2 instances able to reach SSM endpoints or the internet

Recommended AWS profile check:

```bash
aws sts get-caller-identity
```

## Quick Start

Deploy core infrastructure:

```bash
cd 01-IaC
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Run operational scripts from the repo root after instances are online and visible in Systems Manager:

```bash
./patch_now.sh
./os_update.sh
./webserver_setup.sh
./users_permissions.sh
```

Deploy the optional ALB:

```bash
cd 2-web-ALB
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

## Validation

Confirm SSM-managed instances:

```bash
aws ssm describe-instance-information --region us-east-2
```

Confirm EC2 instances:

```bash
aws ec2 describe-instances \
  --region us-east-2 \
  --query 'Reservations[].Instances[].{Id:InstanceId,State:State.Name,Name:Tags[?Key==`Name`].Value|[0]}' \
  --output table
```

Confirm web access through the ALB output or instance public IPs.

## Security Notes

- Do not commit AWS access keys or downloaded credential CSV files.
- Prefer IAM roles and Systems Manager over direct SSH.
- Use least-privilege IAM policies for Terraform and SSM automation.
- Restrict security group ingress to required ports and trusted sources.
- Use tags for SSM fleet targeting and lifecycle ownership.
- Destroy unused lab resources to avoid cost.

## Cleanup

Use the ordered helper from the repo root:

```bash
./destroy_all.sh
```

Or destroy each Terraform phase intentionally:

```bash
cd 2-web-ALB
terraform destroy

cd ../01-IaC
terraform destroy
```

## Cost Notice

This lab creates billable AWS resources, including EC2 instances, EBS volumes, public IP usage, and optionally an Application Load Balancer. Destroy the lab when testing is complete.
