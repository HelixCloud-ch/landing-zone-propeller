# AWS Load Balancer Controller — IAM policy, Helm release, with optional IRSA or Pod Identity.
#
# The controller watches Ingress and Service type=LoadBalancer objects and
# provisions ALBs/NLBs accordingly. The ALB/NLB resources themselves are not
# created here — only the controller that can create them on demand.
#
# The IAM policy is loaded from the versioned iam_policy.json snapshot bundled
# with this module. Keep that file in sync with var.chart_version (both pinned
# to the same upstream controller release).
#
# This module supports two IAM identity methods:
#   - IRSA/OIDC (default): Creates IAM role with trust policy towards the cluster's OIDC provider
#   - Pod Identity: Uses the EKS Pod Identity Agent add-on instead of IRSA
#
# References:
#   https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html
#   https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html
#   https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html

locals {
  role_name = coalesce(var.role_name, "${var.cluster_name}-aws-load-balancer-controller")
}

# ── IRSA/OIDC configuration (only when not using Pod Identity) ────────────────

data "aws_iam_policy_document" "assume" {
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
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  count = var.use_pod_identity ? 0 : 1

  name               = local.role_name
  assume_role_policy = data.aws_iam_policy_document.assume[0].json
}

resource "aws_iam_policy" "this" {
  name   = "${local.role_name}-policy"
  policy = file("${path.module}/iam_policy.json")
}

resource "aws_iam_role_policy_attachment" "this" {
  count = var.use_pod_identity ? 0 : 1

  role       = aws_iam_role.this[0].name
  policy_arn = aws_iam_policy.this.arn
}

# ── Helm release (supports both IRSA and Pod Identity) ───────────────────────

resource "helm_release" "this" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.chart_version
  namespace  = var.namespace

  set = [
    {
      name  = "clusterName"
      value = var.cluster_name
    },
    {
      name  = "region"
      value = var.region
    },
    {
      name  = "vpcId"
      value = var.vpc_id
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = var.service_account_name
    },
  ]

  # When using IRSA/OIDC, attach the role ARN via annotation
  set_sensitive = var.use_pod_identity ? [] : [
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.this[0].arn
    }
  ]
}
