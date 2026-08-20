# ephemeral-credential

Manages a storage credential via AWS Secrets Manager or SSM Parameter Store,
producing **ephemeral outputs** that never touch Terraform state or plan.

## Interface

Set exactly **one** of these four variables to select backend and mode:

| Variable | Backend | Mode | Behaviour |
|----------|---------|------|-----------|
| `secret_name` | Secrets Manager | create | Generates password, creates secret |
| `secret_arn` | Secrets Manager | read | Reads existing secret ephemerally |
| `parameter_name` | SSM Parameter Store | create | Generates password, creates SecureString |
| `parameter_arn` | SSM Parameter Store | read | Reads existing parameter ephemerally |

A cross-variable validation ensures exactly one is provided.

## Credential format

When `username` is set, the stored value is a JSON object matching the
RDS managed secret convention:

```json
{"username":"dbadmin","password":"generated-password-here"}
```

When `username` is null, only the plain password string is stored.

## Password generation

The `password` variable is an object with full control over generation:

```hcl
password = {
  length                     = 32
  exclude_characters         = "/@\"\\'"
  exclude_punctuation        = false
  require_each_included_type = true
}
```

## Password rotation

Bump `password_version` to rotate:

1. New random password generation.
2. Write to the backend (write-only, never in state).
3. Downstream consumers tied to `password_version` update atomically.

## Usage — create with username (Secrets Manager)

```hcl
module "db_credential" {
  source      = "../../../shared/modules/ephemeral-credential"
  secret_name = "platform/myapp/rds-master"
  username    = "dbadmin"

  password = {
    length = 32
  }

  password_version = 1
  kms_key_id       = "arn:aws:kms:eu-west-1:123456789012:key/abcd-1234"
}

module "rds_postgresql" {
  source              = "../../../shared/modules/rds-postgresql"
  username            = "dbadmin"
  password            = module.db_credential.password
  password_wo_version = module.db_credential.password_version
}
```

## Usage — password only

```hcl
module "db_credential" {
  source           = "../../../shared/modules/ephemeral-credential"
  secret_name      = "platform/myapp/rds-password"
  password_version = 1
}
```

## Usage — read existing secret

```hcl
module "db_credential" {
  source     = "../../../shared/modules/ephemeral-credential"
  secret_arn = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:my-db-AbCdEf"
  username   = "dbadmin"  # tells the module the stored value is JSON
}
```

## Usage — SSM Parameter Store

```hcl
module "db_credential" {
  source           = "../../../shared/modules/ephemeral-credential"
  parameter_name   = "/platform/myapp/rds-master-password"
  password_version = 1
}
```

## Requirements

- Terraform >= 1.14 (ephemeral resources, write-only arguments, cross-variable
  validation)
- AWS provider >= 6.0

## What does NOT belong here

- **RDS `manage_master_user_password` mode** — RDS owns the secret, this
  module is not involved.
- **Rotation Lambda functions** — rotation is manual via `password_version`.
- **Non-password secrets** — scoped to storage credentials.

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
