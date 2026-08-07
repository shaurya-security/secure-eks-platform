#################################################
# EBS CSI Driver IRSA
#################################################

module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.52.2"

  role_name = "${var.project_name}-ebs-csi-driver"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn = data.terraform_remote_state.core.outputs.oidc_provider_arn

      namespace_service_accounts = [
        "kube-system:ebs-csi-controller-sa"
      ]
    }
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

#################################################
# EBS CSI Driver Addon
#################################################

resource "aws_eks_addon" "ebs_csi_driver" {

  cluster_name = data.terraform_remote_state.core.outputs.cluster_name

  addon_name = "aws-ebs-csi-driver"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn

  depends_on = [
    module.ebs_csi_driver_irsa
  ]

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}
