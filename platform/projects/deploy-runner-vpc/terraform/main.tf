# ── Subnet resolution ─────────────────────────────────────────────────────────

locals {
  # Use explicit subnet_ids if provided, otherwise decode from JSON tier map
  resolved_subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : (
    var.subnet_ids_json != "" ? jsondecode(var.subnet_ids_json)[var.subnet_tier] : []
  )

  state_bucket = var.state_bucket_name != "" ? var.state_bucket_name : "state-iac-${data.aws_caller_identity.current.account_id}-${var.region}-an"
}

data "aws_caller_identity" "current" {}

# ── Security group (all outbound) ─────────────────────────────────────────────

resource "aws_security_group" "codebuild" {
  name        = "${var.project_name}-sg"
  description = "Security group for VPC-attached CodeBuild deploy runner"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

# ── IAM role for CodeBuild ────────────────────────────────────────────────────

resource "aws_iam_role" "codebuild" {
  name = "${var.project_name}-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codebuild.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.codebuild.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ── S3 read access (bundle bucket in operations account) ──────────────────────

resource "aws_iam_role_policy" "s3_read_bundle" {
  name = "read-bundle-bucket"
  role = aws_iam_role.codebuild.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetBucketLocation",
        "s3:ListBucket",
      ]
      Resource = [
        "arn:aws:s3:::${var.bundle_bucket_name}",
        "arn:aws:s3:::${var.bundle_bucket_name}/*",
      ]
    }]
  })
}

# ── S3 read/write access (state bucket in same account) ──────────────────────

resource "aws_iam_role_policy" "s3_state" {
  name = "state-bucket"
  role = aws_iam_role.codebuild.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:PutObject",
        "s3:GetBucketLocation",
        "s3:ListBucket",
      ]
      Resource = [
        "arn:aws:s3:::${local.state_bucket}",
        "arn:aws:s3:::${local.state_bucket}/*",
      ]
    }]
  })
}

# ── Cross-account run role (assumed by autopilot Lambda) ──────────────────────

resource "aws_iam_role" "run_role" {
  name = "${var.project_name}-run-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.caller_account_id}:root"
      }
      Action = "sts:AssumeRole"
      Condition = {
        ArnEquals = {
          "aws:PrincipalArn" = var.caller_arn
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "run_role_codebuild" {
  name = "codebuild-access"
  role = aws_iam_role.run_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "codebuild:StartBuild",
        "codebuild:BatchGetBuilds",
        "codebuild:StopBuild",
      ]
      Resource = aws_codebuild_project.runner.arn
    }]
  })
}

# ── CloudWatch Logs ───────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${var.project_name}"
  retention_in_days = 90
}

# ── CodeBuild project (VPC-attached) ─────────────────────────────────────────

resource "aws_codebuild_project" "runner" {
  name           = var.project_name
  service_role   = aws_iam_role.codebuild.arn
  build_timeout  = var.timeout_minutes

  artifacts {
    type = "NO_ARTIFACTS"
  }

  cache {
    type = "NO_CACHE"
  }

  environment {
    compute_type                = var.compute_type
    image                       = var.image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  logs_config {
    cloudwatch_logs {
      status     = "ENABLED"
      group_name = aws_cloudwatch_log_group.codebuild.name
    }
  }

  source {
    type      = "NO_SOURCE"
    buildspec = <<-BUILDSPEC
      version: 0.2
      phases:
        build:
          commands:
            - echo "No buildspec override provided"
    BUILDSPEC
  }

  vpc_config {
    vpc_id             = var.vpc_id
    subnets            = local.resolved_subnet_ids
    security_group_ids = [aws_security_group.codebuild.id]
  }
}
