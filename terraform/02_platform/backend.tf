terraform {
  backend "s3" {
    bucket       = "shaurya-eks-tfstate-2026"
    key          = "secure-eks-platform/platform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}
