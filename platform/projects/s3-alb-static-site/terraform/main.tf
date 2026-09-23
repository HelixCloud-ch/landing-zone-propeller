data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  eni_ids = toset(var.interface_eni_ids)
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

# ── ALB target group ──────────────────────────────────────────────────────────
# Backend traffic is HTTPS/443 to the interface endpoint ENIs. Health checks
# probe on HTTP/80 without a bucket-identifying Host header, so S3 answers
# with 307 (redirect to HTTPS) or 405 (method not allowed). Both are accepted
# as healthy responses.
# https://aws.amazon.com/blogs/networking-and-content-delivery/hosting-internal-https-static-websites-with-alb-s3-and-privatelink/

resource "aws_lb_target_group" "static" {
  name        = "${var.name}-tg"
  target_type = "ip"
  protocol    = "HTTPS"
  port        = 443
  vpc_id      = var.vpc_id

  health_check {
    protocol            = "HTTP"
    port                = "80"
    path                = "/"
    matcher             = "307,405"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# ── Interface endpoint ENI IP attachments ─────────────────────────────────────
# The upstream project publishes ENI IDs as a first-class output. We resolve
# them to their private IPs via a bounded data source and register each as an
# ip-type target.

data "aws_network_interface" "endpoint" {
  for_each = local.eni_ids
  id       = each.value
}

resource "aws_lb_target_group_attachment" "endpoint_eni" {
  for_each          = data.aws_network_interface.endpoint
  target_group_arn  = aws_lb_target_group.static.arn
  target_id         = each.value.private_ip
  availability_zone = "all"
}
