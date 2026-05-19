# CI Setup

One-time setup for deploying from GitHub Actions using static IAM credentials.

## 1. Create IAM User

In the operations account:

```bash
aws iam create-user --user-name propeller-ci
aws iam put-user-policy --user-name propeller-ci --policy-name propeller-deploy --policy-document '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::<BUNDLE_BUCKET>/bundle.zip"
    },
    {
      "Effect": "Allow",
      "Action": "lambda:InvokeFunction",
      "Resource": "arn:aws:lambda:<REGION>:<ACCOUNT_ID>:function:propeller-autopilot:*"
    }
  ]
}'
```

## 2. Create Access Keys

```bash
aws iam create-access-key --user-name propeller-ci
```

## 3. GitHub Secrets

Add to the consumer repo (Settings → Secrets → Actions):

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

## 4. GitHub Variables

Add to the consumer repo (Settings → Variables → Actions):

- `AWS_REGION`
- `PROPELLER_BUNDLE_BUCKET`
- `PROPELLER_LAMBDA_ARN` (`:$LATEST` is appended automatically)

## 5. Deploy Workflow

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
      - run: cat dist/pipeline.lock.md >> $GITHUB_STEP_SUMMARY
```
