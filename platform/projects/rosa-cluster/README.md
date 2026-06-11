# ROSA HCP Cluster

Deploys a ROSA HCP (Hosted Control Planes) cluster with account roles, OIDC, and
operator roles created inline. Private by default.

## Prerequisites

See the [PREREQUISITES](#prerequisites) section at the bottom of this file.

## Pipeline wiring

```yaml
stages:
  - name: cluster
    steps:
      - project: rosa-cluster
        target: workload-account
        depends_on: [vpc]
        inputs:
          - name: vpc.subnet_ids_by_tier
            var: subnet_ids_json
          - name: vpc.availability_zones
            var: availability_zones
```

The `subnet_ids_json` input is the JSON-encoded tier map from the VPC project.
The project extracts the `private` tier by default (configurable via
`private_subnet_tier`). For public clusters, the `public` tier is also used.

## Consumer tfvars

Required values:

```hcl
region            = "eu-central-2"
cluster_name      = "acme-prod"
openshift_version = "4.17.6"
machine_cidr      = "10.0.0.0/16"
availability_zones = ["eu-central-2a", "eu-central-2b", "eu-central-2c"]
```

## Accessing the cluster

If `create_admin_user = true` (default), admin credentials are stored in Secrets
Manager:

```bash
aws secretsmanager get-secret-value \
  --secret-id propeller/rosa/<cluster_name>/admin \
  --query SecretString --output text | jq .
```

Returns
`{"username":"...","password":"...","api_url":"...","console_url":"..."}`.

Then:

```bash
oc login <api_url> --username <username> --password <password>
```

## Destroy notes

Cluster deletion takes ~25-30 minutes. ROSA leaves a VPC endpoint in the VPC
after destroy (e.g. `*-vpce-private-router`) that must be deleted manually
before the VPC can also be torn down.

---

## PREREQUISITES

Complete these one-time steps. Steps 1-2 are console actions; the rest run from
AWS CloudShell in the workload account.

### 1. Enable ROSA and link billing

Enable ROSA in **both** accounts:

- **Management account**: Open the
  [ROSA console](https://console.aws.amazon.com/rosa/home), click **Enable
  ROSA**, then **Continue to Red Hat** to complete the billing link between your
  AWS account and your Red Hat organization.
- **Workload account**: Open the
  [ROSA console](https://console.aws.amazon.com/rosa/home) and click **Enable
  ROSA**. This creates the ELB service-linked role needed for cluster
  deployment.

Without the Red Hat billing link (management account), cluster creation fails
with "billing account not linked to organization at the aws marketplace".

Ref:
[AWS — Set up to use ROSA](https://docs.aws.amazon.com/rosa/latest/userguide/set-up.html)
Ref:
[Red Hat KB — Billing account not linked](https://access.redhat.com/solutions/7068951)

### 2. Create an OCM service account

On the Red Hat console, create a service account for CI automation. Save the
`client_id` and `client_secret`.

→
[console.redhat.com/iam/service-accounts](https://console.redhat.com/iam/service-accounts)

### 3. STS token version (opt-in regions)

Required if deploying in an opt-in region (e.g. `eu-central-2`). Account-wide,
one-time, run in the workload account:

```sh
aws iam set-security-token-service-preferences --global-endpoint-token-version v2Token
```

### 4. Install the ROSA CLI (CloudShell)

```sh
mkdir -p ~/.local/bin && curl -sL https://mirror.openshift.com/pub/openshift-v4/clients/rosa/latest/rosa-linux.tar.gz | tar xz -C ~/.local/bin && chmod +x ~/.local/bin/rosa
rosa version
```

### 5. Login with the service account

```sh
rosa login --client-id <client_id> --client-secret <client_secret>
```

### 6. Link AWS account to Red Hat OCM (workload account)

Create the OCM and user IAM roles that link your AWS account to your Red Hat
organization:

```sh
rosa create ocm-role --mode auto
rosa create user-role --mode auto
```

Accept defaults and confirm when prompted.

Ref:
[Red Hat — Required IAM roles and resources](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/prepare_your_environment/rosa-hcp-prepare-iam-roles-resources#rosa-sts-ocm-roles-and-permissions-iam-basic-role_prepare-role-resources)
Ref:
[Red Hat KB — Understanding OCM role and User role](https://access.redhat.com/articles/6961686)

### 7. Verify setup

```sh
rosa list versions --channel-group stable --hosted-cp
```

If this returns a list of versions, the account is correctly linked and ready
for cluster creation.

### 8. Store OCM credentials in Secrets Manager

Create a secret in the **workload account** (or whichever account the pipeline
runner assumes into). The `rosa-cluster` project reads this secret at plan/apply
time.

Via CLI:

```sh
aws secretsmanager create-secret \
  --name "propeller/rosa/ocm-token" \
  --secret-string '{"client_id":"<ID>","client_secret":"<SECRET>"}'
```

Or create it manually from the
[Secrets Manager console](https://console.aws.amazon.com/secretsmanager) as a
plaintext JSON secret with name `propeller/rosa/ocm-token`.

The secret name is configurable via the `ocm_secret_name` variable. Default:
`propeller/rosa/ocm-token`.

### 9. Verify AWS service quotas (optional)

The ROSA console checks for 100 vCPUs but doesn't validate EBS, VPC, or ELB
quotas. For larger clusters, verify manually via Service Quotas and request
increases if needed (allow hours to days).

Ref:
[Red Hat — Required AWS service quotas](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/prepare_your_environment/rosa-sts-required-aws-service-quotas)
