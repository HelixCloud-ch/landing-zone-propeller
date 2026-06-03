#!/usr/bin/env bash
set -euo pipefail
set -x

: "${OPERATIONS_ACCOUNT_NAME:=Operations}"
: "${OPERATIONS_EMAIL:?OPERATIONS_EMAIL is required}"
: "${OPERATIONS_ROLE_NAME:=AWSControlTowerExecution}"
: "${AWS_REGION:=${AWS_DEFAULT_REGION:-eu-central-2}}"
# STS_REGION is used for assume-role into the new account. Opt-in regions
# are not enabled yet, so we use a default region for the initial calls.
: "${STS_REGION:=us-east-1}"
if ! echo "$OPERATIONS_EMAIL" | grep -qE '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
  echo "OPERATIONS_EMAIL is not a valid email address: ${OPERATIONS_EMAIL}" >&2
  exit 1
fi

# ── Check if account already exists anywhere in the org ─────────────────────
MATCHING_IDS=$(aws organizations list-accounts \
  --query "Accounts[?Name=='${OPERATIONS_ACCOUNT_NAME}' && Status=='ACTIVE'].Id" \
  --output text)
MATCH_COUNT=$(echo "$MATCHING_IDS" | wc -w | tr -d ' ')

if [ "$MATCH_COUNT" -gt 1 ]; then
  echo "Multiple accounts named '${OPERATIONS_ACCOUNT_NAME}' found: ${MATCHING_IDS}" >&2
  echo "Refusing to proceed. Rename the duplicates or use a different OPERATIONS_ACCOUNT_NAME." >&2
  exit 1
fi
OPERATIONS_ACCOUNT_ID="$MATCHING_IDS"

# ── Create account if it does not exist ──────────────────────────────────────
if [ "$OPERATIONS_ACCOUNT_ID" != "None" ] && [ -n "$OPERATIONS_ACCOUNT_ID" ]; then
  echo "Operations account already exists: ${OPERATIONS_ACCOUNT_ID}"
else
  echo "Creating Operations account..."
  CREATE_REQ=$(aws organizations create-account \
    --email "$OPERATIONS_EMAIL" \
    --account-name "$OPERATIONS_ACCOUNT_NAME" \
    --role-name "$OPERATIONS_ROLE_NAME" \
    --query 'CreateAccountStatus.Id' \
    --output text)

  while true; do
    STATUS=$(aws organizations describe-create-account-status \
      --create-account-request-id "$CREATE_REQ" \
      --query 'CreateAccountStatus.[State,AccountId]' \
      --output text)
    STATE=$(echo "$STATUS" | awk '{print $1}')

    if [ "$STATE" = "SUCCEEDED" ]; then
      OPERATIONS_ACCOUNT_ID=$(echo "$STATUS" | awk '{print $2}')
      echo "Account created: ${OPERATIONS_ACCOUNT_ID}"
      break
    elif [ "$STATE" = "FAILED" ]; then
      echo "Account creation failed" >&2
      exit 1
    fi

    echo "Waiting for account creation (state: ${STATE})..."
    sleep 10
  done
fi

echo "OPERATIONS_ACCOUNT_ID=${OPERATIONS_ACCOUNT_ID}"

# ── Enable opt-in region in the new account if needed ────────────────────────
echo "--- Checking if ${AWS_REGION} needs opt-in in operations account ---"

ROLE_ARN="arn:aws:iam::${OPERATIONS_ACCOUNT_ID}:role/${OPERATIONS_ROLE_NAME}"
CREDS=$(aws sts assume-role \
  --region "$STS_REGION" \
  --role-arn "$ROLE_ARN" \
  --role-session-name "bootstrap-enable-region" \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)

# Temporarily switch to the operations account
ORIG_AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
ORIG_AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
ORIG_AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN:-}"

export $(printf "AWS_ACCESS_KEY_ID=%s AWS_SECRET_ACCESS_KEY=%s AWS_SESSION_TOKEN=%s" $CREDS)

REGION_STATUS=$(aws account get-region-opt-status \
  --region-name "$AWS_REGION" \
  --region "$STS_REGION" \
  --query 'RegionOptStatus' --output text 2>/dev/null || echo "UNKNOWN")

if [ "$REGION_STATUS" = "ENABLED" ] || [ "$REGION_STATUS" = "ENABLED_BY_DEFAULT" ]; then
  echo "Region ${AWS_REGION} already enabled in operations account"
else
  echo "Enabling region ${AWS_REGION} in operations account..."
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
  echo "Region ${AWS_REGION} enabled in operations account"
fi

# Restore original credentials (back to management account)
export AWS_ACCESS_KEY_ID="$ORIG_AWS_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$ORIG_AWS_SECRET_ACCESS_KEY"
export AWS_SESSION_TOKEN="$ORIG_AWS_SESSION_TOKEN"

echo "Done."
