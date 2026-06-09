# ECR - Shared Container Registry

Configures an ECR private registry with repository creation templates
(create-on-push) and organization-wide cross-account pull access.

## What it deploys

- **Repository creation templates** - auto-create repos on push with configured
  defaults (tag immutability, encryption, lifecycle policy)
- **IAM role** - `ecr-repository-creation-role`, assumed by ECR to apply tags
  when auto-creating repositories
- **Cross-account pull policy** - repository policy granting pull access to all
  accounts in the organization (or scoped to specific OUs)

## Pipeline usage

```yaml
- project: ecr
  target: shared-services # or any account hosting your shared registry
  inputs:
    - name: "@landing-zone/workload-parameters.organization_id"
      var: organization_id
```

### Cross-account pull

Workload accounts can pull images without additional setup. The repository
creation template includes an org-path-based policy that grants pull access to
all accounts in the organization (or scoped to specific OUs via
`pull_access_ou_ids`).

```bash
# From any workload account:
aws ecr get-login-password --region eu-central-2 \
  | docker login --username AWS --password-stdin ECR_ACCOUNT_ID.dkr.ecr.eu-central-2.amazonaws.com

docker pull ECR_ACCOUNT_ID.dkr.ecr.eu-central-2.amazonaws.com/my-app:v1.0.0
```

---

## CI push access

The ECR project configures the registry but does not create CI push credentials.
You need to set up authentication for your CI pipelines to push images.

### Option 1: IAM user with access keys (on-prem GitLab / Jenkins)

Create an IAM user in the account hosting ECR with push permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["ecr:GetAuthorizationToken"],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:CompleteLayerUpload",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer"
      ],
      "Resource": "arn:aws:ecr:*:ACCOUNT_ID:repository/*"
    }
  ]
}
```

Then in your CI pipeline:

```bash
aws ecr get-login-password --region eu-central-2 \
  | docker login --username AWS --password-stdin ACCOUNT_ID.dkr.ecr.eu-central-2.amazonaws.com

docker push ACCOUNT_ID.dkr.ecr.eu-central-2.amazonaws.com/my-app:v1.0.0
```

### Option 2: IAM Roles Anywhere (on-prem with certificates)

If your on-prem runners have X.509 certificates, use IAM Roles Anywhere to
obtain temporary credentials without long-lived access keys. Create a trust
anchor + profile pointing to a role with the same push policy above.

### Option 3: OIDC (GitHub Actions / GitLab SaaS)

Configure an OIDC identity provider in the ECR account and create a role that
your CI platform can assume:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/*"
        }
      }
    }
  ]
}
```

---

## Testing create-on-push

Push an image to a repo that doesn't exist, ECR auto-creates it:

```bash
# Using crane (no Docker daemon needed):
crane copy alpine:latest ACCOUNT_ID.dkr.ecr.eu-central-2.amazonaws.com/test/hello:v1

# Or with Docker:
docker tag alpine:latest ACCOUNT_ID.dkr.ecr.eu-central-2.amazonaws.com/test/hello:v1
docker push ACCOUNT_ID.dkr.ecr.eu-central-2.amazonaws.com/test/hello:v1
```

The `test/hello` repository is created with the template settings.
