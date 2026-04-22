resource "aws_iam_role" "this" {
  name = "${var.sfn_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "states.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codebuild" {
  name = "codebuild"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CodeBuildLocal"
        Effect = "Allow"
        Action = [
          "codebuild:StartBuild",
          "codebuild:StopBuild",
          "codebuild:BatchGetBuilds",
        ]
        Resource = [local.local_cb_arn]
      },
      {
        Sid    = "EventBridgeForSync"
        Effect = "Allow"
        Action = [
          "events:PutTargets",
          "events:PutRule",
          "events:DescribeRule",
        ]
        Resource = [local.eventbridge_rule]
      },
      {
        Sid    = "LogsAndTracing"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:CreateLogStream",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutLogEvents",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups",
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets",
        ]
        Resource = ["*"]
      },
    ]
  })
}

resource "aws_iam_role_policy" "cross_account" {
  name = "cross-account-assume"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AssumeRunRole"
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = local.run_role_pattern
      Condition = {
        "ForAnyValue:StringLike" = {
          "aws:PrincipalOrgPaths" = ["${var.organization_id}/*"]
        }
      }
    }]
  })
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/states/${var.sfn_name}"
  retention_in_days = 90
}

resource "aws_sfn_state_machine" "this" {
  name     = var.sfn_name
  role_arn = aws_iam_role.this.arn

  definition = templatefile("${path.module}/templates/landing-zone-propeller-sfn.asl.json.tftpl", {
    local_account_id            = local.account_id
    deploy_runner_project_name  = var.deploy_runner_project_name
    cross_account_run_role_name = var.cross_account_run_role_name
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.this.arn}:*"
    include_execution_data = true
    level                  = "ERROR"
  }

  tracing_configuration {
    enabled = true
  }
}
