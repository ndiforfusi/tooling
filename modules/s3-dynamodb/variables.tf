variable "bucket" {
  description = "The name of the S3 bucket"
  type        = string
  default     = "dominion-terraform-backend-bucket"
}

variable "table" {
  description = "The name of the DynamoDB table"
  type        = string
  default     = "terraform-state-locking"
}

variable "region" {
  description = "The AWS region"
  type        = string
  default     = "us-west-2"
}
