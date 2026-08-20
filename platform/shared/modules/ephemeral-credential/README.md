# ephemeral-credential

Manages a storage credential via AWS Secrets Manager or SSM Parameter Store,
producing **ephemeral outputs** that never touch Terraform state or plan.

## Interface

Set exactly **one** of these four variables to select backend and mode:

| Variable | Backend | Mode | Behaviour |
|----------|---------|------|-----------|
| `secret_name` | Secrets Manager | create | Generates credential, creates secret |
| `secret_arn` | Secrets Manager | read | Reads existing secret ephemerally |
| `parameter_name` | SSM Parameter Store | create | Generates credential, creates SecureString |
| `parameter_arn` | SSM Parameter Store | read | Reads existing parameter ephemerally |

A cross-variable validation ensures exactly one is provided.

## Credential format

When `username` is set, the stored value is a JSON object matching the
RDS managed secret convention:

```json
{"username":"appadm7bk2m3x","password":"generated-password-here"}
```

The username is `{prefix}{random_suffix}` — the caller controls any separator
by including it in the prefix (e.g. `prefix = "app_"` or `prefix = "svc"`).
No separator is inserted by the module.

When `username` is null, only the plain password string is stored.

## Generation parameters

Both `password` and `username` are objects with full control over the random
generation:

```hcl
password = {
  length                     = 32
  exclude_characters         = "/@\"\\'"
  exclude_punctuation        = false
  require_each_included_type = true
}

username = {
  prefix              = "app"    # prefix is concatenated directly to the random suffix
  length              = 8        # suffix length
  exclude_uppercase   = true     # default: only lowercase + numbers
  exclude_punctuation = true
}
```

## Password rotation

Bump `password_version` to rotate. This triggers:

1. New random password (and username) generation.
2. Write to the backend (write-only, never in state).
3. Downstream consumers tied to `password_version` update atomically.

## Usage — full credential with generated username

```hcl
module "db_credential" {
  source      = "../../../shared/modules/ephemeral-credential"
  secret_name = "platform/myapp/rds-master"

  username = {
    prefix = "app"
    length = 8
  }

  password = {
    length = 32
  }

  password_version = 1
  kms_key_id       = "arn:aws:kms:eu-west-1:123456789012:key/abcd-1234"
}

module "rds_postgresql" {
  source              = "../../../shared/modules/rds-postgresql"
  username            = module.db_credential.username
  password            = module.db_credential.password
  password_wo_version = module.db_credential.password_version
}
```

## Usage — password only (no username generation)

```hcl
module "db_credential" {
  source           = "../../../shared/modules/ephemeral-credential"
  secret_name      = "platform/myapp/rds-password"
  password_version = 1
}

module "rds_postgresql" {
  source              = "../../../shared/modules/rds-postgresql"
  username            = "dbadmin"
  password            = module.db_credential.password
  password_wo_version = module.db_credential.password_version
}
```

## Usage — read existing secret

```hcl
module "db_credential" {
  source     = "../../../shared/modules/ephemeral-credential"
  secret_arn = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:my-db-AbCdEf"
  username   = {}  # signals the stored value is JSON, parse it
}
```

## Usage — SSM Parameter Store

```hcl
module "db_credential" {
  source         = "../../../shared/modules/ephemeral-credential"
  parameter_name = "/platform/myapp/rds-master"

  username = {
    prefix = "svc"
    length = 6
  }

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
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_secretsmanager_secret.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_ssm_parameter.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_description"></a> [description](#input\_description) | Description for the created secret or parameter. | `string` | `null` | no |
| <a name="input_kms_key_id"></a> [kms\_key\_id](#input\_kms\_key\_id) | KMS key ARN or alias for encryption. Uses the service default<br/>key (aws/secretsmanager or aws/ssm) if null. | `string` | `null` | no |
| <a name="input_parameter_arn"></a> [parameter\_arn](#input\_parameter\_arn) | ARN of an EXISTING SSM parameter to read. | `string` | `null` | no |
| <a name="input_parameter_name"></a> [parameter\_name](#input\_parameter\_name) | Full path (starting with /) for a NEW SSM SecureString parameter to create. | `string` | `null` | no |
| <a name="input_password"></a> [password](#input\_password) | Password generation parameters. | <pre>object({<br/>    length                     = optional(number, 28)<br/>    exclude_characters         = optional(string, "/@\"\\'\n")<br/>    exclude_lowercase          = optional(bool, false)<br/>    exclude_numbers            = optional(bool, false)<br/>    exclude_punctuation        = optional(bool, false)<br/>    exclude_uppercase          = optional(bool, false)<br/>    include_space              = optional(bool, false)<br/>    require_each_included_type = optional(bool, true)<br/>  })</pre> | `{}` | no |
| <a name="input_password_version"></a> [password\_version](#input\_password\_version) | Rotation trigger. Bump to generate and store new credentials. | `number` | `1` | no |
| <a name="input_secret_arn"></a> [secret\_arn](#input\_secret\_arn) | ARN of an EXISTING Secrets Manager secret to read. | `string` | `null` | no |
| <a name="input_secret_name"></a> [secret\_name](#input\_secret\_name) | Friendly name for a NEW Secrets Manager secret to create. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to the created resource (create modes only). | `map(string)` | `{}` | no |
| <a name="input_username"></a> [username](#input\_username) | When set, the stored value becomes JSON {"username":"...","password":"..."}.<br/>The username is built as prefix concatenated with a random suffix of the<br/>given length. Defaults produce lowercase alphanumeric suffixes.<br/>Set to null to store only a plain password string. | <pre>object({<br/>    prefix              = optional(string, "usr")<br/>    length              = optional(number, 8)<br/>    exclude_characters  = optional(string, "")<br/>    exclude_numbers     = optional(bool, false)<br/>    exclude_lowercase   = optional(bool, false)<br/>    exclude_uppercase   = optional(bool, true)<br/>    exclude_punctuation = optional(bool, true)<br/>    include_space       = optional(bool, false)<br/>  })</pre> | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_credential_json"></a> [credential\_json](#output\_credential\_json) | The full stored value as a string. When username is configured this is<br/>JSON {"username":"...","password":"..."}. Ephemeral. |
| <a name="output_password"></a> [password](#output\_password) | The password value. Ephemeral: never persisted in state or plan. |
| <a name="output_password_version"></a> [password\_version](#output\_password\_version) | Current password version. Pass to downstream password\_wo\_version arguments. |
| <a name="output_secret_arn"></a> [secret\_arn](#output\_secret\_arn) | ARN of the Secrets Manager secret or SSM parameter. |
| <a name="output_username"></a> [username](#output\_username) | The generated username. Ephemeral. Null when username is not configured. |
<!-- END_TF_DOCS -->
