# Control Tower Prerequisites

Creates the prerequisite resources required before enabling AWS Control Tower
via the `CreateLandingZone` API (or `aws_controltower_landing_zone` Terraform
resource).

## What it creates

All resources are optional except the Security OU.

| Resource | Controlled by | Default |
|---|---|---|
| Security OU | always created | — |
| Log Archive account | `LOG_ARCHIVE_EMAIL` set | skipped |
| Security Tooling account | `AUDIT_EMAIL` set | skipped |
| Backup Admin account | `BACKUP_ADMIN_EMAIL` + `BACKUP_CENTRAL_EMAIL` both set | skipped |
| Central Backup account | `BACKUP_ADMIN_EMAIL` + `BACKUP_CENTRAL_EMAIL` both set | skipped |
| 4 CT IAM service roles | `CREATE_IAM_ROLES=true` | created |

The 4 IAM service roles are:
- `AWSControlTowerAdmin` — inline policy + `AWSControlTowerServiceRolePolicy`
- `AWSControlTowerCloudTrailRole` — `AWSControlTowerCloudTrailRolePolicy`
- `AWSControlTowerStackSetRole` — inline policy (AssumeRole → AWSControlTowerExecution)
- `AWSControlTowerConfigAggregatorRoleForOrganizations` — `AWSConfigRoleForOrganizations`

## Account naming rationale

### "Security Tooling" instead of "Audit"

CT names this account "Audit" by default, but the AWS SRA and the AWS
multi-account strategy whitepaper call it **"Security Tooling (Audit)"**,
noting that "Audit" is just the CT default name.

The account is the delegated administrator for Security Hub, GuardDuty,
Config, Macie, IAM Access Analyzer, Firewall Manager, Detective, Audit
Manager, Inspector, and CloudTrail — it is a security operations hub, not
merely an audit account. "Security Tooling" better reflects this role.

