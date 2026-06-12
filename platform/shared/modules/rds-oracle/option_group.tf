# ── Option Group (module-managed) ─────────────────────────────────────────────
# Created when enable_s3_integration or additional_options are set,
# and no external option_group_name is provided.

resource "aws_db_option_group" "this" {
  count = local.create_option_group ? 1 : 0

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
