variable "aws_region" {
  description = "AWS region for IAM resources"
  type        = string
  default     = "us-west-2"
}

# ---- Names ----
variable "jenkins_instance_role_name" {
  description = "Name of the IAM role attached to the Jenkins EC2 instance"
  type        = string
  default     = "JenkinsBaseRole"
}

variable "jenkins_instance_profile_name" {
  description = "Name of the IAM instance profile for Jenkins EC2 instance"
  type        = string
  default     = "JenkinsInstanceProfile"
}

variable "deploy_role_name" {
  description = "Name of the IAM role Jenkins will assume to run Terraform"
  type        = string
  default     = "TerraformDeployRole"
}

# ---- OIDC (optional) ----
variable "enable_oidc" {
  description = "Create an IAM OIDC provider and add OIDC trust to the deploy role"
  type        = bool
  default     = false
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL (e.g., https://token.actions.githubusercontent.com or your IdP)"
  type        = string
  default     = "https://token.actions.githubusercontent.com"
}

variable "oidc_audience" {
  description = "OIDC audience (usually sts.amazonaws.com)"
  type        = string
  default     = "sts.amazonaws.com"
}

variable "oidc_sub_claim" {
  description = "Subject claim to restrict which identity can assume the role (e.g., repo:org/name:ref:refs/heads/main)"
  type        = string
  default     = "repo:your-org/your-repo:ref:refs/heads/main"
}
