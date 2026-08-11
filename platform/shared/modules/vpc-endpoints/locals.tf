locals {
  # Organization-scoped baseline: allow everything, then deny principals
  # outside the organization. Opt-in via var.organization_id; a caller-supplied
  # policy_json always wins.
  org_baseline_policy = var.organization_id == null ? null : jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAll"
        Effect    = "Allow"
        Principal = "*"
        Action    = "*"
        Resource  = "*"
      },
      {
        Sid       = "DenyOutsideOrganization"
        Effect    = "Deny"
        Principal = "*"
        Action    = "*"
        Resource  = "*"
        Condition = {
          StringNotEquals = {
            "aws:PrincipalOrgID" = var.organization_id
          }
        }
      },
    ]
  })

  # Not coalesce(): both arguments can legitimately be null at once (no
  # organization_id and no per-endpoint policy_json, the common case), and
  # coalesce() errors when every argument is null.
  effective_policy = {
    for k, v in var.endpoints :
    k => v.policy_json != null ? v.policy_json : (
      data.aws_vpc_endpoint_service.this[k].vpc_endpoint_policy_supported ? local.org_baseline_policy : null
    )
  }
}
