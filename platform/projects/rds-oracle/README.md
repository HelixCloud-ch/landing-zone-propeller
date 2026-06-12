# RDS Oracle

Deploys an RDS Oracle instance (SE2 by default) with managed credentials via
Secrets Manager, encrypted storage, and configurable networking.

## What it deploys

- **DB subnet group** from the data tier subnets
- **Security group** with configurable ingress (CIDRs or SG references)
- **RDS Oracle instance** with storage autoscaling
- **Master credentials** auto-managed in Secrets Manager (no plaintext password)

## Pipeline wiring

```yaml
stages:
  - name: database
    steps:
      - project: rds-oracle
        target: workload-account
        depends_on: [vpc]
        inputs:
          - name: vpc.vpc_id
            var: vpc_id
          - name: vpc.subnet_ids
            var: subnet_ids_json
```

The `subnet_ids_json` input is the JSON-encoded map from the VPC project. The
project decodes it and extracts the `data` tier by default (configurable via
`subnet_tier`).

## Consumer tfvars

Only `region`, `identifier`, and `engine_version` are required. Everything else
has sensible defaults:

```hcl
region         = "eu-central-2"
identifier     = "my-oracle-db"
engine_version = "19"

# Access — at least one must be set for connectivity
allowed_cidrs = ["10.0.0.0/8"]

# For testing (allows fast teardown):
# deletion_protection = false
# skip_final_snapshot = true
```

## Retrieving credentials

Via CLI:

```bash
aws secretsmanager get-secret-value \
  --secret-id <master_user_secret_arn> \
  --query SecretString --output text | jq .
```

Returns `{"username": "admin", "password": "..."}`.

Or from the
[Secrets Manager console](https://console.aws.amazon.com/secretsmanager) — find
the secret by its ARN (from the Terraform output `master_user_secret_arn`) and
click **Retrieve secret value**.

## S3 Integration (optional)

Set `enable_s3_integration = true` to create an S3 bucket and IAM role for
Oracle Data Pump / `UTL_FILE` operations. This adds the `S3_INTEGRATION` option
to the instance's option group.

The bucket is named `<identifier>-oracle-data-<account_id>-<region>-an`.

## Additional options

Use `additional_options` to add Oracle features to the module-managed option
group (e.g. native network encryption):

```hcl
additional_options = [
  {
    option_name = "NATIVE_NETWORK_ENCRYPTION"
    settings = [
      { name = "SQLNET.ENCRYPTION_SERVER", value = "REQUIRED" },
      { name = "SQLNET.CRYPTO_CHECKSUM_SERVER", value = "REQUIRED" },
    ]
  }
]
```


## Engine versions

The supported major version for `oracle-se2` is **19**. Oracle 21 is only
available with Enterprise Edition (`oracle-ee`).

Setting `engine_version` to the major number (`"19"`) lets RDS auto-select the
latest patch (Release Update). You can also pin a specific RU, e.g.
`"19.0.0.0.ru-2026-04.rur-2026-04.r1"`.

To list available versions for your region:

```bash
aws rds describe-db-engine-versions \
  --engine oracle-se2 \
  --query 'DBEngineVersions[].EngineVersion' \
  --output table
```

Ref:
[RDS Oracle database versions](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Oracle.Concepts.database-versions.html)
