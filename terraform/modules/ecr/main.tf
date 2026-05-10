locals {
  base_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
      Module      = "ecr"
    },
    var.additional_tags
  )
}

resource "aws_ecr_repository" "main" {
  for_each = toset(var.repositories)

  name                 = "${var.project}-${var.environment}-${each.key}"
  image_tag_mutability = var.image_tag_mutability

  # force_delete allows destroying repo even when it contains images.
  # Safe for nonprod — prevents RepositoryNotEmptyException during
  # repo rename or cleanup. Set to false in prod for safety.
  force_delete = var.force_delete

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.base_tags, {
    Name = "${var.project}-${var.environment}-${each.key}"
  })
}

resource "aws_ecr_lifecycle_policy" "main" {
  for_each = toset(var.repositories)

  repository = aws_ecr_repository.main[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_expiry_days} day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last ${var.keep_image_count} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "latest", "dev", "staging"]
          countType     = "imageCountMoreThan"
          countNumber   = var.keep_image_count
        }
        action = { type = "expire" }
      }
    ]
  })
}
