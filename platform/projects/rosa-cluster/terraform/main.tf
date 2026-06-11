# ── Subnet decoding ───────────────────────────────────────────────────────────

locals {
  subnets_by_tier    = jsondecode(var.subnet_ids_json)
  private_subnet_ids = local.subnets_by_tier[var.private_subnet_tier]
  public_subnet_ids  = try(local.subnets_by_tier[var.public_subnet_tier], [])
}

# ── OCM credentials from Secrets Manager (ephemeral — never stored in state) ──

ephemeral "aws_secretsmanager_secret_version" "ocm" {
  secret_id = var.ocm_secret_name
}

locals {
  ocm_credentials = jsondecode(ephemeral.aws_secretsmanager_secret_version.ocm.secret_string)
}

# ── ROSA HCP cluster ──────────────────────────────────────────────────────────

module "rosa_hcp" {
  source  = "terraform-redhat/rosa-hcp/rhcs"
  version = "1.7.3"

  cluster_name           = var.cluster_name
  openshift_version      = var.openshift_version
  machine_cidr           = var.machine_cidr
  private                = var.private
  aws_subnet_ids         = var.private ? local.private_subnet_ids : concat(local.private_subnet_ids, local.public_subnet_ids)
  aws_availability_zones = var.availability_zones
  aws_billing_account_id = var.aws_billing_account_id
  replicas               = var.replicas
  compute_machine_type   = var.compute_machine_type

  create_account_roles  = true
  account_role_prefix   = "${var.cluster_name}-account"
  create_oidc           = true
  create_operator_roles = true
  operator_role_prefix  = "${var.cluster_name}-operator"

  create_admin_user = var.create_admin_user

  tags = var.tags
}

# ── Store admin credentials in Secrets Manager ────────────────────────────────

resource "aws_secretsmanager_secret" "cluster_admin" {
  count = var.create_admin_user ? 1 : 0

  name        = "propeller/rosa/${var.cluster_name}/admin"
  description = "ROSA cluster admin credentials for ${var.cluster_name}"

  # Immediate deletion avoids name conflicts on destroy/recreate cycles
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "cluster_admin" {
  count = var.create_admin_user ? 1 : 0

  secret_id = aws_secretsmanager_secret.cluster_admin[0].id
  secret_string = jsonencode({
    username    = module.rosa_hcp.cluster_admin_username
    password    = module.rosa_hcp.cluster_admin_password
    api_url     = module.rosa_hcp.cluster_api_url
    console_url = module.rosa_hcp.cluster_console_url
  })
}
