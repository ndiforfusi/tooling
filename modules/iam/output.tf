output "jenkins_instance_role_arn" {
  value       = aws_iam_role.jenkins_base_role.arn
  description = "ARN of the Jenkins EC2 base role"
}

output "jenkins_instance_profile_name" {
  value       = aws_iam_instance_profile.jenkins_profile.name
  description = "Attach this instance profile to the Jenkins EC2 instance"
}

output "terraform_deploy_role_arn" {
  value       = aws_iam_role.terraform_deploy_role.arn
  description = "Role ARN Jenkins will assume to run Terraform"
}
