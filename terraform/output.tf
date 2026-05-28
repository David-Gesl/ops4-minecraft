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

output "ssh_command" {
  description = "SSH command for connecting to the k3s EC2 instance"
  value       = "ssh -i ${var.private_key_path} ec2-user@${aws_instance.minecraft.public_ip}"
}

output "kubectl_tunnel_command" {
  description = "SSH tunnel command for local kubectl access without exposing port 6443 publicly"
  value       = "ssh -i ${var.private_key_path} -N -L 6443:127.0.0.1:6443 ec2-user@${aws_instance.minecraft.public_ip}"
}