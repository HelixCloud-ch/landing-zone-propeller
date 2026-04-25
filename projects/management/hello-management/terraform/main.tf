# Demo project — validates cross-project I/O across accounts.

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

variable "operations_2_message" {
  description = "Message from the operations-2 project"
  type        = string
}

resource "aws_ssm_parameter" "hello" {
  name  = "/propeller/${var.environment}/hello-management"
  type  = "String"
  value = "Hello from management, received: ${var.operations_2_message}"
  tags = {
    ManagedBy = "propeller"
    Project   = "hello-management"
  }
}

output "message" {
  description = "SSM parameter value written by this project."
  value       = aws_ssm_parameter.hello.value
}
