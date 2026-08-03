variable "identifier" { type = string }
variable "net_id" { type = string }

variable "size" {
  type    = string
  default = "small"
}

variable "label" {
  type    = string
  default = "unset"
}
