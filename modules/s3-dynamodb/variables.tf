variable "bucket" {
  description = "The name of the S3 bucket"
  type        = string
  default     = "class38-terraform-backend-bucket-01"
  #default     = "terraform-state-bucket-fusi"
 
}


variable "DynamoDBtable" {
  description = "The name of the DynamoDB table"
  type        = string
  default     = "terraform-state-file-locking"

  #default     = "terraform-state-locking"
}

variable "region" {
  description = "The AWS region"
  type        = string
  default     = "us-west-1"
}
