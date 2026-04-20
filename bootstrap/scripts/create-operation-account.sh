#!/usr/bin/env bash
set -euo pipefail

: "${OPERATION_ACCOUNT_NAME:=operations}"
: "${OPERATION_EMAIL:?OPERATION_EMAIL is required}"
: "${OPERATION_ROLE_NAME:=AWSControlTowerExecution}"
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

echo "Done. OPERATION_ACCOUNT_ID=${OPERATION_ACCOUNT_ID}"
