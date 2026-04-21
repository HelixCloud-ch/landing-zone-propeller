# Bootstrap — Landing Zone Setup

Step-by-step guide to bootstrap a landing zone from a brand-new, empty AWS
account. All operations run from the AWS Management Console and CloudShell.
Bootstrap scripts run inside CodeBuild; the source code is downloaded as a zip
from a GitHub release — no git clone required.

> Prerequisites: sign in to the AWS Management Console with the root or admin
> user of the account that will become the management account.

## Open CloudShell

CloudShell is not available in every Region. If your target Region does not
support CloudShell (e.g. `eu-central-2`), open it in a nearby default Region
such as `eu-central-1`:

1. In the navigation bar, select a Region where CloudShell is available
   (e.g. **eu-central-2**).
2. Choose the **CloudShell** icon (terminal icon) in the navigation bar, or
   search for *CloudShell* in the service search bar.
3. Wait for the environment to initialize.

All CLI commands in this guide include an explicit `--region` flag so they
work regardless of which Region CloudShell is running in.

---

## 1. Enable opt-in Region (if applicable)

Skip this section if you are deploying in a default Region (e.g. `eu-central-1`).
Opt-in Regions like `eu-central-2` (Zurich) are disabled by default and must be
enabled before any resource can be created there.

> IAM Identity Center can only be enabled in a single Region per organization.
> Changing it later requires deleting and re-creating the instance, so pick
> carefully.

### Console

1. Choose your account name in the top-right corner, then choose **Account**.
2. Scroll down to the **AWS Regions** section.
3. Find the target Region (e.g. **Europe (Zurich) eu-central-2**) and choose
   **Enable**.
4. Review the confirmation text and choose **Enable region**.
5. Wait for the status to change from *Enabling* to *Enabled* (a few minutes
   while IAM data propagates).

Required permissions: `account:EnableRegion`, `account:GetRegionOptStatus`.

---

## 2. Create an AWS Organization

From CloudShell, create the organization with all features enabled (SCPs, tag
policies, etc.). The current account becomes the management account.

```bash
TARGET_REGION=eu-central-2

aws organizations create-organization \
  --feature-set ALL \
  --region "$TARGET_REGION"
```

Verify the management account email when the verification message arrives
(required before you can invite existing accounts).

Required permissions: `organizations:CreateOrganization`,
`iam:CreateServiceLinkedRole`.

---

## 3. Enable IAM Identity Center (organization instance)

