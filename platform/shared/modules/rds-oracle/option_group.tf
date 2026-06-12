# ── Option Group (module-managed) ─────────────────────────────────────────────
# Always created. Includes S3_INTEGRATION when enabled, plus any additional_options.

resource "aws_db_option_group" "this" {
  name                     = "${var.identifier}-options"
  engine_name              = var.engine
  major_engine_version     = var.engine_version
  option_group_description = "Option group for ${var.identifier}"

  dynamic "option" {
    for_each = local.all_options
    content {
      option_name = option.value.option_name
      version     = option.value.version
      port        = option.value.port

      dynamic "option_settings" {
        for_each = option.value.settings
        content {
          name  = option_settings.value.name
          value = option_settings.value.value
        }
      }
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}
