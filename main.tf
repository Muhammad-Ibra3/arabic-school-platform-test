# ==============================================================================
# Terraform block — project metadata, providers, and state storage
# ==============================================================================
# Every Terraform project starts with a `terraform` block. Think of it as the
# project's manifest: it declares which Terraform version you need, which
# plugins (providers) talk to external APIs, and where Terraform stores its
# state file. The state file is Terraform's inventory of what it created — like
# a live `/etc` for your cloud resources. Without it, Terraform cannot know
# what already exists on the next `terraform apply`. Here we pin the AWS
# provider (the plugin that calls the AWS API) and configure an S3 backend so
# state lives in a shared, encrypted bucket instead of on your laptop.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "gateway2khair-test"
    key          = "ec2/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

# ==============================================================================
# Provider — how Terraform authenticates and talks to AWS
# ==============================================================================
# A provider is the bridge between your `.tf` files and a real API. You already
# know AWS from the CLI (`aws ec2 describe-instances`); the provider does the
# same thing programmatically on your behalf during `plan` and `apply`. The
# `region` setting is like exporting `AWS_DEFAULT_REGION` — all resources in
# this file are created there unless overridden. `default_tags` automatically
# stamps every resource with shared labels, so you do not have to repeat
# `ManagedBy` and `Project` on every block.

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Project   = var.project_name
    }
  }
}

# ==============================================================================
# Variables — inputs you can change without editing the main logic
# ==============================================================================
# Variables are function parameters for your infrastructure code. If you have
# written shell scripts with `$1`, `$2`, or sourced a config file, variables
# serve the same role: they let you reuse one template across environments or
# runs. Set them via defaults (as below), a `terraform.tfvars` file, or
# `-var` on the command line. Terraform validates types at plan time — e.g.
# `tester*_ip` must be a CIDR like `203.0.113.10/32` or left unset (`null`),
# which is Terraform's way of saying "optional / not provided."

variable "aws_region" {
  description = "AWS region to deploy resources in."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming and tags."
  type        = string
  default     = "gateway2khair-test"
}

variable "instance_name" {
  description = "Name tag for the EC2 instance."
  type        = string
  default     = "gateway2khair-test-server"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair in this region. Required for SSH access."
  type        = string
  default     = "ec2-key"
}

variable "ssh_user" {
  description = "Linux login user for SSH (e.g. ec2-user for Amazon Linux, ubuntu for Ubuntu)."
  type        = string
  default     = "ubuntu"
}

variable "tester1_ip" {
  description = "Optional public IP for tester1. Allows inbound SSH (22), HTTP (80), and HTTPS (443) when set. Use CIDR notation, e.g. 203.0.113.10/32."
  type        = string
  default     = null

  validation {
    condition     = var.tester1_ip == null || can(cidrhost(var.tester1_ip, 0))
    error_message = "tester1_ip must be a valid IPv4 CIDR block (e.g. 203.0.113.10/32)."
  }
}

variable "tester2_ip" {
  description = "Optional public IP for tester2. Allows inbound SSH (22), HTTP (80), and HTTPS (443) when set. Use CIDR notation, e.g. 203.0.113.11/32."
  type        = string
  default     = null

  validation {
    condition     = var.tester2_ip == null || can(cidrhost(var.tester2_ip, 0))
    error_message = "tester2_ip must be a valid IPv4 CIDR block (e.g. 203.0.113.11/32)."
  }
}

variable "tester3_ip" {
  description = "Optional public IP for tester3. Allows inbound SSH (22), HTTP (80), and HTTPS (443) when set. Use CIDR notation, e.g. 203.0.113.12/32."
  type        = string
  default     = null

  validation {
    condition     = var.tester3_ip == null || can(cidrhost(var.tester3_ip, 0))
    error_message = "tester3_ip must be a valid IPv4 CIDR block (e.g. 203.0.113.12/32)."
  }
}

# ==============================================================================
# Locals — private constants and derived values inside this configuration
# ==============================================================================
# Locals are like `readonly` variables computed from other values. They are not
# set from outside the project — use them to avoid repeating expressions or to
# build intermediate lists. Here we hard-code the AMI and instance type (you
# might later move these to variables) and build `tester_ips` by filtering out
# any `null` entries with `compact()`, so downstream rules only run for IPs
# that were actually provided.

locals {
  ami_id        = "ami-0b6d9d3d33ba97d99"
  instance_type = "c7i-flex.large"

  # Collect only the tester IPs that were provided.
  tester_ips = compact([
    var.tester1_ip,
    var.tester2_ip,
    var.tester3_ip,
  ])
}

