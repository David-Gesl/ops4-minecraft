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

  tags = {
    Name    = local.name_prefix
    Project = var.project_name
    Owner   = var.student_name
  }
}

# -----------------------------
# Generated Ansible Inventory
# -----------------------------

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/generated/inventory.ini"

  content = <<EOF
[minecraft]
${aws_instance.minecraft.public_ip} ansible_user=ec2-user ansible_ssh_private_key_file=${var.private_key_path} ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF
}

resource "null_resource" "run_ansible" {
  depends_on = [
    aws_instance.minecraft,
    aws_ecr_repository.minecraft,
    aws_s3_bucket.world_backup,
    aws_s3_bucket_versioning.world_backup,
    local_file.ansible_inventory
  ]

  triggers = {
    instance_id   = aws_instance.minecraft.id
    public_ip     = aws_instance.minecraft.public_ip
    playbook_hash = filesha256("${path.module}/../ansible/playbook.yml")
    image_tag     = "v1.0.1"
    motd          = "David-Gesl-Ops3-Minecraft"
  }

  provisioner "local-exec" {
    working_dir = path.module

    command = <<EOT
      echo "Waiting for SSH to be ready on ${aws_instance.minecraft.public_ip}..."

      until ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        -i '${var.private_key_path}' \
        ec2-user@${aws_instance.minecraft.public_ip} \
        "echo SSH is ready"; do
          echo "Still waiting for SSH..."
          sleep 10
      done

      echo "Running Ansible playbook..."

      ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
        -i '${aws_instance.minecraft.public_ip},' \
        ../ansible/playbook.yml \
        -u ec2-user \
        --private-key '${var.private_key_path}' \
        -e 'aws_region=${var.aws_region}' \
        -e 'ecr_repository_url=${aws_ecr_repository.minecraft.repository_url}' \
        -e 'image_tag=v1.0.1' \
        -e 'world_backup_bucket=${aws_s3_bucket.world_backup.bucket}' \
        -e 'minecraft_motd=David-Gesl-Ops3-Minecraft'
    EOT
  }
}