variable "bucket" {
  description = "The name of the S3 bucket"
  type        = string
  default     = "class38dominion-terraform-backend"
}

variable "table" {
  description = "The name of the DynamoDB table"
  type        = string
  default     = "terraform-state-locking"
}

variable "region" {
  description = "The AWS region"
  type        = string
  default     = "us-east-2"
}
