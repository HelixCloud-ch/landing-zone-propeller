resource "aws_mskconnect_custom_plugin" "this" {
  for_each = var.plugins

  name         = join("-", [var.name_prefix, each.key])
  content_type = "ZIP"

  location {
    s3 {
      bucket_arn = var.artifact_bucket_arn
      file_key   = each.value.file_key
      # object_version is optional on this resource; omitted (rather than an
      # empty string) when the destination bucket is not versioned.
      object_version = each.value.object_version
    }
  }
}
