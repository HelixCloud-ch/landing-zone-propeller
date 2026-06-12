locals {
  # Create a module-managed option group when any options are needed
  # and no external option group is provided
  create_option_group = var.option_group_name == null && (var.enable_s3_integration || length(var.additional_options) > 0)

  s3_option = var.enable_s3_integration ? [{
    option_name = "S3_INTEGRATION"
    version     = "1.0"
    port        = null
    settings    = []
  }] : []

  all_options = concat(local.s3_option, var.additional_options)
}
