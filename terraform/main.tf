terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }

  }
}

provider "aws" {
  region = var.aws_region
}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  name_prefix = "${var.project_name}-${var.student_name}"
}

# -----------------------------
# Networking
# -----------------------------

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# -----------------------------
# AMI
# Amazon Linux 2023
# -----------------------------

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# -----------------------------
# ECR Repository
# -----------------------------

resource "aws_ecr_repository" "minecraft" {
  name         = "${local.name_prefix}-repo"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project = var.project_name
    Owner   = var.student_name
  }
}

# -----------------------------
# S3 Bucket for Minecraft World Backups
# -----------------------------

resource "aws_s3_bucket" "world_backup" {
  bucket        = "${local.name_prefix}-world-${random_id.suffix.hex}"
  force_destroy = true

  tags = {
    Project = var.project_name
    Owner   = var.student_name
    Purpose = "Minecraft world backups"
  }
}

resource "aws_s3_bucket_versioning" "world_backup" {
  bucket = aws_s3_bucket.world_backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

# -----------------------------
# Security Group
# -----------------------------

resource "aws_security_group" "minecraft" {
  name        = "${local.name_prefix}-sg"
  description = "Allow SSH and Minecraft traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH admin access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  ingress {
    description = "Minecraft Java server"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = var.project_name
    Owner   = var.student_name
  }
}

# -----------------------------
# EC2 Minecraft Server
# -----------------------------

resource "aws_instance" "minecraft" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.minecraft.id]
  key_name                    = var.key_name

  # Required by the assignment / AWS Academy
  iam_instance_profile = "LabInstanceProfile"

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  user_data_replace_on_change = true

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

    echo "Starting k3s bootstrap..."

    # Install required tools.
    # Amazon Linux 2023 already includes curl-minimal, which provides curl.
    # Installing full curl can conflict with curl-minimal.
    dnf install -y awscli cronie

    systemctl enable --now crond

    command -v curl
    command -v aws

    # Create a script to refresh ECR credentials using the IAM instance profile
    cat << 'SCRIPT' > /usr/local/bin/refresh-ecr.sh
    #!/bin/bash
    set -euxo pipefail

    REGION="${var.aws_region}"

    # Wait for the IAM instance profile credentials to become available
    for i in {1..30}; do
      if aws sts get-caller-identity >/tmp/aws-identity.json 2>/tmp/aws-identity.err; then
        break
      fi

      echo "Waiting for IAM instance profile credentials..."
      sleep 10
    done

    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    REGISTRY="$${ACCOUNT_ID}.dkr.ecr.$${REGION}.amazonaws.com"
    TOKEN=$(aws ecr get-login-password --region "$${REGION}")

    mkdir -p /etc/rancher/k3s

    cat << YAMLEOF > /etc/rancher/k3s/registries.yaml
    configs:
      "$${REGISTRY}":
        auth:
          username: AWS
          password: "$${TOKEN}"
    YAMLEOF

    # Restart k3s to pick up new credentials, but only if k3s already exists and is running
    if systemctl list-unit-files | grep -q '^k3s.service' && systemctl is-active --quiet k3s; then
      systemctl restart k3s
    fi
    SCRIPT

    chmod +x /usr/local/bin/refresh-ecr.sh

    # Run once before installing k3s so registries.yaml exists before containerd starts
    /usr/local/bin/refresh-ecr.sh

    # Refresh the temporary ECR token every 6 hours
    echo "0 */6 * * * root /usr/local/bin/refresh-ecr.sh" > /etc/cron.d/ecr-refresh

    # Install k3s.
    # Keep ServiceLB enabled for the Minecraft LoadBalancer Service.
    # Disable Traefik because Minecraft does not need HTTP ingress.
    curl -sfL https://get.k3s.io | sh -s - server --disable traefik

    # Set up kubeconfig for ec2-user
    mkdir -p /home/ec2-user/.kube
    cp /etc/rancher/k3s/k3s.yaml /home/ec2-user/.kube/config
    chown -R ec2-user:ec2-user /home/ec2-user/.kube
    chmod 600 /home/ec2-user/.kube/config

    echo 'export KUBECONFIG=~/.kube/config' >> /home/ec2-user/.bashrc

    echo "k3s bootstrap complete!"

    systemctl status k3s --no-pager
    kubectl get nodes
  EOF

  tags = {
    Name    = local.name_prefix
    Project = var.project_name
    Owner   = var.student_name
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }
}
