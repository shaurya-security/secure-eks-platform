#############################################
# Elastic Container Registry
#############################################

resource "aws_ecr_repository" "app" {

  name = var.project_name

  image_tag_mutability = "MUTABLE"

  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {

    encryption_type = "KMS"

    kms_key = aws_kms_key.ecr.arn
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

#############################################
# Lifecycle Policy
#############################################

resource "aws_ecr_lifecycle_policy" "app" {

  repository = aws_ecr_repository.app.name

  policy = jsonencode({

    rules = [

      {
        rulePriority = 1

        description = "Keep latest 10 images"

        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }

        action = {
          type = "expire"
        }
      }
    ]
  })
}
