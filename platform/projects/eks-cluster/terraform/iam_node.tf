# Shared node IAM role — created only when at least one node group does not
# supply its own node_role_arn.

resource "aws_iam_role" "node" {
  count = local.create_node_role ? 1 : 0

  name = "${var.cluster_name}-eks-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = local.create_node_role ? toset(var.node_role_policy_arns) : toset([])

  role       = aws_iam_role.node[0].name
  policy_arn = each.value
}

# ── VPC CNI IRSA role ──────────────────────────────────────────────────────────
# AWS recommends scoping AmazonEKS_CNI_Policy to the aws-node ServiceAccount via
# IRSA rather than the node role, so EC2 instances don't inherit ENI/IP
# permissions they don't need. Created whenever node groups exist and IRSA is
# available; consumed by eks-addons as the vpc-cni service_account_role_arn.

data "aws_iam_policy_document" "cni_assume" {
  count = local.create_cni_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [module.cluster.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.cluster.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:aws-node"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.cluster.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cni" {
  count = local.create_cni_role ? 1 : 0

  name               = "${var.cluster_name}-vpc-cni"
  assume_role_policy = data.aws_iam_policy_document.cni_assume[0].json
}

resource "aws_iam_role_policy_attachment" "cni_AmazonEKS_CNI_Policy" {
  count = local.create_cni_role ? 1 : 0

  role       = aws_iam_role.cni[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}
