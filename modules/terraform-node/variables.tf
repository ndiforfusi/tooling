##############################
# Core AWS + Naming
##############################

variable "region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-west-2"
}

variable "name_prefix" {
  description = "Prefix applied to resource names."
  type        = string
  default     = "cicd"
}

##############################
# Networking
##############################


variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed to SSH (port 22). Replace with office/VPN CIDR for production."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

##############################
# EC2 Instance Configuration
##############################

variable "instance_type" {
  description = "EC2 instance type for the build node."
  type        = string
  default     = "t3.medium"
}

variable "associate_public_ip" {
  description = "Attach a public IP to the instance if true. Recommended 'false' for private subnets."
  type        = bool
  default     = false
}

variable "user_data" {
  description = "EC2 user data script (cloud-init or bash)."
  type        = string
  default     = ""
}

variable "ssh_key_name" {
  description = "Optional EC2 key pair name for SSH access. Leave null to rely on AWS SSM Session Manager."
  type        = string
  default     = null
}

variable "availability_zone" {
  description = "AZ to place the instance/subnet in"
  type        = string
  default     = "us-west-2a"
}


variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB (gp3)."
  type        = number
  default     = 20
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for the instance."
  type        = bool
  default     = false
}

##############################
# OS / AMI Selection
##############################

variable "os_family" {
  description = "Select AMI base: 'al2023' (default) or 'al2'."
  type        = string
  default     = "al2023"

  validation {
    condition     = contains(["al2023", "al2"], var.os_family)
    error_message = "os_family must be 'al2023' or 'al2'."
  }
}

##############################
# IAM and Security
##############################

variable "external_id" {
  description = "Optional ExternalId condition to enforce when the EC2 role is assumed."
  type        = string
  default     = null
}

##############################
# Tagging
##############################

variable "tags" {
  description = "Common resource tags."
  type        = map(string)
  default = {
    Project     = "cicd"
    Environment = "dev"
    Owner       = "platform"
  }
}


# Add PassRole targets you actually need (cluster/nodegroup/fargate/ALB controller, etc.)
variable "passrole_arns" {
  description = "List of IAM Role ARNs that this CI role may pass to AWS services (EKS/nodegroups, etc.)"
  type        = list(string)
  default     = [] # e.g., ["arn:aws:iam::327019199684:role/eks-cluster-role","arn:aws:iam::327019199684:role/eks-nodegroup-role"]
}

# Optional: allow creating specific service-linked roles commonly needed by EKS/ASG/ELB
variable "allow_create_slr" {
  description = "Whether to allow CreateServiceLinkedRole for common services"
  type        = bool
  default     = true
}

variable "allocate_eip" {
  description = "If true, allocate and attach a new Elastic IP to the build node."
  type        = bool
  default     = true
}

variable "eip_allocation_id" {
  description = "Optional existing EIP allocation ID (eipalloc-xxxx) to attach instead of creating a new one."
  type        = string
  default     = null
}

