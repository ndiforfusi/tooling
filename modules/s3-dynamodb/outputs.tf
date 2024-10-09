output "bucket" {
  value = aws_s3_bucket.terraform_state.id
}

output "table" {
  value = aws_dynamodb_table.terraform_locks.id
}
