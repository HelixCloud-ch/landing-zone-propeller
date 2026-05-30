# org-trusted-access

Runs in the **management account**, `foundation` stage, after `control-tower-prerequisites`.

## What it does

**RAM sharing with AWS Organizations** — allows RAM shares to target OU ARNs without per-account invitations. Creates the `AWSServiceRoleForResourceAccessManager` service-linked role. Required by `network-tgw` and any future project that shares resources with workload OUs via RAM.

Use `aws_ram_sharing_with_organization`, not `aws_organizations_organization.aws_service_access_principals = ["ram.amazonaws.com"]` — the latter does not create the service-linked role.

If already enabled manually, import before the first apply:
```bash
terraform import aws_ram_sharing_with_organization.this <management-account-id>
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
