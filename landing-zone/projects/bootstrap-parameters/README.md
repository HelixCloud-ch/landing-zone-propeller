# bootstrap-parameters

Runs in the **management account**, `foundation` stage (no `depends_on` — runs in parallel with `control-tower-prerequisites` etc.).

Resolves bootstrap-time values that are needed by downstream projects but are not produced by bootstrap scripts:

| Output | Description |
|--------|-------------|
| `portfolio_id` | ID of the Service Catalog portfolio created by `bootstrap/scripts/create-portfolio.sh` (e.g. `port-xxxx`). |
| `product_id` | ID of the `deploy-runner` Service Catalog product (e.g. `prod-xxxx`). |
| `artifact_id` | ID of the latest active DEFAULT provisioning artifact (e.g. `pa-xxxx`). This is the version that will be deployed. Changes when a new artifact is published and the pipeline re-runs. |
| `s3_source_bucket` | Name of the source S3 bucket in Operations (`source-{id}-{region}`). |
| `autopilot_role_arn` | Full ARN of `propeller-autopilot-role` in the operations account. Used as `CallerARN` when provisioning the deploy-runner product. |

## Inputs

| Variable | Source | Description |
|----------|--------|-------------|
| `PROPELLER_INPUT_operations_account_id` | SSM `/accounts.operations.id` | Operations account ID, seeded by `bootstrap/scripts/deploy-autopilot.sh`. |
| `PROPELLER_INPUT_portfolio_display_name` | consumer tfvars (default: `landing-zone-propeller`) | Display name of the Service Catalog portfolio. Override only if changed at bootstrap. |
| `PROPELLER_INPUT_product_name` | consumer tfvars (default: `deploy-runner`) | Name of the Service Catalog product. Override only if changed at bootstrap. |
| `PROPELLER_INPUT_source_bucket_prefix` | consumer tfvars (default: `source`) | Prefix for the source S3 bucket name. Matches `SOURCE_BUCKET_PREFIX` in `bootstrap/scripts/create-source-bucket.sh`. |
| `PROPELLER_INPUT_autopilot_role_name` | consumer tfvars (default: `propeller-autopilot-role`) | Name of the autopilot IAM role. Matches `CALLER_ROLE_NAME` in `bootstrap/scripts/provision-product-operations.sh`. |

## Version update behaviour

`artifact_id` is resolved at every pipeline run by selecting the latest active DEFAULT
artifact (`sort_by(@, &CreatedTime) | [-1]`). When a new version of the `deploy-runner`
product is published in Service Catalog:

1. Re-run the pipeline (or just the `bootstrap-parameters` + `network-deploy-runner` steps).
2. `bootstrap-parameters` picks up the new `artifact_id`.
3. `network-deploy-runner` receives the changed `provisioning_artifact_id` input.
4. Terraform calls `update-provisioned-product` in the Network account, rolling out the new version.

No manual `aws servicecatalog update-provisioned-product` invocation needed. The pipeline
controls when updates happen — re-running on demand is the trigger.

## Why a script project

The portfolio and product IDs are created by the bootstrap shell scripts and are not in the
pipeline's SSM namespace. A script project is the right primitive: a few CLI calls resolve
the IDs by name and write them to `.propeller-outputs.json`.

## What does NOT belong here

- Resolving the operations account ID via Organizations — it is already seeded at
  `/propeller/accounts/operations/id` by `bootstrap/scripts/deploy-autopilot.sh`.
- Any write operations — this project is read-only.
