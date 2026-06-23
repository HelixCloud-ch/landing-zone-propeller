data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

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
# built-in TLS-only policy when null. The default expresses the universal
# baseline (DenyInsecureTransport); any additional grants belong in the
# override.

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
}

resource "aws_s3_bucket_policy" "this" {
  bucket = module.bucket.bucket_id
  policy = var.bucket_policy_json != null ? var.bucket_policy_json : data.aws_iam_policy_document.default_bucket_policy.json
}
