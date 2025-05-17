terraform {
  required_version = ">=0.12.0"
  backend "s3" {
    key            = "tooling/terraform.state"
    bucket         = "class38-terraform-backend-bucket"             # the backend is a way of attaching the  dynamodb table to the s3 bucket
    region         = "us-east-2"
    dynamodb_table = "terraform-state-locking"
  }
}
