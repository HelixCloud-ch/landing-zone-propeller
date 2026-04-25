# Demo project — validates SSM output for downstream consumers.

terraform {
  required_version = ">= 1.14"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.41.0"
    }
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment name."
  default     = "sandbox"
}

resource "aws_ssm_parameter" "hello" {
  name  = "/propeller/${var.environment}/hello-operations"
  type  = "String"
  value = "Hello from operations account"
  tags = {
    ManagedBy = "propeller"
    Project   = "hello-operations"
  }
}

output "message" {
  description = "SSM parameter value written by this project."
  value       = aws_ssm_parameter.hello.value
}
