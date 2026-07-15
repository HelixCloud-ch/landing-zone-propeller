data "archive_file" "autopilot" {
  type        = "zip"
  source_dir  = "${path.module}/../dist"
  output_path = "${path.module}/.build/autopilot.zip"
}

resource "aws_lambda_function" "autopilot" {
  function_name    = "propeller-autopilot"
  role             = aws_iam_role.lambda.arn
  handler          = "index.handler"
  runtime          = "nodejs24.x"
  timeout          = 900
  memory_size      = 1024
  filename         = data.archive_file.autopilot.output_path
  source_code_hash = data.archive_file.autopilot.output_base64sha256

  logging_config {
    log_format            = "JSON"
    application_log_level = "INFO"
    system_log_level      = "WARN"
  }

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

resource "aws_iam_role_policy_attachment" "lambda_durable" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicDurableExecutionRolePolicy"
}

resource "aws_iam_role_policy" "lambda" {
  name = "propeller-autopilot-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:PutParameter"]
        Resource = "arn:aws:ssm:${local.region}:${local.account_id}:parameter/propeller/*"
      },
      {
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = "arn:aws:iam::*:role/deploy-runner*-run-role"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:CopyObject"]
        Resource = "arn:aws:s3:::propeller-source-*/*"
      },
      {
        Effect   = "Allow"
        Action   = ["lambda:CheckpointDurableExecution", "lambda:GetDurableExecutionState", "lambda:ListDurableExecutionsByFunction"]
        Resource = "${aws_lambda_function.autopilot.arn}:*"
      },
    ]
  })
}
