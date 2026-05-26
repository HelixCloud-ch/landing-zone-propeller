# Base SSO

Creates the four base IAM Identity Center permission sets, the
`aws-identity-operators` group, and pre-assigns the `IdentityOperator`
permission set to that group on the current account. Once a member is added
to the group, they can manage permission set assignments for all other
accounts in the organization.

## Resources created

| Type | Name | Purpose |
|---|---|---|
| Permission set | `ReadOnly` | `arn:aws:iam::aws:policy/ReadOnlyAccess` |
| Permission set | `PowerUser` | `arn:aws:iam::aws:policy/PowerUserAccess` |
| Permission set | `Admin` | `arn:aws:iam::aws:policy/AdministratorAccess` |
| Permission set | `IdentityOperator` | Custom — manage assignments, no permission-set CRUD |
| Group (local mode) | `aws-identity-operators` | Members get `IdentityOperator` |
| Account assignment | `IdentityOperator` × `aws-identity-operators` × current account | Bootstraps the operator role |

The other three groups (`aws-admins`, `aws-powerusers`, `aws-readonly-users`)
are **NOT** created here — IdentityOperators members create them at runtime
(in local mode) or they are SCIM-synced from the IdP (in external mode).
This project deliberately keeps a minimal scope.

## IdentityOperator permissions

Allowed:

- Read everything in IAM Identity Center (`AWSSSOReadOnly`)
- Local mode: full directory admin (`AWSSSODirectoryAdministrator`) — can
  create/edit/delete users, groups, and memberships
- External-IdP mode: directory read-only (`AWSSSODirectoryReadOnly`) — must
  use SCIM-synced users/groups, cannot edit them locally
- Assign existing permission sets to AWS accounts for users **and** groups
  (`sso:CreateAccountAssignment` accepts both `principal_type=USER` and
  `principal_type=GROUP`)
- Associate/disassociate profiles via the legacy `sso:AssociateProfile` /
  `sso:DisassociateProfile` actions — needed by the IC console flows that
  delete groups with active assignments
- Manage the IAM roles IC creates in target accounts on assignment
- Add and remove members of the `aws-identity-operators` group (needed to
  onboard new operators)

Denied:

- Creating, modifying, or deleting permission sets (no `sso:CreatePermissionSet`
  or `sso:UpdatePermissionSet` in the policy — `AWSSSOReadOnly` only allows
  reads on permission sets)

If an operator accidentally removes the management-account bootstrap
assignment (or removes themselves from the group with no other members
left), recovery is a re-apply of this Terraform project. KISS.

## Identity source modes

| `external_idp` | Group source | IdentityOperator directory access |
|---|---|---|
| `false` (default) | Group created by Terraform | Full admin (CRUD on users, groups, memberships, MFA) |
| `true` | Group looked up via `aws_identitystore_group` data source — must already be SCIM-provisioned | Read-only (writes would be overwritten by SCIM sync) |

AWS does not expose the identity source in any describe/list API, so the
mode is set explicitly via this variable rather than autodetected.

## Inputs (from consumer overlay)

| Variable | Default | Description |
|---|---|---|
| `region` | — | AWS region (must match the IAM Identity Center home region) |
| `external_idp` | `false` | Whether IAM Identity Center is fed by an external IdP via SCIM |
| `identity_operators_group_name` | `"aws-identity-operators"` | Name of the IdentityOperators group |
| `session_duration` | `"PT1H"` | Session duration for all permission sets (ISO 8601) |
| `tags` | `{}` | Tags applied via provider `default_tags` to all resources |

## Outputs

| Output | Description |
|---|---|
| `permission_set_arns` | Map of permission set name → ARN |
| `identity_operators_group_id` | Identity Store ID of the `aws-identity-operators` group |
| `instance_arn` | ARN of the IAM Identity Center instance |
| `identity_store_id` | Identity Store ID |

## Notes and limitations

- **Runs in the management account today**. The IAM Identity Center
  instance lives in the management account by AWS design. If IC
  administration is later delegated to a member account, the
  pre-assignment to the management account would have to move to a separate
  resource with a management-account provider — delegated admins **cannot**
  assign permission sets to the management account itself
- **First member must be added manually**. Terraform creates the group and
  the assignment but does not add anyone to the group. Add the first
  user (typically the platform admin) via the IC console or CLI after the
  first apply, then they can manage everything else
- **Permission boundary** is not yet attached. Backlog item — would harden
  the cap on what IdentityOperators can do via the IAM roles they create
- **External IdP setup** (SAML metadata exchange, SCIM token generation)
  is fully manual — AWS does not expose these via API or CLI. See the
  bootstrap runbook in the wiki

## Sources

- [Delegate permission set administration](https://docs.aws.amazon.com/singlesignon/latest/userguide/permissionsetdelegation.html) — tag-based delegation pattern
- [Delegating permission set management blog](https://aws.amazon.com/blogs/security/delegating-permission-set-management-and-account-assignment-in-aws-iam-identity-center/) — Use case 3 (tag-based model)
- [Delegated administration best practices](https://docs.aws.amazon.com/singlesignon/latest/userguide/delegated-admin.html) — what delegated admins cannot do
- [Register a member account](https://docs.aws.amazon.com/singlesignon/latest/userguide/delegated-admin-how-to-register.html) — management-account assignment restriction
