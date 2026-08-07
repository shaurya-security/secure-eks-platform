#############################################
# KMS Key - ECR Encryption
#############################################

resource "aws_kms_key" "ecr" {

  description = "KMS key for ECR image encryption"

  enable_key_rotation = true

  deletion_window_in_days = 7

  tags = {
    Name        = "${var.project_name}-ecr"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_kms_alias" "ecr" {

  name = "alias/${var.project_name}-ecr"

  target_key_id = aws_kms_key.ecr.key_id
}
