locals {
  # CreateCustomPlugin rejects "." and "_" in names, and every plugin key
  # carries a dotted version (e.g. "mariadb-2.7.4.Final"), so any character
  # other than a letter, digit or hyphen becomes a hyphen. The map key, and so
  # every output, keeps the original form.
  plugin_names = {
    for k in keys(var.plugins) :
    k => "${var.name_prefix}-${replace(k, "/[^0-9A-Za-z-]/", "-")}"
  }
}
