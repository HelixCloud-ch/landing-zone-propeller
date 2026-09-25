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
# TLS-only baseline, plus GetObject allowed only when the request originates
# from the paired S3 interface VPC endpoint. Traffic that reaches S3 through
# any other path (public internet, another VPCE, a different account) is
# denied even though the Allow statement uses "Principal": "*".

data "aws_iam_policy_document" "bucket" {
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

  statement {
    sid    = "AllowGetFromInterfaceEndpointOnly"
    effect = "Allow"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${module.bucket.bucket_arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceVpce"
      values   = [var.interface_endpoint_id]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = module.bucket.bucket_id
  policy = data.aws_iam_policy_document.bucket.json
}
