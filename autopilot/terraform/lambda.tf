data "archive_file" "autopilot" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/.build/autopilot.zip"
}

resource "aws_lambda_function" "autopilot" {
  function_name    = "propeller-autopilot"
  role             = aws_iam_role.lambda.arn
  handler          = "handler.handler"
  runtime          = "python3.14"
  timeout          = 900
  memory_size      = 512
  filename         = data.archive_file.autopilot.output_path
  source_code_hash = data.archive_file.autopilot.output_base64sha256

  durable_config {
    execution_timeout = 86400
    retention_period  = 7
  }
}

resource "aws_iam_role" "lambda" {
  name = "propeller-autopilot-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "propeller-autopilot-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:PutParameter"]
        Resource = "arn:aws:ssm:${local.region}:${local.account_id}:parameter/propeller/*"
      },
      {
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = "arn:aws:iam::*:role/deploy-runner-run-role"
      },
      {
        Effect   = "Allow"
        Action   = ["lambda:CheckpointDurableExecution", "lambda:GetDurableExecutionState"]
        Resource = "${aws_lambda_function.autopilot.arn}:*"
      },
    ]
  })
}
