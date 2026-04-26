terraform {
  required_version = ">= 1.14"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.41.0"
    }
  }

  backend "s3" {}
}

variable "operations_2_message" {
  description = "Message from hello-operations-2 (injected from dependency)"
  type        = string
}

resource "aws_ssm_parameter" "hello" {
  name  = "/demo/hello-management"
  type  = "String"
  value = "Received: ${var.operations_2_message}"
  tags = {
    ManagedBy = "propeller"
    Project   = "hello-management"
  }
}

output "message" {
  value = aws_ssm_parameter.hello.value
}
