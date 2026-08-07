data "terraform_remote_state" "core" {
  backend = "s3"

  config = {
    bucket       = "shaurya-eks-tfstate-2026"
    key          = "secure-eks-platform/core.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
