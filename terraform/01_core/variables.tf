variable "aws_region" {
  default = "ap-south-1"
}

variable "project_name" {
  default = "secure-eks-platform"
}

variable "environment" {
  default = "production"
}

variable "cluster_name" {
  default = "secure-eks-cluster"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "db_name" {
  default = "flaskdb"
}

variable "db_username" {
  default = "postgres"
}


variable "github_repository" {
  description = "owner/repository format"

  default = "shaurya-security/secure-eks-platform"
}

variable "github_owner" {
  description = "GitHub organization or username"
  type        = string
  default     = "shaurya-security"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "secure-eks-platform"
}
