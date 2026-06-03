provider "aws" {
  region = var.region

  default_tags {
    # Autopilot is currently deployed outside the pipeline, so framework tags
    # are hardcoded here rather than injected by the engine.
    tags = merge(
      var.tags,
      {
        "propeller:pipeline"           = "bootstrap"
        "propeller:project"            = "autopilot"
        "propeller:cost-center"        = "propeller"
        "propeller:deploy-type"        = "terraform"
        "propeller:framework-required" = "true"
      },
    )
  }
}
