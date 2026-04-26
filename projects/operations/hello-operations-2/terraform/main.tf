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

variable "operations_message" {
  description = "Message from hello-operations (injected from dependency)"
  type        = string
}

variable "greeting" {
  description = "Greeting prefix (customer-configurable)"
  type        = string
  default     = "Received"
}

resource "aws_ssm_parameter" "hello" {
  name  = "/demo/hello-operations-2"
  type  = "String"
  value = "${var.greeting}: ${var.operations_message}"
  tags = {
    ManagedBy = "propeller"
    Project   = "hello-operations-2"
  }
}

output "message" {
  value = aws_ssm_parameter.hello.value
}
