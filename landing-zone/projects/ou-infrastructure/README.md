# OU – Infrastructure

Creates the **Infrastructure** organizational unit, enrolls it into AWS
Control Tower via `AWSControlTowerBaseline`, and moves the operations
account into it.

This project runs **after** `control-tower` (the landing zone must be
active before an OU can be enrolled).

## What it creates

- An organizational unit named `Infrastructure` under the org root
- An `aws_controltower_baseline` (`AWSControlTowerBaseline`) on the OU,
  which registers it into Control Tower and enrolls all member accounts

## What it does

- Moves the operations account into the new OU via
  `aws organizations move-account` (the account is not managed by
  Terraform — the move is performed via `terraform_data` + `local-exec`,
  the account is never imported into state)

## Inputs (from pipeline)

| Variable | Source | Description |
|----------|--------|-------------|
| `operations_account_id` | `/accounts.operations.id` | Operations account ID (moved into the new OU) |

## Inputs (from consumer overlay)

| Variable | Default | Description |
|----------|---------|-------------|
| `region` | — | AWS region (must match Control Tower home region) |
| `ou_name` | `"Infrastructure"` | Name of the OU |
| `baseline_version` | `"5.0"` | Initial version of `AWSControlTowerBaseline`. Ignored after first apply (`lifecycle.ignore_changes`) since AWS may bump it. See the [compatibility table](https://docs.aws.amazon.com/controltower/latest/userguide/table-of-baselines.html) |
| `tags` | `{}` | Tags applied via provider `default_tags` to all resources |

## Outputs

| Output | Description |
|--------|-------------|
| `ou_id` | ID of the OU |
| `ou_arn` | ARN of the OU |
| `enabled_baseline_arn` | ARN of the enabled `AWSControlTowerBaseline` on the OU |
| `baseline_version` | Initial baseline version (note: drift not tracked) |

## Notes

- The `AWSControlTowerBaseline` ARN is discovered at apply time via
  `aws controltower list-baselines` (no Terraform data source exists for
  CT baselines)
- The baseline version is **only used on first apply**. AWS sometimes
  upgrades enabled baselines without notice, so we set
  `lifecycle.ignore_changes = [baseline_version]` to avoid spurious diffs
- This project assumes Identity Center is **not** managed by Control Tower
  (the team manages it separately). If you ever need CT-managed Identity
  Center on this OU, the baseline must receive an
  `IdentityCenterEnabledBaselineArn` parameter — not currently supported
- The operations account move is idempotent: if the account is already in
  the target OU, the AWS CLI error is suppressed
