module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.37.2"

  cluster_name    = var.cluster_name
  cluster_version = "1.33"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_irsa = true

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  cluster_addons = {

    coredns = {
      most_recent                 = true
      resolve_conflicts_on_update = "PRESERVE"
    }

    kube-proxy = {
      most_recent                 = true
      resolve_conflicts_on_update = "PRESERVE"
    }

    vpc-cni = {
      most_recent                 = true
      resolve_conflicts_on_update = "PRESERVE"
    }

  }



  eks_managed_node_groups = {

    default = {

      desired_size = 2
      min_size     = 2
      max_size     = 3

      instance_types = [
        "m7i-flex.large"
      ]

      capacity_type = "ON_DEMAND"
    }
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}



resource "null_resource" "update_kubeconfig" {
  depends_on = [module.eks]

  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --region ap-south-1 --name ${module.eks.cluster_name}"
  }
}



#################################################
# Current Terraform administrator
#################################################

data "aws_caller_identity" "current" {}

resource "aws_eks_access_entry" "terraform_admin" {

  cluster_name = module.eks.cluster_name

  principal_arn = data.aws_caller_identity.current.arn

  type = "STANDARD"
}

resource "aws_eks_access_policy_association" "terraform_admin" {

  cluster_name = module.eks.cluster_name

  principal_arn = aws_eks_access_entry.terraform_admin.principal_arn

  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
