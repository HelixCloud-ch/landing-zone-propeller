# ── OCM credentials ───────────────────────────────────────────────────────────

data "aws_secretsmanager_secret_version" "ocm" {
  secret_id = var.ocm_secret_name
}

locals {
  ocm_credentials = sensitive(jsondecode(data.aws_secretsmanager_secret_version.ocm.secret_string))
}

# ── htpasswd users from Secrets Manager ───────────────────────────────────────

data "aws_secretsmanager_secret_version" "users" {
  secret_id = coalesce(var.users_secret_name, "propeller/rosa/${var.cluster_name}/htpasswd-users")
}

locals {
  users = sensitive(jsondecode(data.aws_secretsmanager_secret_version.users.secret_string))
}

# ── IDP configuration ─────────────────────────────────────────────────────────

locals {
  _users_valid = alltrue([for u in nonsensitive(local.users) : can(u.username) && can(u.password)])
}

resource "terraform_data" "validate_users" {
  lifecycle {
    precondition {
      condition     = local._users_valid
      error_message = "Each entry in the users secret must be an object with 'username' and 'password' keys. Expected format: [{\"username\":\"...\",\"password\":\"...\"}]"
    }
  }
}

module "idp" {
  source  = "terraform-redhat/rosa-hcp/rhcs//modules/idp"
  version = "1.7.3"

  cluster_id = var.cluster_id
  name       = var.idp_name
  idp_type   = "htpasswd"

  htpasswd_idp_users = local.users

  depends_on = [terraform_data.validate_users]
}
