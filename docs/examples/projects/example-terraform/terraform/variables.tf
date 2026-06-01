variable "region" {
  type        = string
  description = "AWS region."
}

variable "upstream_message" {
  type        = string
  description = "Message produced by an upstream project (wired in the pipeline)."
}
