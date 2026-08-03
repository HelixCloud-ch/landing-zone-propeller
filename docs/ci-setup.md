# CI setup

Configure GitHub Actions to run plans and applies from the consumer repo. Once
in place, the pipeline can be triggered through the workflow UI.

The CI user only needs permissions to upload the bundle to S3 and invoke the
Autopilot Lambda.

## 1. Create the CI user

Run from CloudShell in the management account. It resolves the Operations
account, assumes into it, creates the CI user, and prints all values needed for
GitHub.

```bash
# --- Configuration (edit this) ---
REGION="eu-central-2"

# --- Resolve Operations account ---
OPS_ACCOUNT_ID=$(aws organizations list-accounts \
  --query "Accounts[?Name=='Operations' && Status=='ACTIVE'].Id | [0]" \
  --output text)
BUNDLE_BUCKET="source-${OPS_ACCOUNT_ID}-${REGION}-an"
LAMBDA_ARN="arn:aws:lambda:${REGION}:${OPS_ACCOUNT_ID}:function:propeller-autopilot"

# --- Assume role into Operations ---
CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::${OPS_ACCOUNT_ID}:role/AWSControlTowerExecution" \
  --role-session-name "propeller-ci-setup" \
  --query 'Credentials' --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r .AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r .SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r .SessionToken)

# --- Create the CI user ---
aws iam create-user --user-name propeller-ci

aws iam put-user-policy --user-name propeller-ci --policy-name propeller-deploy --policy-document "$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${BUNDLE_BUCKET}/*"
    },
    {
      "Effect": "Allow",
      "Action": "lambda:InvokeFunction",
      "Resource": "${LAMBDA_ARN}:*"
    }
  ]
}
EOF
)"

# --- Generate access keys ---
KEY_OUTPUT=$(aws iam create-access-key --user-name propeller-ci)
CI_ACCESS_KEY_ID=$(echo $KEY_OUTPUT | jq -r '.AccessKey.AccessKeyId')
CI_SECRET_ACCESS_KEY=$(echo $KEY_OUTPUT | jq -r '.AccessKey.SecretAccessKey')

# --- Print values for GitHub ---
cat <<EOF

=== Save these for GitHub ===

Secrets:
  AWS_ACCESS_KEY_ID:     ${CI_ACCESS_KEY_ID}
  AWS_SECRET_ACCESS_KEY: ${CI_SECRET_ACCESS_KEY}

Variables:
  AWS_REGION:              ${REGION}
  PROPELLER_BUNDLE_BUCKET: ${BUNDLE_BUCKET}
  PROPELLER_LAMBDA_ARN:    ${LAMBDA_ARN}
EOF

# --- Clean up session ---
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

## 2. Add GitHub secrets

**Settings > Secrets and Variables > Actions > Secrets > Repository Secrets:**

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

## 3. Add GitHub variables

**Variables > Repository Variables:**

- `AWS_REGION`
- `PROPELLER_BUNDLE_BUCKET`
- `PROPELLER_LAMBDA_ARN`

## 4. Add workflows

Copy the example workflows into `.github/workflows/` and adapt the platform
names in the `options:` lists to match your consumer repo.

| Workflow | Example | Purpose |
|----------|---------|---------|
| Landing zone deploy | [landing-zone-deploy.yml](examples/landing-zone-deploy.yml) | Plan/apply the landing-zone pipeline |
| Landing zone destroy | [landing-zone-destroy-project.yml](examples/landing-zone-destroy-project.yml) | Destroy a single landing-zone project |
| Platform deploy | [platform-deploy.yml](examples/platform-deploy.yml) | Plan/apply a platform pipeline |
| Platform destroy | [platform-destroy-project.yml](examples/platform-destroy-project.yml) | Destroy platform project(s) |
| Platform sleep/wake | [platform-sleep-wake.yml](examples/platform-sleep-wake.yml) | Sleep/wake a platform with presets |

### Workflow features

All deploy workflows include:

- `run-name` for readable execution titles in the Actions UI
- `ONLY` input to target a single project without running the full pipeline
- A summary step that renders the Mermaid pipeline graph in the job summary

Platform deploy adds:

- `supervised` toggle for plan-then-approve-then-apply mode

Sleep/wake adds:

- `sleep_preset` input (required for sleep, auto-resolved on wake from stored
  state)

Destroy workflows add safety gates:

- Typed confirmation (`DESTROY`)
- Checkbox acknowledgment
- 10-second cooldown job between validation and execution
- `ALL` keyword for full platform destroy (sets `DESTROY_ALL=true`)

### How it flows

```
┌──────────────┐     ┌──────────┐     ┌──────────┐     ┌──────────────┐
│ just pull    │────▶│ resolve  │────▶│ bundle   │────▶│ upload to S3 │
└──────────────┘     └──────────┘     └──────────┘     └──────────────┘
                          │                                    │
                          ▼                                    ▼
                   ┌──────────────┐     ┌──────────────────────────────────┐
                   │ Job summary  │     │ Invoke Autopilot Lambda          │
                   │ (Mermaid)    │     │   → CodeBuild per project        │
                   └──────────────┘     └──────────────────────────────────┘
```

The resolve step produces `pipeline.lock.md` (Mermaid graph). The workflow
writes it to the GitHub Actions job summary before invoking the Lambda.

## 5. First deploy

Go to **Actions > Landing Zone - Deploy > Run workflow**. Start with `plan` to
confirm the wiring. The job summary shows the resolved version and pipeline
graph.

## Environment variables reference

| Variable | Purpose |
|----------|---------|
| `PROPELLER_BUNDLE_BUCKET` | S3 bucket for bundles |
| `PROPELLER_LAMBDA_ARN` | Autopilot Lambda ARN |
| `DEPLOY_ACTION` | `plan`, `apply`, `destroy`, `sleep`, `wake` |
| `DEPLOY_MODE` | `autopilot` (default) or `supervised` |
| `ONLY` | Comma-separated project names to target |
| `SLEEP_PRESET` | Preset name for sleep action |
| `DESTROY_ALL` | Set to `true` for full-pipeline destroy (safety gate) |

## What's next

- Customize the pipeline: [customization](customization.md).
- Deploy platforms: [platforms](platforms.md).
- Reference: [pipeline schema](pipeline-schema.md),
  [project structure](project-structure.md).
