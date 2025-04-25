output "ecr_repository_url" {
  value       = aws_ecr_repository.addressbook.repository_url
  description = "URL of the created ECR repository"
}

