# CI setup

Configure GitHub Actions to run plans and applies from the consumer repo. Once
it's in place the pipeline can be triggered through the workflow UI.

The CI user only needs permissions to upload the bundle to S3 and invoke the
Autopilot Lambda. No broad admin access.

## 1. Create the CI user

Run this entire block from CloudShell in the management account. It resolves the
Operations account, assumes into it, creates the CI user, and prints all values
needed for GitHub.

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

In the consumer repo, go to **Settings → Secrets and Variables → Actions →
Secrets (tab) → Repository Secrets (section)** and add:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

## 3. Add GitHub variables

In the same UI, **Variables (tab) → Repository Variables (section)**:

- `AWS_REGION`
- `PROPELLER_BUNDLE_BUCKET`
- `PROPELLER_LAMBDA_ARN`

All values were printed at the end of step 1.

## 4. Add the landing-zone deploy workflow

Create `.github/workflows/deploy-landing-zone.yml`:

```yaml
name: Deploy Landing Zone
on:
  workflow_dispatch:
    inputs:
      action:
        description: "Deploy action"
        required: true
        type: choice
        options:
          - plan
          - apply
        default: apply
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: astral-sh/setup-uv@v7
      - uses: extractions/setup-just@v3
      - run: |
          aws configure set aws_access_key_id "${{ secrets.AWS_ACCESS_KEY_ID }}"
          aws configure set aws_secret_access_key "${{ secrets.AWS_SECRET_ACCESS_KEY }}"
          aws configure set region "${{ vars.AWS_REGION }}"
      - env:
          PROPELLER_BUNDLE_BUCKET: ${{ vars.PROPELLER_BUNDLE_BUCKET }}
          PROPELLER_LAMBDA_ARN: ${{ vars.PROPELLER_LAMBDA_ARN }}
          DEPLOY_ACTION: ${{ inputs.action }}
        run: |
          just pull
          just deploy
      - run: |
          echo "**Propeller version:** $(jq -r '.propeller_version' dist/landing-zone/pipeline.lock.json)" >> $GITHUB_STEP_SUMMARY
          echo "**Action:** ${{ inputs.action }}" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          cat dist/landing-zone/pipeline.lock.md >> $GITHUB_STEP_SUMMARY
```

The `action` input controls what the workflow does: `plan` shows what would
change without applying; `apply` runs the actual deployment. The `DEPLOY_ACTION`
environment variable is read by `just deploy` to decide which mode to invoke.

Commit and push the workflow file.

## 5. First deploy

In the consumer repo, go to **Actions → Deploy Landing Zone → Run workflow**.

Start with a `plan` run to confirm the wiring. The job summary shows the
resolved propeller version, the action, and a Mermaid graph of the pipeline.

## What this step produces

- A dedicated CI user in the Operations account with minimal permissions
- GitHub secrets and variables configured in the consumer repo
- A `.github/workflows/deploy-landing-zone.yml` workflow that runs plan or apply
- A successful first plan of the first step

## What's next

- Customize the pipeline as needs evolve: [customization](customization.md).
- Look up reference details: [pipeline schema](pipeline-schema.md),
  [project structure](project-structure.md).
