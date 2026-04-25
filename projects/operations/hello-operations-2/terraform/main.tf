# Demo project — validates cross-project I/O within the same account.

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

variable "operations_message" {
  description = "Message from the first operations project"
  type        = string
}

resource "aws_ssm_parameter" "hello" {
  name  = "/propeller/${var.environment}/hello-operations-2"
  type  = "String"
  value = "Hello from operations-2, received: ${var.operations_message}"
  tags = {
    ManagedBy = "propeller"
    Project   = "hello-operations-2"
  }
}

output "message" {
  description = "SSM parameter value written by this project."
  value       = aws_ssm_parameter.hello.value
}
