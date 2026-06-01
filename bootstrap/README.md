# Bootstrap — Landing Zone Setup

Step-by-step guide to bootstrap a landing zone from a brand-new, empty AWS
account. All operations run from the AWS Management Console and CloudShell.
Bootstrap scripts run inside CodeBuild; the source code is downloaded as a zip
from a GitHub release — no git clone required.

> **Prerequisites**: sign in to the AWS Management Console with the root or
> admin user of the account that will become the management account.

> **Overrides**: each script documents its configurable variables and defaults
> in its header. Only required inputs are listed below — check the script
> source for the full list of optional overrides.

## Open CloudShell

CloudShell is not available in every Region. If your target Region does not
support CloudShell, open it in a nearby default Region such as `eu-central-1`.

All CLI commands in this guide include an explicit `--region` flag so they
work regardless of which Region CloudShell is running in.

---

## Common variables

Set these once in your CloudShell session before running any step. All
subsequent commands use them.

```bash
export TARGET_REGION=eu-central-2
export LZP_VERSION=v0.0.1
export LZP_ZIP_URL="https://github.com/HelixCloud-ch/landing-zone-propeller/archive/refs/tags/${LZP_VERSION}.zip"
```

---

## 1. Enable opt-in Region (if applicable)

Skip this section if you are deploying in a default Region (e.g. `eu-central-1`).
Opt-in Regions like `eu-central-2` (Zurich) are disabled by default and must be
enabled before any resource can be created there.

> IAM Identity Center can only be enabled in a single Region per organization.
> Changing it later requires deleting and re-creating the instance, so pick
> carefully.

### Console

1. Choose your account name → **Account** → **AWS Regions**.
2. Find the target Region and choose **Enable**.
3. Wait for the status to change to *Enabled* (a few minutes).

---

## 2. Create an AWS Organization

```bash
aws organizations create-organization \
  --feature-set ALL \
  --region "$TARGET_REGION"
```

Verify the management account email when the verification message arrives.

---

## 3. Enable IAM Identity Center (organization instance)

Follow the official guide: [Enable IAM Identity Center](https://docs.aws.amazon.com/singlesignon/latest/userguide/enable-identity-center.html).
Select the target Region before enabling, and choose the **organization instance** type.

> **Optional — external identity provider**: if you want users to sign in with
> corporate credentials (e.g. Entra ID / Azure AD, Okta), configure an
> external IdP after enabling Identity Center:
> [Connect an external identity provider](https://docs.aws.amazon.com/singlesignon/latest/userguide/manage-your-identity-source-idp.html).

---

## 4. Deploy the Bootstrap CodeBuild stack

The CodeBuild project uses `NO_SOURCE` — source code is downloaded at runtime.

```bash
curl -sL "$LZP_ZIP_URL" -o /tmp/lzp.zip
unzip -qo /tmp/lzp.zip "landing-zone-propeller-*/bootstrap/cloudformation/bootstrap.yaml" -d /tmp
TEMPLATE=$(find /tmp/landing-zone-propeller-* -name bootstrap.yaml -path '*/bootstrap/cloudformation/*')

aws cloudformation deploy \
  --region "$TARGET_REGION" \
  --template-file "$TEMPLATE" \
  --stack-name bootstrap \
  --capabilities CAPABILITY_NAMED_IAM
```

Once the stack is deployed, set the remaining session variables and download
`run.sh`:

```bash
export CB_PROJECT=$(aws cloudformation describe-stacks \
  --region "$TARGET_REGION" \
  --stack-name bootstrap \
  --query 'Stacks[0].Outputs[?OutputKey==`CodeBuildProjectName`].OutputValue' \
  --output text)

unzip -qo /tmp/lzp.zip "landing-zone-propeller-*/bootstrap/scripts/run.sh" -d /tmp
RUN=$(find /tmp/landing-zone-propeller-* -name run.sh)
chmod +x "$RUN"

echo "CodeBuild project : $CB_PROJECT"
echo "Source zip        : $LZP_ZIP_URL"
```

Every subsequent step is a single call:

```bash
$RUN <script-name> [KEY=VALUE ...]
```

---

## 5. Deploy the Service Catalog portfolio and product

```bash
$RUN create-portfolio.sh
```

---

## 6. Share the Service Catalog portfolio with the organization

```bash
$RUN share-portfolio.sh
```

---

## 7. Create the Operations account

```bash
$RUN create-operations-account.sh OPERATIONS_EMAIL=ops@example.com
```

Creates the account, assumes `AWSControlTowerExecution` in it, and enables the
opt-in region. The account is ready for resource deployment after this step.

---

## 8. Provision the deploy-runner product in the management account

```bash
$RUN provision-product-mpa.sh
```

Auto-resolves the product ID, artifact ID, and operations account ID from their
default names. Configures the cross-account run role (`deploy-runner-run-role`)
that allows the operations account to start builds.

If the product is already provisioned, the script updates it with the current
parameters.

---

## 9. Provision the deploy-runner product in the Operations account

```bash
$RUN provision-product-operations.sh
```

Assumes `AWSControlTowerExecution` in the operations account, accepts the
org-shared portfolio, and provisions the product. Also configures the
cross-account run role.

---

## 10. Create the source bucket in the Operations account

```bash
$RUN create-source-bucket.sh
```

Creates the S3 source bucket in the Operations account using Terraform. State
is stored in the `state-iac-{account_id}-{region}` bucket created in step 9.

---

## 11. Deploy the Autopilot (Durable Function orchestrator)

```bash
$RUN deploy-autopilot.sh
```

Deploys the `propeller-autopilot` Durable Lambda in the Operations account.
This is the orchestrator that receives pipeline invocations from CI and
coordinates CodeBuild executions across accounts.

---

## 12. Delete the bootstrap stack

The bootstrap CodeBuild project is ephemeral — delete it now that the
foundation is in place.

```bash
aws cloudformation delete-stack \
  --region "$TARGET_REGION" \
  --stack-name bootstrap
```

This removes the CodeBuild project, its IAM role, and the log group. All other
resources (Organization, accounts, Service Catalog, deploy-runners, source
bucket, Autopilot) are permanent and unaffected.
