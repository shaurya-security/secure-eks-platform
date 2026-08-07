provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

#################################################
# EKS Authentication
#################################################

data "aws_eks_cluster_auth" "this" {
  name = data.terraform_remote_state.core.outputs.cluster_name
}

#################################################
# Kubernetes Provider
#################################################

provider "kubernetes" {

  host = data.terraform_remote_state.core.outputs.cluster_endpoint

  cluster_ca_certificate = base64decode(
    data.terraform_remote_state.core.outputs.cluster_certificate_authority_data
  )

  token = data.aws_eks_cluster_auth.this.token
}

#################################################
# Helm Provider
#################################################

provider "helm" {

  kubernetes {

    host = data.terraform_remote_state.core.outputs.cluster_endpoint

    cluster_ca_certificate = base64decode(
      data.terraform_remote_state.core.outputs.cluster_certificate_authority_data
    )

    token = data.aws_eks_cluster_auth.this.token
  }
}
