# Control Tower

Enables AWS Control Tower by calling the `CreateLandingZone` API via the
`aws_controltower_landing_zone` Terraform resource (manifest v4.0).

This project runs **after** `control-tower-prerequisites` (which creates the
Security OU, accounts, and IAM roles).

## What it creates

- A Control Tower landing zone (v4.0 manifest)
- AWS Config integration (delegated to the Security Tooling account)
- Security Roles integration
- Optionally: AWS Backup integration
- Optionally: IAM Identity Center access management
- Inheritance drift remediation (enabled by default)

## Inputs (from pipeline)

| Variable | Source | Description |
|----------|--------|-------------|
| `log_archive_account_id` | `/accounts.log-archive.id` | Log Archive account ID |
| `security_tooling_account_id` | `/accounts.audit.id` | Security Tooling account ID |
| `backup_admin_account_id` | `/accounts.backup-admin.id` | Backup Admin account ID (empty if unused) |
| `backup_central_account_id` | `/accounts.backup-central.id` | Central Backup account ID (empty if unused) |

## Inputs (from consumer overlay)

| Variable | Default | Description |
|----------|---------|-------------|
| `region` | — | AWS region (must match Identity Center region) |
| `governed_regions` | — | Regions governed by CT (include `us-east-1` for global services) |
| `landing_zone_version` | `"4.0"` | Only `"4.0"` is supported |
| `enable_backup` | `false` | Enable AWS Backup integration |
| `backup_kms_key_arn` | `""` | KMS key ARN for backup (required when backup enabled) |
| `enable_access_management` | `false` | Let CT manage IAM Identity Center |
| `enable_inheritance_drift_remediation` | `true` | Auto-remediate inheritance drift |
| `logging_bucket_retention_days` | `365` | Retention for the centralized logging bucket |
| `access_logging_bucket_retention_days` | `365` | Retention for the access logging bucket |
| `tags` | `{}` | Tags applied via provider `default_tags` to all resources |

## Notes

- CT deployment takes ~60 minutes on first apply
- The `governed_regions` list should almost always include `us-east-1`
  (global services like IAM and Organizations operate there)
- **Region ordering matters to avoid perpetual Terraform drift.** The CT API
  returns `governedRegions` in the order it stored them at creation time. If
  the list in `config.auto.tfvars` differs from that order, Terraform detects a
  change on every plan and proposes a ~45-minute in-place update even though
  nothing actually changed. This is a known provider bug
  ([hashicorp/terraform-provider-aws#35763](https://github.com/hashicorp/terraform-provider-aws/issues/35763))
  that is not yet fixed. To avoid it, declare the regions in the exact order the
  API uses: `us-east-1` first, then the CT home region (if different), then any
  additional regions. This matches the order observed in the API response across
  multiple reported cases. Once the bug is fixed (PR
  [#44902](https://github.com/hashicorp/terraform-provider-aws/pull/44902)), the
  provider will normalise the order automatically.
- When `enable_backup = true`, both backup account IDs and the KMS key ARN
  are required
- The v4.0 manifest no longer includes `organizationStructure` — customers
  manage their own OU layout (done in `control-tower-prerequisites`)
- Tags are managed via the provider's `default_tags` block — they apply
  automatically to all resources in the project without per-resource `tags`
  arguments
