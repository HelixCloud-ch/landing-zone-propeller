variable "region" {
  type        = string
  description = "AWS region."
}

variable "namespace" {
  type        = string
  description = "Pipeline namespace (PROPELLER_NAMESPACE)."
  default     = "unknown"
}

variable "project_name" {
  type        = string
  description = "Project name (PROJECT_NAME)."
  default     = "smoke-test"
}

variable "upstream_value" {
  type        = string
  description = "Optional upstream input for wiring tests."
  default     = ""
}

variable "consumer_tags" {
  type    = map(string)
  default = {}
}

variable "propeller_tags" {
  type    = map(string)
  default = {}
}
