# 02_platform/ingress.tf
resource "helm_release" "aws_load_balancer_controller" {
  name      = "aws-load-balancer-controller"
  namespace = "kube-system"

  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.9.0" # Pin a specific version

  # Wait for the cluster to be ready
  depends_on = [
    module.aws_load_balancer_controller_irsa,
  ]

  set {
    name  = "clusterName"
    value = data.terraform_remote_state.core.outputs.cluster_name
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = data.terraform_remote_state.core.outputs.vpc_id
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.aws_load_balancer_controller_irsa.iam_role_arn
  }

  # Wait for resources to be ready
  wait          = true
  wait_for_jobs = true
  timeout       = 300
}
