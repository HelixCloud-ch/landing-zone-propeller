# ── S3 Integration (optional) ─────────────────────────────────────────────────
# When enabled, creates: S3 bucket, IAM role, and associates the role with the
# RDS instance. The S3_INTEGRATION option is handled by option_group.tf.
# Ref: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/oracle-s3-integration.html

resource "aws_s3_bucket" "oracle_data" {
  count = var.enable_s3_integration ? 1 : 0

  bucket = "${var.identifier}-oracle-data-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}-an"

  tags = {
    Name = "${var.identifier}-oracle-data"
  }
}

resource "aws_s3_bucket_versioning" "oracle_data" {
  count  = var.enable_s3_integration ? 1 : 0
  bucket = aws_s3_bucket.oracle_data[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "oracle_data" {
  count  = var.enable_s3_integration ? 1 : 0
  bucket = aws_s3_bucket.oracle_data[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "oracle_data" {
  count  = var.enable_s3_integration ? 1 : 0
  bucket = aws_s3_bucket.oracle_data[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM role for RDS to access S3
data "aws_iam_policy_document" "rds_s3_trust" {
  count = var.enable_s3_integration ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "rds_s3_access" {
  count = var.enable_s3_integration ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = [
      aws_s3_bucket.oracle_data[0].arn,
      "${aws_s3_bucket.oracle_data[0].arn}/*",
    ]
  }
}

resource "aws_iam_role" "rds_s3" {
  count = var.enable_s3_integration ? 1 : 0

  name               = "${var.identifier}-rds-s3-integration"
  assume_role_policy = data.aws_iam_policy_document.rds_s3_trust[0].json
}

resource "aws_iam_role_policy" "rds_s3" {
  count = var.enable_s3_integration ? 1 : 0

  name   = "s3-access"
  role   = aws_iam_role.rds_s3[0].id
  policy = data.aws_iam_policy_document.rds_s3_access[0].json
}

# Associate the IAM role with the RDS instance
resource "aws_db_instance_role_association" "s3" {
  count = var.enable_s3_integration ? 1 : 0

  db_instance_identifier = aws_db_instance.this.identifier
  feature_name           = "S3_INTEGRATION"
  role_arn               = aws_iam_role.rds_s3[0].arn
}
