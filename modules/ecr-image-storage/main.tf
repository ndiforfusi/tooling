resource "aws_ecr_repository" "addressbook" {
  name                 = var.ecr_image_repo
  image_tag_mutability = "MUTABLE" # Or "IMMUTABLE" to prevent tag overwrites

  # Enable image scanning on push
  image_scanning_configuration {
    scan_on_push = true
  }

  # Retain only the last 30 days of untagged images
  lifecycle_policy {
    policy = <<EOF
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Expire untagged images after 30 days",
      "selection": {
        "tagStatus": "untagged",
        "countType": "sinceImagePushed",
        "countUnit": "days",
        "countNumber": 30
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
EOF
  }
}
