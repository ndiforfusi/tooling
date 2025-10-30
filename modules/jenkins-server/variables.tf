variable "instance_type" {
  description = "The instance type for the Jenkins server"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "The key name for the Jenkins server"
  type        = string
  default     = "Oregon-private-key"
}

variable "main-region" {
  description = "The AWS region to deploy resources"
  type        = string
  default     = "us-west-2"
}

variable "availability_zone" {
  description = "AZ to place the instance/subnet in"
  type        = string
  default     = "us-west-2a"
}

