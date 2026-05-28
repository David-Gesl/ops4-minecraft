output "public_ip" {
  description = "Public IP address of the Minecraft EC2 instance"
  value       = aws_instance.minecraft.public_ip
}

output "public_dns" {
  description = "Public DNS name of the Minecraft EC2 instance"
  value       = aws_instance.minecraft.public_dns
}

output "ecr_repository_name" {
  description = "ECR repository name"
  value       = aws_ecr_repository.minecraft.name
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.minecraft.repository_url
}

output "world_backup_bucket" {
  description = "S3 bucket used for Minecraft world backups"
  value       = aws_s3_bucket.world_backup.bucket
}

output "ansible_inventory" {
  description = "Generated Ansible inventory path"
  value       = local_file.ansible_inventory.filename
}