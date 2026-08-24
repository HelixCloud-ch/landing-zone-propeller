locals {
  role_name  = coalesce(var.role_name, "${var.cluster_name}-aws-load-balancer-controller")
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

resource "aws_iam_policy" "this" {
  count = local.create_iam ? 1 : 0

  name   = "${local.role_name}-policy"
  policy = coalesce(var.iam_policy_json, file("${path.module}/iam_policy.json"))
}

resource "aws_iam_role_policy_attachment" "this" {
  count = local.create_iam ? 1 : 0

  role       = aws_iam_role.this[0].name
  policy_arn = aws_iam_policy.this[0].arn
}

resource "helm_release" "this" {
  name       = "aws-load-balancer-controller"
  repository = var.chart_repository
  chart      = "aws-load-balancer-controller"
  version    = var.chart_version
  namespace  = var.namespace
  replace    = true

  set = concat(
    [
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
        value = tostring(var.create_service_account)
      },
      {
        name  = "serviceAccount.name"
        value = var.service_account_name
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
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = local.effective_role_arn
    },
  ] : []

  depends_on = [aws_iam_role_policy_attachment.this]
}
