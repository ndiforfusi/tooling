output "jenkins_instance_role_arn" {
  value       = aws_iam_role.jenkins_base_role.arn
  description = "Attach this role via the Jenkins EC2 instance profile"
}

output "jenkins_instance_profile_name" {
  value       = aws_iam_instance_profile.jenkins_profile.name
  description = "Use this value in your aws_instance iam_instance_profile"
}

output "terraform_deploy_role_arn" {
  value       = aws_iam_role.terraform_deploy_role.arn
  description = "Jenkins assumes this role to run Terraform (PowerUserAccess attached)"
}

output "oidc_provider_arn" {
  value       = var.enable_oidc ? aws_iam_openid_connect_provider.jenkins_oidc[0].arn : null
  description = "OIDC provider ARN (if enabled)"
}