References:
- [AWS SRA — Security Tooling account](https://docs.aws.amazon.com/prescriptive-guidance/latest/security-reference-architecture/security-tooling.html):
  "AWS Control Tower names the account under the Security OU the *Audit Account* by default. You can rename the account during the AWS Control Tower setup."
- [Organizing Your AWS Environment — Foundational OUs](https://docs.aws.amazon.com/whitepapers/latest/organizing-your-aws-environment/foundational-ous.html):
  Uses "Security Tooling (Audit)" throughout, explicitly noting CT's default is "Audit".
- [CT configure shared accounts](https://docs.aws.amazon.com/controltower/latest/userguide/configure-shared-accounts.html):
  "Many customers choose to call [the audit account] the **Security** account."

CT identifies accounts by account ID in the manifest, not by name — the
name is purely organizational.

### "Log Archive"

Consistent across CT console defaults, AWS SRA, and the multi-account
whitepaper. No change needed.

## Backup accounts

The backup accounts are required only if you plan to enable the AWS Backup
integration in the CT v3.3 manifest (`backup.enabled: true`). They map to
`backup.configurations.backupAdmin.accountId` and
`backup.configurations.centralBackup.accountId` in the manifest.

### What each account does

**Backup Administrator account** — the control plane for backup operations.
It is the delegated administrator for AWS Backup across the org. It stores
Backup Audit Manager (BAM) report plans and aggregates all monitoring data
(restore jobs, copy jobs) in an S3 bucket.

**Central Backup account** — the data plane. It stores the actual backup
vaults and cross-account backup copies. Keeping backups here means that if
a workload account is compromised, the backup data is safe in a separate
account.

### Can you use the same account for both?

The CT prerequisites docs say "two other AWS accounts" and the AWS blog
post says "two specialized accounts" — the separation is intentional and
a security best practice. The CT v3.3 schema has two distinct `accountId`
fields. Technically you can pass the same account ID for both, but it
defeats the purpose: the separation ensures that a compromise of one
account does not affect the other.

For small or non-production setups, using a single account is possible.
For production, use two separate accounts.

References:
- [CT backup prerequisites](https://docs.aws.amazon.com/controltower/latest/userguide/backup-prerequisites.html)
- [Build centralized cross-Region backup architecture with CT](https://aws.amazon.com/blogs/storage/build-centralized-cross-region-backup-architecture-with-aws-control-tower/)

## Required inputs

| Variable | Default | Description |
|---|---|---|
| `LOG_ARCHIVE_EMAIL` | *(empty)* | Root email for the Log Archive account (optional) |
| `AUDIT_EMAIL` | *(empty)* | Root email for the Security Tooling account (optional) |
| `BACKUP_ADMIN_EMAIL` | *(empty)* | Root email for the Backup Admin account (optional) |
| `BACKUP_CENTRAL_EMAIL` | *(empty)* | Root email for the Central Backup account (optional) |
| `CREATE_IAM_ROLES` | `true` | Set to `false` to skip IAM role creation (e.g. roles already exist) |
| `ACTION` | `plan` | `plan` or `apply` |

Each account is created only when its email is provided. Backup accounts
require **both** emails to be set — if either is empty, both are skipped.

Set `CREATE_IAM_ROLES=false` when:
- A previous CT installation already created the roles
- You are re-running this project after a partial failure where roles were created
- The customer already has an existing CT setup and only needs the accounts

## Deploy

This project targets the MPA account. The SFN in the Operations account
triggers the MPA deploy-runner via cross-account assume role.

The SFN must be invoked from the Operations account (either directly or by
assuming a role into it). The inline buildspec downloads the repo zip and
runs the deploy script.

```bash
# Required variables — set these before running
TARGET_REGION=eu-central-2
MPA_ACCOUNT_ID=123456789012
SFN_ARN="arn:aws:states:${TARGET_REGION}:${OPERATION_ACCOUNT_ID}:stateMachine:landing-zone-propeller-sfn"
LZP_ZIP_URL="https://github.com/HelixCloud-ch/landing-zone-propeller/archive/refs/heads/main.zip"

# Plan
aws stepfunctions start-execution \
  --region "$TARGET_REGION" \
  --state-machine-arn "$SFN_ARN" \
  --input "{
    \"account_id\": \"${MPA_ACCOUNT_ID}\",
    \"buildspec\": \"version: 0.2\nphases:\n  build:\n    commands:\n      - curl -sL \\\"\$LZP_ZIP_URL\\\" -o /tmp/lzp.zip\n      - unzip -qo /tmp/lzp.zip -d /tmp/lzp\n      - |\n        cd /tmp/lzp/landing-zone-propeller-*\n        chmod +x projects/management/control-tower-prerequisites/scripts/deploy-ct-prereqs.sh\n        ./projects/management/control-tower-prerequisites/scripts/deploy-ct-prereqs.sh\",
    \"env_overrides\": [
      {\"Name\": \"LZP_ZIP_URL\", \"Value\": \"${LZP_ZIP_URL}\", \"Type\": \"PLAINTEXT\"},
      {\"Name\": \"LOG_ARCHIVE_EMAIL\", \"Value\": \"log@example.com\", \"Type\": \"PLAINTEXT\"},
      {\"Name\": \"AUDIT_EMAIL\", \"Value\": \"security-tooling@example.com\", \"Type\": \"PLAINTEXT\"}
    ]
  }"

# Apply — add ACTION=apply to env_overrides
aws stepfunctions start-execution \
  --region "$TARGET_REGION" \
  --state-machine-arn "$SFN_ARN" \
  --input "{
    \"account_id\": \"${MPA_ACCOUNT_ID}\",
    \"buildspec\": \"version: 0.2\nphases:\n  build:\n    commands:\n      - curl -sL \\\"\$LZP_ZIP_URL\\\" -o /tmp/lzp.zip\n      - unzip -qo /tmp/lzp.zip -d /tmp/lzp\n      - |\n        cd /tmp/lzp/landing-zone-propeller-*\n        chmod +x projects/management/control-tower-prerequisites/scripts/deploy-ct-prereqs.sh\n        ./projects/management/control-tower-prerequisites/scripts/deploy-ct-prereqs.sh\",
    \"env_overrides\": [
      {\"Name\": \"LZP_ZIP_URL\", \"Value\": \"${LZP_ZIP_URL}\", \"Type\": \"PLAINTEXT\"},
      {\"Name\": \"LOG_ARCHIVE_EMAIL\", \"Value\": \"log@example.com\", \"Type\": \"PLAINTEXT\"},
      {\"Name\": \"AUDIT_EMAIL\", \"Value\": \"security-tooling@example.com\", \"Type\": \"PLAINTEXT\"},
      {\"Name\": \"ACTION\", \"Value\": \"apply\", \"Type\": \"PLAINTEXT\"}
    ]
  }"
```

## Skipping for existing environments

If a customer already has the Security OU and the required accounts, skip
this project entirely.

## Notes

- Accounts have `prevent_destroy = true` — Terraform will refuse to destroy them
- `close_on_deletion = false` — removing from state only detaches, does not close
- IAM role names are fixed by AWS (not configurable)
- All roles use the `/service-role/` IAM path as required by CT
