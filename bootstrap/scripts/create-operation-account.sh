#!/usr/bin/env bash
set -euo pipefail

: "${OPERATION_ACCOUNT_NAME:=operations}"
: "${OPERATION_EMAIL:?OPERATION_EMAIL is required}"
: "${OPERATION_ROLE_NAME:=AWSControlTowerExecution}"
: "${AWS_REGION:=${AWS_DEFAULT_REGION:-eu-central-2}}"
# STS_REGION is used for assume-role into the new account. Opt-in regions
# are not enabled yet, so we use a default region for the initial calls.
: "${STS_REGION:=us-east-1}"
if ! echo "$OPERATION_EMAIL" | grep -qE '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
  echo "OPERATION_EMAIL is not a valid email address: ${OPERATION_EMAIL}" >&2
  exit 1
fi

# ── Resolve org root ─────────────────────────────────────────────────────────
ORG_ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
echo "Org root: ${ORG_ROOT_ID}"

# ── Check if account already exists in the org root ──────────────────────────
OPERATION_ACCOUNT_ID=$(aws organizations list-accounts-for-parent \
  --parent-id "$ORG_ROOT_ID" \
  --query "Accounts[?Name=='${OPERATION_ACCOUNT_NAME}' && Status=='ACTIVE'].Id | [0]" \
  --output text)

# ── Create account if it does not exist ──────────────────────────────────────
if [ "$OPERATION_ACCOUNT_ID" != "None" ] && [ -n "$OPERATION_ACCOUNT_ID" ]; then
  echo "Operation account already exists: ${OPERATION_ACCOUNT_ID}"
else
  echo "Creating Operation account..."
  CREATE_REQ=$(aws organizations create-account \
    --email "$OPERATION_EMAIL" \
    --account-name "$OPERATION_ACCOUNT_NAME" \
    --role-name "$OPERATION_ROLE_NAME" \
    --query 'CreateAccountStatus.Id' \
    --output text)

  while true; do
    STATUS=$(aws organizations describe-create-account-status \
      --create-account-request-id "$CREATE_REQ" \
      --query 'CreateAccountStatus.[State,AccountId]' \
      --output text)
    STATE=$(echo "$STATUS" | awk '{print $1}')

    if [ "$STATE" = "SUCCEEDED" ]; then
      OPERATION_ACCOUNT_ID=$(echo "$STATUS" | awk '{print $2}')
      echo "Account created: ${OPERATION_ACCOUNT_ID}"
      break
    elif [ "$STATE" = "FAILED" ]; then
      echo "Account creation failed" >&2
      exit 1
    fi

    echo "Waiting for account creation (state: ${STATE})..."
    sleep 10
  done
fi

echo "OPERATION_ACCOUNT_ID=${OPERATION_ACCOUNT_ID}"

# ── Enable opt-in region in the new account if needed ────────────────────────
echo "--- Checking if ${AWS_REGION} needs opt-in in operation account ---"

ROLE_ARN="arn:aws:iam::${OPERATION_ACCOUNT_ID}:role/${OPERATION_ROLE_NAME}"
CREDS=$(aws sts assume-role \
  --region "$STS_REGION" \
  --role-arn "$ROLE_ARN" \
  --role-session-name "bootstrap-enable-region" \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)

# Temporarily switch to the operation account
ORIG_AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
ORIG_AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
ORIG_AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN:-}"

export $(printf "AWS_ACCESS_KEY_ID=%s AWS_SECRET_ACCESS_KEY=%s AWS_SESSION_TOKEN=%s" $CREDS)

REGION_STATUS=$(aws account get-region-opt-status \
  --region-name "$AWS_REGION" \
  --region "$STS_REGION" \
  --query 'RegionOptStatus' --output text 2>/dev/null || echo "UNKNOWN")

if [ "$REGION_STATUS" = "ENABLED" ] || [ "$REGION_STATUS" = "ENABLED_BY_DEFAULT" ]; then
  echo "Region ${AWS_REGION} already enabled in operation account"
else
  echo "Enabling region ${AWS_REGION} in operation account..."
  aws account enable-region \
    --region-name "$AWS_REGION" \
    --region "$STS_REGION"

  while true; do
    REGION_STATUS=$(aws account get-region-opt-status \
      --region-name "$AWS_REGION" \
      --region "$STS_REGION" \
      --query 'RegionOptStatus' --output text)
    echo "Region ${AWS_REGION} status: ${REGION_STATUS}"
    [ "$REGION_STATUS" = "ENABLED" ] && break
    sleep 15
  done
  echo "Region ${AWS_REGION} enabled in operation account"
fi

# Restore original credentials (back to management account)
export AWS_ACCESS_KEY_ID="$ORIG_AWS_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$ORIG_AWS_SECRET_ACCESS_KEY"
export AWS_SESSION_TOKEN="$ORIG_AWS_SESSION_TOKEN"

echo "Done."
