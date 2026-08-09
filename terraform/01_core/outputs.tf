#############################################
# EKS
#############################################

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value     = module.eks.cluster_certificate_authority_data
  sensitive = true
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

#############################################
# Networking
#############################################

output "vpc_id" {
  value = module.vpc.vpc_id
}

#############################################
# Container Registry
#############################################

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

#############################################
# Database
#############################################

output "database_endpoint" {
  value = module.postgres.db_instance_endpoint
}

output "database_secret_arn" {
  value = module.postgres.db_instance_master_user_secret_arn
}

output "aws_region" {
  value = var.aws_region
}