This step must be done from the console. The `sso-admin` `CreateInstance` API
exists but is explicitly rejected when called from the management account — it
only works for standalone or member accounts. See the [AWS API reference](https://docs.aws.amazon.com/boto3/latest/reference/services/sso-admin/client/create_instance.html):
> *"The CreateInstance request is rejected if the instance is created within
> the organization management account."*

1. In the navigation bar, select the target Region (e.g. **eu-central-2**).
2. Open the [IAM Identity Center console](https://console.aws.amazon.com/singlesignon).
3. Under **Enable IAM Identity Center**, choose **Enable**.
4. On the **Enable IAM Identity Center with AWS Organizations** page, review
   the information and choose **Enable**.

This creates an **organization-level** instance that supports multi-account
permissions, delegated administration, and customer-managed KMS keys.

> AWS Organizations can have IAM Identity Center enabled in only a single
> Region. Changing it later requires deleting and re-creating the instance.

---


## 4. Deploy the Bootstrap CodeBuild stack

The CodeBuild project uses `NO_SOURCE` — the source code is downloaded at
runtime from a GitHub release zip. Deploy the stack from CloudShell after
downloading just the bootstrap template:

```bash
TARGET_REGION=eu-central-2
LZP_VERSION=v0.0.1
LZP_ZIP_URL="https://github.com/HelixCloud-ch/landing-zone-propeller/archive/refs/tags/${LZP_VERSION}.zip"

# Download and extract only the bootstrap template
curl -sL "$LZP_ZIP_URL" -o /tmp/lzp.zip
unzip -qo /tmp/lzp.zip "landing-zone-propeller-*/bootstrap/cloudformation/bootstrap.yaml" -d /tmp
TEMPLATE=$(find /tmp/landing-zone-propeller-* -name bootstrap.yaml -path '*/bootstrap/cloudformation/*')

aws cloudformation deploy \
  --region "$TARGET_REGION" \
  --template-file "$TEMPLATE" \
  --stack-name bootstrap \
  --capabilities CAPABILITY_NAMED_IAM
```

---

## Common variables

Set these variables once in your CloudShell session. All subsequent steps use
`run.sh` which reads them automatically.

```bash
export TARGET_REGION=eu-central-2
export LZP_VERSION=v0.0.1
export LZP_ZIP_URL="https://github.com/HelixCloud-ch/landing-zone-propeller/archive/refs/tags/${LZP_VERSION}.zip"

export CB_PROJECT=$(aws cloudformation describe-stacks \
  --region "$TARGET_REGION" \
  --stack-name bootstrap \
  --query 'Stacks[0].Outputs[?OutputKey==`CodeBuildProjectName`].OutputValue' \
  --output text)

echo "CodeBuild project : $CB_PROJECT"
echo "Source zip        : $LZP_ZIP_URL"
```

Then download `run.sh` from the same release zip so it is available in
CloudShell:

```bash
curl -sL "$LZP_ZIP_URL" -o /tmp/lzp.zip
unzip -qo /tmp/lzp.zip "landing-zone-propeller-*/bootstrap/scripts/run.sh" -d /tmp
RUN=$(find /tmp/landing-zone-propeller-* -name run.sh)
chmod +x "$RUN"
```

Every subsequent step is a single call:

```bash
$RUN <script-name> [KEY=VALUE ...]
```

`run.sh` downloads the release zip inside CodeBuild, runs the named script, and
polls until the build completes. Pass `KEY=VALUE` pairs to override any default
environment variable defined in the target script.


---

## 5. Deploy the Service Catalog portfolio and product

```bash
$RUN create-portfolio.sh
```

To override defaults:

```bash
$RUN create-portfolio.sh \
  PRODUCT_NAME=my-custom-runner \
  PRODUCT_TEMPLATE_PATH=path/to/template.yaml
```

Available overrides:

| Variable | Default |
|---|---|
| `PORTFOLIO_DISPLAY_NAME` | `landing-zone-propeller` |
| `PORTFOLIO_PROVIDER_NAME` | `landing-zone-propeller` |
| `PRODUCT_NAME` | `deploy-runner` |
| `PRODUCT_TEMPLATE_PATH` | `bootstrap/cloudformation/deploy-runner.yaml` |

---

## 6. Share the Service Catalog portfolio with the organization

```bash
$RUN share-portfolio.sh
```

To target a different portfolio:

```bash
$RUN share-portfolio.sh PORTFOLIO_DISPLAY_NAME=my-portfolio
```

---

## 7. Create the Operations account

```bash
$RUN create-operation-account.sh OPERATION_EMAIL=ops@example.com
```

The script creates the account, then assumes `AWSControlTowerExecution` in the
new account and, evntually, enable the opt-in region (`eu-central-2` by default). This
ensures the account is ready for resource deployment.

To override defaults:

```bash
$RUN create-operation-account.sh \
  OPERATION_EMAIL=ops@example.com \
  OPERATION_ACCOUNT_NAME=operations
```

Available overrides:

| Variable | Default |
|---|---|
| `OPERATION_EMAIL` | required |
| `OPERATION_ACCOUNT_NAME` | `operations` |
| `OPERATION_ROLE_NAME` | `AWSControlTowerExecution` |

---

## 8. Provision the deploy-runner product in the management account

```bash
$RUN provision-product-mpa.sh
```

The script auto-resolves the product ID, artifact ID, and operation account ID
from their default names. The source bucket defaults to
`source-{operation_account_id}-{region}`.

To override defaults:

```bash
$RUN provision-product-mpa.sh \
  PRODUCT_NAME=my-runner \
  CB_PROJECT_NAME=my-runner
```

Available overrides:

| Variable | Default |
|---|---|
| `PRODUCT_NAME` | `deploy-runner` |
| `PROVISIONED_PRODUCT_NAME` | `deploy-runner` |
| `CB_PROJECT_NAME` | `deploy-runner` |
| `OPERATION_ACCOUNT_NAME` | `operations` |
| `OPERATION_SOURCE_BUCKET` | `source-{account_id}-{region}` |
| `PRODUCT_ID` | auto-resolved |
| `ARTIFACT_ID` | auto-resolved |
| `OPERATION_ACCOUNT_ID` | auto-resolved |

---

## 9. Provision the deploy-runner product in the Operations account

```bash
$RUN deploy-product-operation.sh
```

This step assumes `AWSControlTowerExecution` in the operations account, accepts
the org-shared portfolio, grants the caller access, and provisions the product.

To override defaults:

```bash
$RUN deploy-product-operation.sh \
  OPERATION_ACCOUNT_ID=123456789012 \
  CB_PROJECT_NAME=my-runner
```

Available overrides:

| Variable | Default |
|---|---|
| `OPERATION_ACCOUNT_NAME` | `operations` |
| `OPERATION_ROLE_NAME` | `AWSControlTowerExecution` |
| `PORTFOLIO_DISPLAY_NAME` | `landing-zone-propeller` |
| `PRODUCT_NAME` | `deploy-runner` |
| `PROVISIONED_PRODUCT_NAME` | `deploy-runner` |
| `CB_PROJECT_NAME` | `deploy-runner` |
| `OPERATION_SOURCE_BUCKET` | `source-{account_id}-{region}` |
| `OPERATION_ACCOUNT_ID` | auto-resolved |
| `STS_REGION` | `us-east-1` |

---

<!-- Subsequent sections will be added as bootstrap tasks are implemented. -->