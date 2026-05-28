variable "aws_region" {
  description = "AWS Academy region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for AWS resource names"
  type        = string
  default     = "ops3-minecraft"
}

variable "student_name" {
  description = "Your name or student ID for tags and Minecraft MOTD"
  type        = string
  default     = "david-gesl"
}

variable "instance_type" {
  description = "EC2 instance type for Minecraft"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "Existing EC2 SSH key pair name in AWS"
  type        = string
}

variable "private_key_path" {
  description = "Local path to SSH private key"
  type        = string
}

variable "ssh_cidr" {
  description = "Public IP CIDR allowed to SSH into the instance"
  type        = string
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 20
}