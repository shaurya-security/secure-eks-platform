module "external_secrets_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.52.2"

  role_name = "${var.project_name}-external-secrets"

  attach_external_secrets_policy = true

  oidc_providers = {
    main = {
      provider_arn = data.terraform_remote_state.core.outputs.oidc_provider_arn

      namespace_service_accounts = [
        "external-secrets:external-secrets"
      ]
    }
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}



# 02_platform/secrets.tf
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true

  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "0.14.0" # Pin a specific version

  depends_on = [
    module.external_secrets_irsa,
  ]

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "external-secrets"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.external_secrets_irsa.iam_role_arn
  }

  # Wait for resources to be ready
  wait          = true
  wait_for_jobs = true
  timeout       = 300
}
