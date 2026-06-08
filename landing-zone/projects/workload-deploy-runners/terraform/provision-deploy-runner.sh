#!/usr/bin/env bash
set -euo pipefail

# Provisions (or updates) the deploy-runner Service Catalog product in a
# single workload account. Called by terraform local-exec with environment
# variables set per account.

: "${ACCOUNT_ID:?ACCOUNT_ID is required}"
: "${AWS_REGION:?AWS_REGION is required}"
: "${ASSUME_ROLE_NAME:=AWSControlTowerExecution}"
: "${PORTFOLIO_ID:?PORTFOLIO_ID is required}"
: "${PRODUCT_ID:?PRODUCT_ID is required}"
: "${PROVISIONING_ARTIFACT_ID:?PROVISIONING_ARTIFACT_ID is required}"
: "${PROVISIONED_PRODUCT_NAME:=deploy-runner}"
: "${CB_PROJECT_NAME:=deploy-runner}"

echo "=== Provisioning deploy-runner in account ${ACCOUNT_ID} (${ACCOUNT_NAME:-unnamed}) ==="

# ── Assume role into the target workload account ──────────────────────────────
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ASSUME_ROLE_NAME}"
echo "Assuming ${ROLE_ARN}..."

CREDS=$(aws sts assume-role \
  --region "${AWS_REGION}" \
  --role-arn "${ROLE_ARN}" \
  --role-session-name "provision-deploy-runner" \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)

read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN <<< "$CREDS"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

CURRENT_ACCOUNT=$(aws sts get-caller-identity --region "${AWS_REGION}" --query Account --output text)
echo "Now operating as account: ${CURRENT_ACCOUNT}"

if [ "$CURRENT_ACCOUNT" != "$ACCOUNT_ID" ]; then
  echo "ERROR: Account mismatch — expected ${ACCOUNT_ID}, got ${CURRENT_ACCOUNT}" >&2
  exit 1
fi

# ── Accept portfolio share (idempotent) ───────────────────────────────────────
echo "Accepting portfolio share..."
EXISTING_PORTFOLIO=$(aws servicecatalog list-accepted-portfolio-shares \
  --region "${AWS_REGION}" \
  --portfolio-share-type AWS_ORGANIZATIONS \
  --query "PortfolioDetails[?Id=='${PORTFOLIO_ID}'].Id | [0]" \
  --output text)

if [ "$EXISTING_PORTFOLIO" = "None" ] || [ -z "$EXISTING_PORTFOLIO" ]; then
  aws servicecatalog accept-portfolio-share \
    --region "${AWS_REGION}" \
    --portfolio-id "${PORTFOLIO_ID}" \
    --portfolio-share-type AWS_ORGANIZATIONS
  echo "Portfolio share accepted: ${PORTFOLIO_ID}"
else
  echo "Portfolio share already accepted: ${PORTFOLIO_ID}"
fi

# ── Associate principal with portfolio (idempotent) ───────────────────────────
PRINCIPAL_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ASSUME_ROLE_NAME}"
echo "Associating principal ${PRINCIPAL_ARN} with portfolio..."
aws servicecatalog associate-principal-with-portfolio \
  --region "${AWS_REGION}" \
  --portfolio-id "${PORTFOLIO_ID}" \
  --principal-arn "${PRINCIPAL_ARN}" \
  --principal-type IAM 2>/dev/null || true
echo "Principal associated."

# ── Build provisioning parameters ────────────────────────────────────────────
PARAMS=(
  "Key=ProjectName,Value=${CB_PROJECT_NAME}"
  "Key=CreateBucket,Value=true"
)

if [ -n "${S3_SOURCE_BUCKET:-}" ]; then
  PARAMS+=("Key=S3ReadBuckets,Value=${S3_SOURCE_BUCKET}")
fi

if [ -n "${CALLER_ARN:-}" ] && [ -n "${CALLER_ACCOUNT_ID:-}" ]; then
  PARAMS+=("Key=CallerARN,Value=${CALLER_ARN}")
  PARAMS+=("Key=CallerAccountId,Value=${CALLER_ACCOUNT_ID}")
fi

# ── Check existing provisioned product ────────────────────────────────────────
echo "Checking existing provisioned product '${PROVISIONED_PRODUCT_NAME}'..."
PP_STATUS=$(aws servicecatalog search-provisioned-products \
  --region "${AWS_REGION}" \
  --query "ProvisionedProducts[?Name=='${PROVISIONED_PRODUCT_NAME}'].Status | [0]" \
  --output text)

echo "Current status: ${PP_STATUS:-not found}"

