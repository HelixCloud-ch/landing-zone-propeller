# org-trusted-access

Runs in the **management account**, `foundation` stage. No dependencies.

## What it does

**RAM sharing with AWS Organizations** — allows RAM shares to target OU ARNs without per-account invitations. Creates the `AWSServiceRoleForResourceAccessManager` service-linked role. Required by `network-tgw` and any future project that shares resources with workload OUs via RAM.

Use `aws_ram_sharing_with_organization`, not `aws_organizations_organization.aws_service_access_principals = ["ram.amazonaws.com"]` — the latter does not create the service-linked role.

If RAM org-sharing was already enabled manually, add an import block to the consumer overlay before the first apply:

```hcl
# landing-zone/projects/org-trusted-access/terraform/imports.tf (consumer repo)
import {
  to = aws_ram_sharing_with_organization.this[0]
  id = "<management-account-id>"
}
```

**Trusted access for AWS services** — enables org-wide integration for services listed in `trusted_service_principals` (default: empty). Each entry creates one `aws_organizations_aws_service_access` resource.

> **Note:** AWS recommends enabling trusted access through the service's own console or CLI, because some services run extra setup steps on enable. Use this variable only for services that don't have a dedicated Terraform resource for their org integration. Services like Control Tower and Service Catalog manage their own trusted access.

## Example: Security Hub

When the `security-hub` project is added, set:

```hcl
# config.auto.tfvars (consumer repo)
trusted_service_principals = ["securityhub.amazonaws.com"]
```

This is the prerequisite for `aws_securityhub_organization_admin_account` (delegated admin designation), which lives in the `security-hub` project, not here.

## What does NOT belong here

- Delegated administrator assignments — those go in the service-specific project.
- Control Tower, Service Catalog — they manage their own trusted access.
- RAM — handled by `aws_ram_sharing_with_organization`, not `aws_organizations_aws_service_access`.

## References

- [AWS services that work with Organizations](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_integrate_services_list.html)
- [Using trusted access with AWS Organizations](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_integrate_services.html)
- [RAM — Enable sharing with AWS Organizations](https://docs.aws.amazon.com/ram/latest/userguide/getting-started-sharing.html)
- [Security Hub — Designating a delegated administrator](https://docs.aws.amazon.com/securityhub/latest/userguide/designate-orgs-admin-account.html)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | 6.41.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.41.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_organizations_aws_service_access.this](https://registry.terraform.io/providers/hashicorp/aws/6.41.0/docs/resources/organizations_aws_service_access) | resource |
| [aws_ram_sharing_with_organization.this](https://registry.terraform.io/providers/hashicorp/aws/6.41.0/docs/resources/ram_sharing_with_organization) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_enable_ram_org_sharing"></a> [enable\_ram\_org\_sharing](#input\_enable\_ram\_org\_sharing) | Enable RAM sharing with AWS Organizations. Required before any RAM share can target OU ARNs without per-account invitations. | `bool` | `true` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region for the management account provider. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_trusted_service_principals"></a> [trusted\_service\_principals](#input\_trusted\_service\_principals) | Service principals to enable for trusted access with AWS Organizations.<br/>Each entry maps to one aws\_organizations\_aws\_service\_access resource.<br/><br/>Example:<br/>  trusted\_service\_principals = ["securityhub.amazonaws.com"]<br/><br/>Full list of supported principals:<br/>https://docs.aws.amazon.com/organizations/latest/userguide/orgs_integrate_services_list.html | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_ram_sharing_enabled"></a> [ram\_sharing\_enabled](#output\_ram\_sharing\_enabled) | Management account ID if RAM org-sharing is enabled, empty string otherwise. |
| <a name="output_trusted_service_principals"></a> [trusted\_service\_principals](#output\_trusted\_service\_principals) | Set of service principals for which trusted access was enabled. |
<!-- END_TF_DOCS -->