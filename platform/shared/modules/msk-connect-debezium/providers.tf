# This module declares no configured `provider "aws"` block: it inherits the
# provider (region, credentials, default_tags) from the calling project. The
# provider requirement itself is declared in versions.tf. The module receives
# `region` as a plain input only because the SSM Config_Provider in the worker
# configuration needs the region as a literal string, not for provider setup.
