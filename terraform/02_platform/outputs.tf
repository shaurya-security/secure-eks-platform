#############################################
# AWS Load Balancer Controller
#############################################

output "alb_controller_status" {
  value = helm_release.aws_load_balancer_controller.status
}

output "alb_controller_version" {
  value = helm_release.aws_load_balancer_controller.version
}

#############################################
# External Secrets
#############################################

output "external_secrets_status" {
  value = helm_release.external_secrets.status
}

output "external_secrets_version" {
  value = helm_release.external_secrets.version
}

#############################################
# IRSA
#############################################

output "alb_controller_irsa_role_arn" {
  value = module.aws_load_balancer_controller_irsa.iam_role_arn
}

output "external_secrets_irsa_role_arn" {
  value = module.external_secrets_irsa.iam_role_arn
}


#################################################
# EBS CSI Driver
#################################################

output "ebs_csi_driver_version" {
  value = aws_eks_addon.ebs_csi_driver.addon_version
}
