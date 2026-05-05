#!/usr/bin/env bash
set -euo pipefail
set -x

: "${AWS_REGION:=${AWS_DEFAULT_REGION:?AWS_REGION or AWS_DEFAULT_REGION is required}}"
: "${OPERATION_ACCOUNT_NAME:=operations}"
: "${OPERATION_ROLE_NAME:=AWSControlTowerExecution}"
: "${STS_REGION:=us-east-1}"
: "${TF_DIR:=bootstrap/terraform/landing-zone-propeller-sfn}"
: "${TF_VERSION:=1.14.9}"
: "${STATE_BUCKET_PREFIX:=state-iac}"
: "${TF_STATE_KEY:=bootstrap/landing-zone-propeller-sfn/terraform.tfstate}"
: "${SFN_NAME:=landing-zone-propeller-sfn}"

# ── Resolve operation account ID ─────────────────────────────────────────────
if [ -z "${OPERATION_ACCOUNT_ID:-}" ]; then
  echo "--- Resolving operation account '${OPERATION_ACCOUNT_NAME}' from org root ---"
  ORG_ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
  OPERATION_ACCOUNT_ID=$(aws organizations list-accounts-for-parent \
    --parent-id "$ORG_ROOT_ID" \
    --query "Accounts[?Name=='${OPERATION_ACCOUNT_NAME}' && Status=='ACTIVE'].Id | [0]" \
    --output text)
  if [ "$OPERATION_ACCOUNT_ID" = "None" ] || [ -z "$OPERATION_ACCOUNT_ID" ]; then
    echo "Account '${OPERATION_ACCOUNT_NAME}' not found. Run create-operation-account first." >&2
    exit 1
  fi
fi
echo "Operation account ID: ${OPERATION_ACCOUNT_ID}"

STATE_BUCKET="${STATE_BUCKET_PREFIX}-${OPERATION_ACCOUNT_ID}-${AWS_REGION}-an"

# ── Resolve organization ID ──────────────────────────────────────────────────
ORG_ID=$(aws organizations describe-organization \
  --query 'Organization.Id' --output text)
echo "Organization ID: ${ORG_ID}"

echo "  State bucket   : ${STATE_BUCKET}"
echo "  TF state key   : ${TF_STATE_KEY}"
echo "  SFN name       : ${SFN_NAME}"

# ── Assume role in operation account ─────────────────────────────────────────
ROLE_ARN="arn:aws:iam::${OPERATION_ACCOUNT_ID}:role/${OPERATION_ROLE_NAME}"
echo "--- Assuming ${OPERATION_ROLE_NAME} in ${OPERATION_ACCOUNT_ID} (via ${STS_REGION}) ---"

CREDS=$(aws sts assume-role \
  --region "$STS_REGION" \
  --role-arn "$ROLE_ARN" \
  --role-session-name "bootstrap-deploy-trigger" \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)

export $(printf "AWS_ACCESS_KEY_ID=%s AWS_SECRET_ACCESS_KEY=%s AWS_SESSION_TOKEN=%s" $CREDS)

CURRENT_ACCOUNT=$(aws sts get-caller-identity --region "$STS_REGION" --query Account --output text)
echo "Now operating as: ${CURRENT_ACCOUNT}"

if [ "$CURRENT_ACCOUNT" != "$OPERATION_ACCOUNT_ID" ]; then
  echo "Account mismatch: expected ${OPERATION_ACCOUNT_ID}, got ${CURRENT_ACCOUNT}" >&2
  exit 1
fi

# ── Install Terraform if not available ───────────────────────────────────────
if ! command -v terraform &>/dev/null; then
  echo "--- Installing Terraform ${TF_VERSION} ---"
  curl -sL "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip" \
    -o /tmp/terraform.zip
  unzip -qo /tmp/terraform.zip -d /usr/local/bin
  terraform version
fi

# ── Validate Terraform directory ─────────────────────────────────────────────
if [ ! -d "$TF_DIR" ]; then
  echo "Terraform directory not found: ${TF_DIR}" >&2
  exit 1
fi

# ── Run Terraform ────────────────────────────────────────────────────────────
echo "--- Terraform init ---"
terraform -chdir="$TF_DIR" init \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="key=${TF_STATE_KEY}" \
  -backend-config="region=${AWS_REGION}"

echo "--- Terraform apply ---"
terraform -chdir="$TF_DIR" apply -auto-approve \
  -var="region=${AWS_REGION}" \
  -var="sfn_name=${SFN_NAME}" \
  -var="organization_id=${ORG_ID}"

echo "Done."
