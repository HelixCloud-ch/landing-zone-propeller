# ── Context ───────────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# Resolve the CDC parameters' KMS key to its real key ARN — but only when it is
# a customer-managed key and the module creates the role. A kms:Decrypt IAM
# statement's Resource must be a key ARN, never an alias ARN; the input is often
# an alias, so aws_kms_key resolves an alias/id/ARN to KeyMetadata.Arn. The
# default AWS-managed key is skipped entirely: its access is not governed by an
# IAM Resource statement, so there is nothing to resolve or grant.
data "aws_kms_key" "cdc" {
  count  = local.kms_lookup ? 1 : 0
  key_id = var.cdc_kms_key_id
}

# ── Service Execution Role ────────────────────────────────────────────────────

data "aws_iam_policy_document" "assume" {
  count = local.create_role ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["kafkaconnect.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    # The connector ARN is generated with a random suffix at create time and so
    # cannot be pinned here; the wildcard is scoped to this connector name in
    # this account/region, and confused-deputy protection is still provided by
    # the SourceAccount condition above.
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.connector_arn_wildcard]
    }
  }
}

resource "aws_iam_role" "connector" {
  count = local.create_role ? 1 : 0

  name               = "${var.identifier}-connector"
  assume_role_policy = data.aws_iam_policy_document.assume[0].json
  tags               = var.tags
}

# Not counted: it also feeds the required_policy_json output, so the owners of
# an external role can apply the same permissions.
data "aws_iam_policy_document" "connector" {
  # Read exactly the two credential parameters this connector uses — nothing wider.
  dynamic "statement" {
    for_each = local.cdc_credentials_enabled ? [1] : []
    content {
      sid       = "ReadCdcCredentials"
      effect    = "Allow"
      actions   = ["ssm:GetParameter"]
      resources = [var.cdc_username_parameter_arn, var.cdc_password_parameter_arn]
    }
  }

  # Decrypt the SecureString parameters when they are encrypted with a
  # customer-managed key, scoped to that key's real ARN. Omitted for the default
  # AWS-managed key, whose decrypt access is implicit and cannot be scoped by an
  # IAM Resource — see the data source comment above.
  dynamic "statement" {
    for_each = local.kms_decrypt_grant ? [1] : []
    content {
      sid       = "DecryptCdcCredentials"
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = [local.kms_key_arn]
    }
  }

  # Kafka data-plane access, only under IAM auth.
  dynamic "statement" {
    for_each = local.kafka_iam_grants ? [1] : []
    content {
      sid    = "KafkaClusterAccess"
      effect = "Allow"
      actions = [
        "kafka-cluster:Connect",
        "kafka-cluster:AlterCluster",
        "kafka-cluster:DescribeCluster",
      ]
      resources = [var.kafka_cluster_arn]
    }
  }

  dynamic "statement" {
    for_each = local.kafka_iam_grants ? [1] : []
    content {
      sid    = "KafkaTopicAndGroupAccess"
      effect = "Allow"
      actions = [
        "kafka-cluster:*Topic*",
        "kafka-cluster:WriteData",
        "kafka-cluster:ReadData",
        "kafka-cluster:*Group*",
      ]
      # Topic and group ARNs derive from the cluster ARN by swapping the
      # `cluster` resource segment for `topic`/`group` and appending a name
      # wildcard; scope the grants to this cluster's topics and groups only.
      resources = [
        var.kafka_cluster_arn,
        "${replace(var.kafka_cluster_arn, ":cluster/", ":topic/")}/*",
        "${replace(var.kafka_cluster_arn, ":cluster/", ":group/")}/*",
      ]
    }
  }
}

# IAM rejects a policy document without statements, so the inline policy is
# skipped when neither credentials nor Kafka IAM grants apply.
resource "aws_iam_role_policy" "connector" {
  count = local.create_role && local.connector_policy_has_statements ? 1 : 0

  name   = "${var.identifier}-connector"
  role   = aws_iam_role.connector[0].id
  policy = data.aws_iam_policy_document.connector.json
}

resource "aws_iam_role_policy" "additional" {
  count = local.create_role && var.additional_policy_json != null ? 1 : 0

  name   = "${var.identifier}-connector-additional"
  role   = aws_iam_role.connector[0].id
  policy = var.additional_policy_json
}

resource "aws_iam_role_policy_attachment" "additional" {
  for_each = local.create_role ? toset(var.additional_policy_arns) : toset([])

  role       = aws_iam_role.connector[0].name
  policy_arn = each.value
}
