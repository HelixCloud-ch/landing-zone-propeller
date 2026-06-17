locals {
  bucket_name = var.bucket_namespace == "account-regional" ? (
    format("%s-%s-%s-an", var.name, var.account_id, var.region)
  ) : var.name
}

# ── Bucket ────────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "this" {
  bucket           = local.bucket_name
  bucket_namespace = var.bucket_namespace

  force_destroy = var.force_destroy

  lifecycle {
    precondition {
      condition     = var.bucket_namespace != "account-regional" || (var.account_id != null && var.region != null)
      error_message = "When bucket_namespace is \"account-regional\", account_id and region must both be provided."
    }
  }
}

# ── Versioning ────────────────────────────────────────────────────────────────

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Disabled"
  }
}

# ── Encryption ────────────────────────────────────────────────────────────────

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = var.kms_key_arn != null ? true : null
  }
}

# ── Public access block ───────────────────────────────────────────────────────

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = var.block_public_acls
  block_public_policy     = var.block_public_policy
  ignore_public_acls      = var.ignore_public_acls
  restrict_public_buckets = var.restrict_public_buckets
}

# ── Bucket policy ─────────────────────────────────────────────────────────────
# The caller passes the full policy JSON. Only attached when provided.

resource "aws_s3_bucket_policy" "this" {
  count = var.bucket_policy_json != null ? 1 : 0

  bucket = aws_s3_bucket.this.id
  policy = var.bucket_policy_json

  # Public access block must be in place before the policy is attached.
  depends_on = [aws_s3_bucket_public_access_block.this]
}
