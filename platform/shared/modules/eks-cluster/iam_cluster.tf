data "aws_iam_policy" "cluster" {
  name = "AmazonEKSClusterPolicy"
}

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

locals {
  cluster_role_arn = var.create_cluster_role ? aws_iam_role.cluster[0].arn : var.cluster_role_arn
}

resource "aws_iam_role" "cluster" {
  count = var.create_cluster_role ? 1 : 0

  name               = "${var.cluster_name}-eks-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  count = var.create_cluster_role ? 1 : 0

  role       = aws_iam_role.cluster[0].name
  policy_arn = data.aws_iam_policy.cluster.arn
}
