locals {
  role_name  = coalesce(var.role_name, "${var.cluster_name}-cluster-autoscaler")
  create_iam = !var.use_pod_identity && var.existing_role_arn == null
  effective_role_arn = (
    var.existing_role_arn != null
    ? var.existing_role_arn
    : local.create_iam ? aws_iam_role.this[0].arn : null
  )
}

data "aws_iam_policy_document" "assume" {
  count = local.create_iam ? 1 : 0

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
  count = local.create_iam ? 1 : 0

  name               = local.role_name
  assume_role_policy = data.aws_iam_policy_document.assume[0].json
}

data "aws_iam_policy_document" "autoscaler" {
  count = local.create_iam ? 1 : 0

  statement {
    sid    = "AutoscalerDescribe"
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeImages",
      "ec2:GetInstanceTypesFromInstanceRequirements",
      "eks:DescribeNodegroup",
    ]
    resources = ["*"]
    # checkov:skip=CKV_AWS_356: Describe actions do not support resource-level restrictions — CA discovers ASG names at runtime
    # checkov:skip=CKV_AWS_111: Describe actions do not support resource-level restrictions — CA discovers ASG names at runtime
  }

  statement {
    sid    = "AutoscalerScale"
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }
  }
}

resource "aws_iam_policy" "this" {
  count = local.create_iam ? 1 : 0

  name   = "${local.role_name}-policy"
  policy = data.aws_iam_policy_document.autoscaler[0].json
}

resource "aws_iam_role_policy_attachment" "this" {
  count = local.create_iam ? 1 : 0

  role       = aws_iam_role.this[0].name
  policy_arn = aws_iam_policy.this[0].arn
}

resource "helm_release" "this" {
  name       = "cluster-autoscaler"
  repository = var.chart_repository
  chart      = "cluster-autoscaler"
  version    = var.chart_version
  namespace  = var.namespace
  replace    = true

  set = concat(
    [
      {
        name  = "cloudProvider"
        value = "aws"
      },
      {
        name  = "awsRegion"
        value = var.region
      },
      {
        name  = "autoDiscovery.clusterName"
        value = var.cluster_name
      },
      {
        name  = "rbac.serviceAccount.name"
        value = var.service_account_name
      },
      {
        name  = "rbac.serviceAccount.create"
        value = tostring(var.create_service_account)
      },
    ],
    var.image_repository != null ? [{
      name  = "image.repository"
      value = var.image_repository
    }] : [],
    var.image_tag != null ? [{
      name  = "image.tag"
      value = var.image_tag
    }] : [],
    var.extra_set,
  )

  set_sensitive = (!var.use_pod_identity && var.create_service_account && local.effective_role_arn != null) ? [
    {
      name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = local.effective_role_arn
    },
  ] : []

  depends_on = [aws_iam_role_policy_attachment.this]
}
