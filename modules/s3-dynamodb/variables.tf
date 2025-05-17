variable "bucket" {
  description = "The name of the S3 bucket"
  type        = string
  default     = "class38-terraform-backend-bucketo"
}


variable "DynamoDBtable" {
  description = "The name of the DynamoDB table"
  type        = string
  default     = "terraform-state-bucket-Azwe"
}

variable "region" {
  description = "The AWS region"
  type        = string
  default     = "us-west-1"
}