# ── Terminate if in error/tainted state ───────────────────────────────────────
if [ "$PP_STATUS" = "ERROR" ] || [ "$PP_STATUS" = "TAINTED" ]; then
  echo "Previous provisioning in ${PP_STATUS} state, terminating..."
  FAILED_PP_ID=$(aws servicecatalog search-provisioned-products \
    --region "${AWS_REGION}" \
    --query "ProvisionedProducts[?Name=='${PROVISIONED_PRODUCT_NAME}'].Id | [0]" \
    --output text)
  aws servicecatalog terminate-provisioned-product \
    --region "${AWS_REGION}" \
    --provisioned-product-id "$FAILED_PP_ID"

  while true; do
    TERM_CHECK=$(aws servicecatalog search-provisioned-products \
      --region "${AWS_REGION}" \
      --query "ProvisionedProducts[?Name=='${PROVISIONED_PRODUCT_NAME}'].Status | [0]" \
      --output text)
    if [ "$TERM_CHECK" = "None" ] || [ -z "$TERM_CHECK" ]; then
      echo "Terminated successfully."
      break
    fi
    echo "Waiting for termination (status: ${TERM_CHECK})..."
    sleep 10
  done
  PP_STATUS=""
fi

# ── Update if already available, provision otherwise ──────────────────────────
if [ "$PP_STATUS" = "AVAILABLE" ]; then
  echo "Product already provisioned — updating..."
  PP_ID=$(aws servicecatalog search-provisioned-products \
    --region "${AWS_REGION}" \
    --query "ProvisionedProducts[?Name=='${PROVISIONED_PRODUCT_NAME}'].Id | [0]" \
    --output text)

  aws servicecatalog update-provisioned-product \
    --region "${AWS_REGION}" \
    --provisioned-product-id "$PP_ID" \
    --product-id "${PRODUCT_ID}" \
    --provisioning-artifact-id "${PROVISIONING_ARTIFACT_ID}" \
    --provisioning-parameters "${PARAMS[@]}" \
    --query 'RecordDetail.RecordId' \
    --output text

  while true; do
    PP_STATUS=$(aws servicecatalog describe-provisioned-product \
      --region "${AWS_REGION}" \
      --id "$PP_ID" \
      --query 'ProvisionedProductDetail.Status' \
      --output text)
    if [ "$PP_STATUS" = "AVAILABLE" ]; then
      echo "Update complete: ${PP_ID}"
      break
    elif [ "$PP_STATUS" = "ERROR" ] || [ "$PP_STATUS" = "TAINTED" ]; then
      echo "ERROR: Update failed with status: ${PP_STATUS}" >&2
      aws servicecatalog describe-provisioned-product \
        --region "${AWS_REGION}" \
        --id "$PP_ID" \
        --query 'ProvisionedProductDetail.StatusMessage' \
        --output text >&2 || true
      exit 1
    fi
    echo "Waiting for update (status: ${PP_STATUS})..."
    sleep 15
  done

elif [ "$PP_STATUS" = "UNDER_CHANGE" ]; then
  echo "Product is currently being modified — waiting for completion..."
  PP_ID=$(aws servicecatalog search-provisioned-products \
    --region "${AWS_REGION}" \
    --query "ProvisionedProducts[?Name=='${PROVISIONED_PRODUCT_NAME}'].Id | [0]" \
    --output text)

  while true; do
    PP_STATUS=$(aws servicecatalog describe-provisioned-product \
      --region "${AWS_REGION}" \
      --id "$PP_ID" \
      --query 'ProvisionedProductDetail.Status' \
      --output text)
    if [ "$PP_STATUS" = "AVAILABLE" ]; then
      echo "Product now available: ${PP_ID}"
      break
    elif [ "$PP_STATUS" = "ERROR" ] || [ "$PP_STATUS" = "TAINTED" ]; then
      echo "ERROR: Provisioning failed with status: ${PP_STATUS}" >&2
      exit 1
    fi
    echo "Waiting (status: ${PP_STATUS})..."
    sleep 15
  done

else
  echo "Provisioning new product..."
  PP_ID=$(aws servicecatalog provision-product \
    --region "${AWS_REGION}" \
    --product-id "${PRODUCT_ID}" \
    --provisioning-artifact-id "${PROVISIONING_ARTIFACT_ID}" \
    --provisioned-product-name "${PROVISIONED_PRODUCT_NAME}" \
    --provisioning-parameters "${PARAMS[@]}" \
    --query 'RecordDetail.ProvisionedProductId' \
    --output text)
  echo "Provisioning started: ${PP_ID}"

  while true; do
    PP_STATUS=$(aws servicecatalog describe-provisioned-product \
      --region "${AWS_REGION}" \
      --id "$PP_ID" \
      --query 'ProvisionedProductDetail.Status' \
      --output text)
    if [ "$PP_STATUS" = "AVAILABLE" ]; then
      echo "Provisioned product available: ${PP_ID}"
      break
    elif [ "$PP_STATUS" = "ERROR" ] || [ "$PP_STATUS" = "TAINTED" ]; then
      echo "ERROR: Provisioning failed with status: ${PP_STATUS}" >&2
      aws servicecatalog describe-provisioned-product \
        --region "${AWS_REGION}" \
        --id "$PP_ID" \
        --query 'ProvisionedProductDetail.StatusMessage' \
        --output text >&2 || true
      exit 1
    fi
    echo "Waiting for provisioning (status: ${PP_STATUS})..."
    sleep 15
  done
fi

echo "=== Done: deploy-runner provisioned in ${ACCOUNT_ID} ==="
