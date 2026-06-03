#!/usr/bin/env bash
set -euo pipefail
set -x

: "${AWS_REGION:=${AWS_DEFAULT_REGION:?AWS_REGION or AWS_DEFAULT_REGION is required}}"
: "${OPERATIONS_ACCOUNT_NAME:=Operations}"
: "${OPERATIONS_ROLE_NAME:=AWSControlTowerExecution}"
: "${STS_REGION:=us-east-1}"
: "${TF_DIR:=bootstrap/terraform/source-bucket}"
: "${TF_VERSION:=1.14.9}"
: "${STATE_BUCKET_PREFIX:=state-iac}"
: "${TF_STATE_KEY:=bootstrap/source-bucket/terraform.tfstate}"
: "${SOURCE_BUCKET_PREFIX:=source}"

# ── Resolve operations account ID ─────────────────────────────────────────────
if [ -z "${OPERATIONS_ACCOUNT_ID:-}" ]; then
  echo "--- Resolving operations account '${OPERATIONS_ACCOUNT_NAME}' from organization ---"
  MATCHING_IDS=$(aws organizations list-accounts \
    --query "Accounts[?Name=='${OPERATIONS_ACCOUNT_NAME}' && Status=='ACTIVE'].Id" \
    --output text)
  MATCH_COUNT=$(echo "$MATCHING_IDS" | wc -w | tr -d ' ')
  if [ "$MATCH_COUNT" -eq 0 ]; then
    echo "Account '${OPERATIONS_ACCOUNT_NAME}' not found in the organization." >&2
    echo "Run create-operations-account.sh first or pass OPERATIONS_ACCOUNT_ID directly." >&2
    exit 1
  elif [ "$MATCH_COUNT" -gt 1 ]; then
    echo "Multiple accounts named '${OPERATIONS_ACCOUNT_NAME}' found: ${MATCHING_IDS}" >&2
    echo "Pass OPERATIONS_ACCOUNT_ID=<id> to disambiguate." >&2
    exit 1
  fi
  OPERATIONS_ACCOUNT_ID="$MATCHING_IDS"
fi
echo "Operations account ID: ${OPERATIONS_ACCOUNT_ID}"

STATE_BUCKET="${STATE_BUCKET_PREFIX}-${OPERATIONS_ACCOUNT_ID}-${AWS_REGION}-an"

# ── Resolve organization ID ──────────────────────────────────────────────────
ORG_ID=$(aws organizations describe-organization \
  --query 'Organization.Id' --output text)
echo "Organization ID: ${ORG_ID}"

echo "  State bucket          : ${STATE_BUCKET}"
echo "  Source bucket prefix  : ${SOURCE_BUCKET_PREFIX}"
echo "  TF state key          : ${TF_STATE_KEY}"

# ── Assume role in operations account ─────────────────────────────────────────
ROLE_ARN="arn:aws:iam::${OPERATIONS_ACCOUNT_ID}:role/${OPERATIONS_ROLE_NAME}"
echo "--- Assuming ${OPERATIONS_ROLE_NAME} in ${OPERATIONS_ACCOUNT_ID} (via ${STS_REGION}) ---"

CREDS=$(aws sts assume-role \
  --region "$STS_REGION" \
  --role-arn "$ROLE_ARN" \
  --role-session-name "bootstrap-source-bucket" \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)

export $(printf "AWS_ACCESS_KEY_ID=%s AWS_SECRET_ACCESS_KEY=%s AWS_SESSION_TOKEN=%s" $CREDS)

CURRENT_ACCOUNT=$(aws sts get-caller-identity --region "$STS_REGION" --query Account --output text)
echo "Now operating as: ${CURRENT_ACCOUNT}"

if [ "$CURRENT_ACCOUNT" != "$OPERATIONS_ACCOUNT_ID" ]; then
  echo "Account mismatch: expected ${OPERATIONS_ACCOUNT_ID}, got ${CURRENT_ACCOUNT}" >&2
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
  -var="bucket_prefix=${SOURCE_BUCKET_PREFIX}" \
  -var="region=${AWS_REGION}" \
  -var="organization_id=${ORG_ID}"

echo "Done."
