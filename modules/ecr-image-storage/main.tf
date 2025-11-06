resource "aws_ecr_repository" "addressbook" {
  name                 = var.ecr_image_repo
  image_tag_mutability = "MUTABLE" # or "IMMUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  # Optional but recommended
  encryption_configuration {
    encryption_type = "AES256" # or "KMS"
    # kms_key       = aws_kms_key.ecr.arn
  }

  # tags = var.tags
}

resource "aws_ecr_lifecycle_policy" "untagged_after_30_days" {
  repository = aws_ecr_repository.addressbook.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 30 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 30
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
