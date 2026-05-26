# CI Setup

One-time setup for deploying from GitHub Actions. The CI user only needs
permissions to upload the bundle to S3 and invoke the autopilot Lambda.

## 1. Create CI User (from management account CloudShell)

Run this entire block. It resolves the Operations account, assumes into it,
creates the CI user, and outputs everything you need for GitHub.

```bash
# --- Configuration (edit this) ---
REGION="eu-central-2"

# --- Resolve operations account ---
OPS_ACCOUNT_ID=$(aws organizations list-accounts \
  --query "Accounts[?Name=='Operations' && Status=='ACTIVE'].Id | [0]" \
  --output text)
BUNDLE_BUCKET="source-${OPS_ACCOUNT_ID}-${REGION}-an"
LAMBDA_ARN="arn:aws:lambda:${REGION}:${OPS_ACCOUNT_ID}:function:propeller-autopilot"

# --- Assume role into operations ---
CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::${OPS_ACCOUNT_ID}:role/AWSControlTowerExecution" \
  --role-session-name "propeller-ci-setup" \
  --query 'Credentials' --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r .AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r .SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r .SessionToken)

# --- Create CI user ---
aws iam create-user --user-name propeller-ci

aws iam put-user-policy --user-name propeller-ci --policy-name propeller-deploy --policy-document "$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${BUNDLE_BUCKET}/bundle.zip"
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

## 2. GitHub Secrets

Add to the consumer repo (Settings → Secrets and Variables → Actions → Secrets → Repository Secrets):

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

## 3. GitHub Variables

Add to the consumer repo (Settings → Secrets and Variables → Actions → Variables → Repository Variables):

- `AWS_REGION`
- `PROPELLER_BUNDLE_BUCKET`
- `PROPELLER_LAMBDA_ARN`

All values are printed at the end of the script above.

## 4. Deploy Workflow

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy
on:
  workflow_dispatch:
    inputs:
      action:
        description: 'Deploy action'
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
          echo "**Propeller version:** $(jq -r '.propeller_version' dist/pipeline.lock.json)" >> $GITHUB_STEP_SUMMARY
          echo "**Action:** ${{ inputs.action }}" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          cat dist/pipeline.lock.md >> $GITHUB_STEP_SUMMARY
```
