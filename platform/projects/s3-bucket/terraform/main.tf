data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  enforce_kms_key = var.kms_key_arn != null && var.enforce_kms_key
}

# ── Bucket ────────────────────────────────────────────────────────────────────

module "bucket" {
  source = "../../../shared/modules/s3-bucket"

  name             = var.name
  bucket_namespace = "account-regional"
  account_id       = data.aws_caller_identity.current.account_id
  region           = data.aws_region.current.region

  versioning_enabled = var.versioning_enabled
  force_destroy      = var.force_destroy
  kms_key_arn        = var.kms_key_arn
}

# ── Bucket policy ─────────────────────────────────────────────────────────────
# Caller-supplied policy via var.bucket_policy_json, falling back to the
# built-in policy when null. The default expresses the universal baseline
# (DenyInsecureTransport, plus KMS enforcement when enabled); any
# additional grants belong in the override.

data "aws_iam_policy_document" "default_bucket_policy" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:*"]
    resources = [module.bucket.bucket_arn, "${module.bucket.bucket_arn}/*"]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # KMS enforcement (see README). Uploads without encryption headers stay
  # allowed: they get the bucket default, which is the same key.
  dynamic "statement" {
    for_each = local.enforce_kms_key ? [1] : []
    content {
      sid    = "DenyNonKmsEncryption"
      effect = "Deny"
      principals {
        type        = "*"
        identifiers = ["*"]
      }
      actions   = ["s3:PutObject"]
      resources = ["${module.bucket.bucket_arn}/*"]
      condition {
        test     = "StringNotEqualsIfExists"
        variable = "s3:x-amz-server-side-encryption"
        values   = ["aws:kms"]
      }
    }
  }

  dynamic "statement" {
    for_each = local.enforce_kms_key ? [1] : []
    content {
      sid    = "DenyKmsWithoutKeyId"
      effect = "Deny"
      principals {
        type        = "*"
        identifiers = ["*"]
      }
      actions   = ["s3:PutObject"]
      resources = ["${module.bucket.bucket_arn}/*"]
      condition {
        test     = "StringEquals"
        variable = "s3:x-amz-server-side-encryption"
        values   = ["aws:kms"]
      }
      condition {
        test     = "Null"
        variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
        values   = ["true"]
      }
    }
  }

  dynamic "statement" {
    for_each = local.enforce_kms_key ? [1] : []
    content {
      sid    = "DenyOtherKmsKey"
      effect = "Deny"
      principals {
        type        = "*"
        identifiers = ["*"]
      }
      actions   = ["s3:PutObject"]
      resources = ["${module.bucket.bucket_arn}/*"]
      condition {
        test     = "StringNotEqualsIfExists"
        variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
        values   = [var.kms_key_arn]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  count = var.manage_bucket_policy ? 1 : 0

  bucket = module.bucket.bucket_id
  policy = var.bucket_policy_json != null ? var.bucket_policy_json : data.aws_iam_policy_document.default_bucket_policy.json
}
