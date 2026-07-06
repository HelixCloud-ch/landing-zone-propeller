locals {
  s3_option = var.enable_s3_integration ? [{
    option_name = "S3_INTEGRATION"
    version     = "1.0"
    port        = null
    settings    = []
  }] : []

  jvm_option = var.enable_jvm ? [{
    option_name = "JVM"
    version     = null
    port        = null
    settings    = []
  }] : []

  all_options = concat(local.s3_option, local.jvm_option, var.additional_options)
}
