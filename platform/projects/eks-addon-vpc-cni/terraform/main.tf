locals {
  role_name = coalesce(var.role_name, "${var.cluster_name}-vpc-cni")
}

data "aws_iam_policy_document" "assume_irsa" {
  count = var.use_pod_identity ? 0 : 1

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:aws-node"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "assume_pod_identity" {
  count = var.use_pod_identity ? 1 : 0

  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = local.role_name
  assume_role_policy = var.use_pod_identity ? data.aws_iam_policy_document.assume_pod_identity[0].json : data.aws_iam_policy_document.assume_irsa[0].json
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

module "vpc_cni" {
  source = "../../../shared/modules/eks-addon-base"

  cluster_name         = var.cluster_name
  addon_name           = "vpc-cni"
  addon_version        = var.addon_version
  configuration_values = var.configuration_values

  service_account_role_arn = var.use_pod_identity ? null : aws_iam_role.this.arn

  pod_identity_association = var.use_pod_identity ? {
    role_arn        = aws_iam_role.this.arn
    service_account = "aws-node"
  } : null

  depends_on = [aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy]
}
