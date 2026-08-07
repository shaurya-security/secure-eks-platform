#############################################
# GitHub Actions OIDC Identity Provider
#############################################

locals {
  github_owner = split("/", var.github_repository)[0]
  github_repo  = split("/", var.github_repository)[1]
}


resource "aws_iam_openid_connect_provider" "github" {

  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  # AWS manages GitHub OIDC root CAs automatically.
  thumbprint_list = []
}

#############################################
# GitHub Actions Assume Role Policy
#############################################

data "aws_iam_policy_document" "github_oidc_assume_role" {

  statement {

    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type = "Federated"

      identifiers = [
        aws_iam_openid_connect_provider.github.arn
      ]
    }

    #
    # Enforce correct audience
    #
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }

    #
    # Required by AWS IAM.
    # Wildcard handles GitHub's injected numeric IDs.
    #
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"

      values = [
        "repo:${var.github_owner}*/*:ref:refs/heads/main"
      ]
    }

    #
    # Restrict to this repository only.
    #
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:repository"

      values = [
        "${var.github_owner}/${var.github_repo}"
      ]
    }
  }
}

#############################################
# GitHub Actions IAM Role
#############################################

resource "aws_iam_role" "github_actions" {

  name = "${var.project_name}-github-actions-role"

  assume_role_policy = data.aws_iam_policy_document.github_oidc_assume_role.json

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

#############################################
# GitHub Actions Least-Privilege Policy
#############################################

data "aws_iam_policy_document" "github_actions_policy" {

  #
  # ECR Authentication
  #
  statement {

    sid = "ECRAuthentication"

    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:DescribeRepositories"
    ]

    resources = ["*"]
  }

  #
  # Push/Pull Images
  #
  statement {

    sid = "ECRRepositoryAccess"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:ListImages"
    ]

    resources = [
      aws_ecr_repository.app.arn
    ]
  }

  #
  # Read Cluster Information
  #
  statement {

    sid = "DescribeCluster"

    actions = [
      "eks:DescribeCluster"
    ]

    resources = [
      module.eks.cluster_arn
    ]
  }
}

resource "aws_iam_policy" "github_actions" {

  name = "${var.project_name}-github-actions-policy"

  policy = data.aws_iam_policy_document.github_actions_policy.json
}

resource "aws_iam_role_policy_attachment" "github_actions" {

  role = aws_iam_role.github_actions.name

  policy_arn = aws_iam_policy.github_actions.arn
}

#############################################
# EKS Access Entry
#############################################

resource "aws_eks_access_entry" "github_actions" {

  cluster_name = module.eks.cluster_name

  principal_arn = aws_iam_role.github_actions.arn

  type = "STANDARD"
}

#############################################
# Cluster Access Policy
#############################################

resource "aws_eks_access_policy_association" "github_actions_admin" {

  cluster_name = module.eks.cluster_name

  principal_arn = aws_iam_role.github_actions.arn

  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

#############################################
# Output
#############################################

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}
