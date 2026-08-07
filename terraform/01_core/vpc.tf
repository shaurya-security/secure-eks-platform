module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.21.0"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  azs = [
    "${var.aws_region}a",
    "${var.aws_region}b"
  ]

  private_subnets = [
    "10.0.1.0/24",
    "10.0.2.0/24"
  ]

  public_subnets = [
    "10.0.101.0/24",
    "10.0.102.0/24"
  ]

  database_subnets = [
    "10.0.11.0/24",
    "10.0.12.0/24"
  ]

  create_database_subnet_group = true

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb"                   = "1"
    "kubernetes.io/cluster/secure-eks-cluster" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"          = "1"
    "kubernetes.io/cluster/secure-eks-cluster" = "shared"
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}
