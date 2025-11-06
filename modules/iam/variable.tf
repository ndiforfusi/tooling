##########################################
# AWS Provider Settings
##########################################
variable "aws_region" {
  description = "AWS region where IAM resources will be created"
  type        = string
  default     = "us-west-2"
}

##########################################
# Jenkins IAM Role and Profile
##########################################
variable "jenkins_instance_role_name" {
  description = "Name of the IAM role attached to the Jenkins EC2 instance"
  type        = string
  default     = "JenkinsBaseRole"
}

variable "jenkins_instance_profile_name" {
  description = "Name of the IAM instance profile for the Jenkins EC2 instance"
  type        = string
  default     = "JenkinsInstanceProfile"
}

##########################################
# Terraform Deployment Role
##########################################
variable "deploy_role_name" {
  description = "Name of the IAM role Jenkins will assume to run Terraform"
  type        = string
  default     = "TerraformDeployRole"
}
