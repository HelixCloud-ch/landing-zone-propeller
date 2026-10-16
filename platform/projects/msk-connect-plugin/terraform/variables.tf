variable "region" {
  type        = string
  description = "AWS region."
}

# ── Plugin inputs ─────────────────────────────────────────────────────────────

variable "plugins" {
  type = map(object({
    file_key       = string
    object_version = optional(string)
  }))
  description = <<-EOT
    Custom plugins to register, keyed by full plugin identity
    "<flavour>-<version>" (e.g. "mariadb-2.7.4.Final"). Each entry gives the
    artifact's S3 file key and, when the bucket is versioned, its object
    version. Decoded from the artifact project's single `plugins_json` output.
    A version bump ADDS a new key (old and new plugins coexist); remove a key
    only after no connector references it — see README.md.
  EOT
}

variable "default_versions" {
  type        = map(string)
  description = <<-EOT
    Default version per flavour, e.g. { mariadb = "2.7.4.Final" }. Decoded from
    the artifact project's `default_versions_json` output. Selects which
    plugin_arns / plugin_revisions entry default_plugin_arns /
    default_plugin_revisions expose for a consumer that always wants "the
    current one" rather than naming a version.
  EOT

  validation {
    condition = alltrue([
      for flavour, version in var.default_versions :
      contains(keys(var.plugins), "${flavour}-${version}")
    ])
    error_message = "Every default_versions entry must resolve to a key already present in plugins (\"<flavour>-<version>\"); a default cannot point at a version that was never registered."
  }
}

variable "artifact_bucket_arn" {
  type        = string
  description = "ARN of the S3 bucket holding the connector artifacts referenced by `plugins`."
}

variable "name_prefix" {
  type        = string
  default     = "debezium"
  description = "Prefix for each custom plugin name; the full name is hyphen-joined as <name_prefix>-<plugin-key>. Defaults to \"debezium\"."

  validation {
    condition = alltrue([
      for k in keys(var.plugins) :
      length(join("-", [var.name_prefix, k])) <= 128
    ])
    error_message = "The composed custom plugin name <name_prefix>-<plugin-key> must be at most 128 characters (AWS MSK Connect CreateCustomPlugin name limit); shorten name_prefix or the plugin key."
  }
}

# ── Tags ──────────────────────────────────────────────────────────────────────

variable "tags" {
  type    = map(string)
  default = {}
}

variable "consumer_tags" {
  type    = map(string)
  default = {}
}

variable "propeller_tags" {
  type    = map(string)
  default = {}
}
