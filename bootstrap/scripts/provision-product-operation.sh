#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:=${AWS_DEFAULT_REGION:?AWS_REGION or AWS_DEFAULT_REGION is required}}"
: "${OPERATION_ACCOUNT_NAME:=operations}"
: "${OPERATION_ROLE_NAME:=AWSControlTowerExecution}"

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

# ── Assume role in operation account ─────────────────────────────────────────
echo "--- Assuming ${OPERATION_ROLE_NAME} in ${OPERATION_ACCOUNT_ID} ---"
CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::${OPERATION_ACCOUNT_ID}:role/${OPERATION_ROLE_NAME}" \
  --role-session-name "bootstrap-deploy-product" \
  --query 'Credentials' \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['AccessKeyId'])")
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['SecretAccessKey'])")
export AWS_SESSION_TOKEN=$(echo "$CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['SessionToken'])")

# ── Verify identity ──────────────────────────────────────────────────────────
CALLER=$(aws sts get-caller-identity --output json)
echo "Now operating as:"
echo "$CALLER"
# TODO: provision the deploy-runner product in the operation account

echo "Done."
