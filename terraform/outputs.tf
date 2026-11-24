
output "aws_region" {
  description = "Configured AWS region"
  value       = var.aws_region
}
output "ecr_repository_name" {
  value = aws_ecr_repository.webapp.name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.webapp.repository_url
}

output "ec2_instance_id" {
  value = aws_instance.webapp.id
}

output "ec2_public_ip" {
  value = aws_instance.webapp.public_ip
}
