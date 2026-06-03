variable "region" {
  type        = string
  description = "AWS region for the autopilot resources."
}

variable "tags" {
  type        = map(string)
  description = "Optional consumer tags applied via provider default_tags. Framework tags are merged on top."
  default     = {}
}