# ==============================================================================
# Data sources — read existing AWS objects without creating or changing them
# ==============================================================================
# Data sources are read-only lookups. In AWS terms, they are like running
# `aws ec2 describe-vpcs` or `aws ec2 describe-images` and using the result in
# your config. Terraform fetches them at plan/apply time and exposes attributes
# (`.id`, `.ids`, etc.) you can reference elsewhere. Unlike `resource` blocks,
# data sources never create or destroy anything — they only observe what already
# exists in your account.

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

data "aws_ami" "selected" {
  owners = ["amazon"]

  filter {
    name   = "image-id"
    values = [local.ami_id]
  }
}

# ==============================================================================
# Security group — firewall rules for the EC2 instance
# ==============================================================================
# A security group is a stateful virtual firewall attached to ENIs/instances.
# This design is deny-by-default for inbound traffic: no ingress is defined on
# the group itself. Separate `aws_vpc_security_group_ingress_rule` resources add
# SSH, HTTP, and HTTPS only for each IP in `local.tester_ips`. The `for_each` loop creates
# one rule per IP automatically — if you add `tester2_ip` in tfvars, Terraform
# plans a new rule without you copying blocks by hand. Egress allows outbound
# HTTP/HTTPS so the instance can run `apt`/`yum` updates and reach AWS APIs.

resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "Secure-by-default SG. SSH/HTTP/HTTPS allowed only from optional tester IPs."
  vpc_id      = data.aws_vpc.default.id

  # No ingress rules defined inline — all ingress is via separate rules below.

  egress {
    description = "Allow outbound HTTPS for package updates and AWS API calls"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound HTTP for package updates"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "tester_http" {
  for_each = toset(local.tester_ips)

  security_group_id = aws_security_group.ec2.id
  description       = "HTTP from tester ${each.value}"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "tester_https" {
  for_each = toset(local.tester_ips)

  security_group_id = aws_security_group.ec2.id
  description       = "HTTPS from tester ${each.value}"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "tester_ssh" {
  for_each = toset(local.tester_ips)

  security_group_id = aws_security_group.ec2.id
  description       = "SSH from tester ${each.value}"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

# ==============================================================================
# EC2 instance — the compute resource this stack provisions
# ==============================================================================
# This block defines the virtual server. References like `data.aws_subnets...`
# and `aws_security_group.ec2.id` wire dependencies automatically — Terraform
# knows to create the security group and look up the subnet before launching
# the instance. `associate_public_ip_address` places the VM on a subnet route
# that can reach the internet (like assigning a public IP in the console).
# `metadata_options` enforces IMDSv2 (token-required), which hardens against
# certain SSRF attacks that try to steal instance role credentials. The root
# volume uses encrypted gp3 storage; `lifecycle { ignore_changes = [ami] }`
# tells Terraform not to replace the instance when the AMI ID drifts — useful
# if AWS publishes newer patch AMIs but you want to control upgrades yourself.

resource "aws_instance" "app" {
  ami                    = local.ami_id
  instance_type          = local.instance_type
  key_name               = var.key_name
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.ec2.id]

  # Required so optional tester IPs can reach SSH/HTTP/HTTPS endpoints.
  associate_public_ip_address = true

  monitoring = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 20

    tags = {
      Name = "${var.instance_name}-root"
    }
  }

  tags = {
    Name = var.instance_name
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

# ==============================================================================
# Outputs — values printed after apply for operators and other tools
# ==============================================================================
# Outputs are return values from your module. After `terraform apply`, Terraform
# prints them so you can copy the instance ID, IPs, or the SSH command
# without digging through the AWS console. Other Terraform configurations can
# also consume outputs via `terraform_remote_state` if you split stacks later.
# Think of outputs as the friendly summary at the end of a deployment script.

output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.app.id
}

output "public_ip" {
  description = "Public IP address of the EC2 instance."
  value       = aws_instance.app.public_ip
}

output "private_ip" {
  description = "Private IP address of the EC2 instance."
  value       = aws_instance.app.private_ip
}

output "security_group_id" {
  description = "Security group attached to the instance."
  value       = aws_security_group.ec2.id
}

output "allowed_tester_ips" {
  description = "Tester IPs currently allowed for SSH/HTTP/HTTPS ingress."
  value       = local.tester_ips
}

output "ssh_connect_command" {
  description = "SSH command to connect to the instance."
  value       = "ssh -i '${var.key_name}' ${var.ssh_user}@${aws_instance.app.public_ip} -y"
}
