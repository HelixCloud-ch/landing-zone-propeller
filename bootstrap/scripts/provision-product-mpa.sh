#!/usr/bin/env bash
set -euo pipefail
set -x

: "${AWS_REGION:=${AWS_DEFAULT_REGION:?AWS_REGION or AWS_DEFAULT_REGION is required}}"
: "${PROVISIONED_PRODUCT_NAME:=deploy-runner}"
: "${CB_PROJECT_NAME:=deploy-runner}"
: "${PORTFOLIO_DISPLAY_NAME:=landing-zone-propeller}"
: "${PRODUCT_NAME:=deploy-runner}"
: "${OPERATION_ACCOUNT_NAME:=operations}"
: "${CALLER_ROLE_NAME:=landing-zone-propeller-sfn-role}"

# ── Resolve PRODUCT_ID from name if not provided ─────────────────────────────
if [ -z "${PRODUCT_ID:-}" ]; then
  echo "--- Resolving product ID from name '${PRODUCT_NAME}' ---"
  PRODUCT_ID=$(aws servicecatalog search-products-as-admin \
    --query "ProductViewDetails[?ProductViewSummary.Name=='${PRODUCT_NAME}'].ProductViewSummary.ProductId | [0]" \
    --output text)
  if [ "$PRODUCT_ID" = "None" ] || [ -z "$PRODUCT_ID" ]; then
    echo "Product '${PRODUCT_NAME}' not found. Run create-portfolio first." >&2
    exit 1
  fi
  echo "Product ID: ${PRODUCT_ID}"
fi

# ── Resolve ARTIFACT_ID: latest active artifact if not provided ──────────────
if [ -z "${ARTIFACT_ID:-}" ]; then
  echo "--- Resolving latest active artifact for product '${PRODUCT_ID}' ---"
  ARTIFACT_ID=$(aws servicecatalog list-provisioning-artifacts \
    --product-id "$PRODUCT_ID" \
    --query "ProvisioningArtifactDetails[?Active==\`true\` && Guidance=='DEFAULT'] | sort_by(@, &CreatedTime) | [-1].Id" \
    --output text)
  if [ "$ARTIFACT_ID" = "None" ] || [ -z "$ARTIFACT_ID" ]; then
    echo "No active provisioning artifact found for product '${PRODUCT_ID}'" >&2
    exit 1
  fi
  echo "Artifact ID: ${ARTIFACT_ID}"
fi

# ── Resolve operation account ID ─────────────────────────────────────────────
if [ -z "${OPERATION_ACCOUNT_ID:-}" ]; then
  echo "--- Resolving operation account '${OPERATION_ACCOUNT_NAME}' from org root ---"
  ORG_ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
  OPERATION_ACCOUNT_ID=$(aws organizations list-accounts-for-parent \
    --parent-id "$ORG_ROOT_ID" \
    --query "Accounts[?Name=='${OPERATION_ACCOUNT_NAME}' && Status=='ACTIVE'].Id | [0]" \
    --output text)
  if [ "$OPERATION_ACCOUNT_ID" = "None" ] || [ -z "$OPERATION_ACCOUNT_ID" ]; then
    echo "Account '${OPERATION_ACCOUNT_NAME}' not found in org root. Run create-operation-account first." >&2
    exit 1
  fi
  echo "Operation account ID: ${OPERATION_ACCOUNT_ID}"
fi

: "${OPERATION_SOURCE_BUCKET:=source-${OPERATION_ACCOUNT_ID}-${AWS_REGION}}"
: "${CALLER_ARN:=arn:aws:iam::${OPERATION_ACCOUNT_ID}:role/${CALLER_ROLE_NAME}}"
: "${CALLER_ACCOUNT_ID:=${OPERATION_ACCOUNT_ID}}"

PROVISIONING_PARAMS=( \
  "Key=ProjectName,Value=${CB_PROJECT_NAME}" \
  "Key=CreateBucket,Value=true" \
  "Key=S3ReadBuckets,Value=${OPERATION_SOURCE_BUCKET}" \
  "Key=CallerARN,Value=${CALLER_ARN}" \
  "Key=CallerAccountId,Value=${CALLER_ACCOUNT_ID}" \
)

echo "--- Provision product in MPA ---"
echo "  Operation account : ${OPERATION_ACCOUNT_ID}"
echo "  Product ID        : ${PRODUCT_ID}"
echo "  Artifact ID       : ${ARTIFACT_ID}"
echo "  Provisioned name  : ${PROVISIONED_PRODUCT_NAME}"
echo "  CB project name   : ${CB_PROJECT_NAME}"
echo "  Source bucket      : ${OPERATION_SOURCE_BUCKET}"
echo "  Caller ARN         : ${CALLER_ARN}"
echo "  Caller account     : ${CALLER_ACCOUNT_ID}"

# ── Ensure caller has access to the portfolio ────────────────────────────────
echo "--- Ensure portfolio access for caller ---"
PORTFOLIO_ID=$(aws servicecatalog list-portfolios \
  --query "PortfolioDetails[?DisplayName=='${PORTFOLIO_DISPLAY_NAME}'].Id | [0]" \
  --output text)
if [ "$PORTFOLIO_ID" = "None" ] || [ -z "$PORTFOLIO_ID" ]; then
  echo "Portfolio '${PORTFOLIO_DISPLAY_NAME}' not found." >&2
  exit 1
fi

BOOTSTRAP_CALLER_ARN=$(aws sts get-caller-identity --query Arn --output text)
if echo "$BOOTSTRAP_CALLER_ARN" | grep -q ':assumed-role/'; then
  ACCOUNT=$(echo "$BOOTSTRAP_CALLER_ARN" | cut -d: -f5)
  ROLE_NAME=$(echo "$BOOTSTRAP_CALLER_ARN" | sed 's|.*:assumed-role/||; s|/.*||')
  BOOTSTRAP_CALLER_ARN="arn:aws:iam::${ACCOUNT}:role/${ROLE_NAME}"
fi
echo "  Portfolio ID : ${PORTFOLIO_ID}"
echo "  Caller ARN   : ${BOOTSTRAP_CALLER_ARN}"

aws servicecatalog associate-principal-with-portfolio \
  --portfolio-id "$PORTFOLIO_ID" \
  --principal-arn "$BOOTSTRAP_CALLER_ARN" \
  --principal-type IAM
echo "Portfolio access granted to: ${BOOTSTRAP_CALLER_ARN}"

# ── Check existing provisioned product ───────────────────────────────────────
PP_STATUS=$(aws servicecatalog search-provisioned-products \
  --query "ProvisionedProducts[?Name=='${PROVISIONED_PRODUCT_NAME}'].Status | [0]" \
  --output text)

# ── Terminate if in error state ──────────────────────────────────────────────
if [ "$PP_STATUS" = "ERROR" ] || [ "$PP_STATUS" = "TAINTED" ]; then
  echo "Previous provisioning in ${PP_STATUS} state, terminating..."
  FAILED_PP_ID=$(aws servicecatalog search-provisioned-products \
    --query "ProvisionedProducts[?Name=='${PROVISIONED_PRODUCT_NAME}'].Id | [0]" \
    --output text)
  aws servicecatalog terminate-provisioned-product \
    --provisioned-product-id "$FAILED_PP_ID"

  while true; do
    TERM_CHECK=$(aws servicecatalog search-provisioned-products \
      --query "ProvisionedProducts[?Name=='${PROVISIONED_PRODUCT_NAME}'].Status | [0]" \
      --output text)
    if [ "$TERM_CHECK" = "None" ] || [ -z "$TERM_CHECK" ]; then
      echo "Terminated successfully"
      break
    fi
    echo "Waiting for termination (status: ${TERM_CHECK})..."
    sleep 10
  done
  PP_STATUS=""
fi

# ── Update if already available, provision otherwise ─────────────────────────
if [ "$PP_STATUS" = "AVAILABLE" ]; then
  echo "Product already provisioned — updating..."
  PP_ID=$(aws servicecatalog search-provisioned-products \
    --query "ProvisionedProducts[?Name=='${PROVISIONED_PRODUCT_NAME}'].Id | [0]" \
    --output text)

  aws servicecatalog update-provisioned-product \
    --provisioned-product-id "$PP_ID" \
    --product-id "$PRODUCT_ID" \
    --provisioning-artifact-id "$ARTIFACT_ID" \
    --provisioning-parameters "${PROVISIONING_PARAMS[@]}" \
    --query 'RecordDetail.RecordId' \
    --output text

  while true; do
    PP_STATUS=$(aws servicecatalog describe-provisioned-product \
      --id "$PP_ID" \
      --query 'ProvisionedProductDetail.Status' \
      --output text)
    if [ "$PP_STATUS" = "AVAILABLE" ]; then
      echo "Update complete: ${PP_ID}"
      break
    elif [ "$PP_STATUS" = "ERROR" ] || [ "$PP_STATUS" = "TAINTED" ]; then
      echo "Update failed with status: ${PP_STATUS}" >&2
      exit 1
    fi
    echo "Waiting for update (status: ${PP_STATUS})..."
    sleep 15
  done
else
  PP_ID=$(aws servicecatalog provision-product \
    --product-id "$PRODUCT_ID" \
    --provisioning-artifact-id "$ARTIFACT_ID" \
    --provisioned-product-name "$PROVISIONED_PRODUCT_NAME" \
    --provisioning-parameters "${PROVISIONING_PARAMS[@]}" \
    --query 'RecordDetail.ProvisionedProductId' \
    --output text)
  echo "Provisioning started: ${PP_ID}"

  while true; do
    PP_STATUS=$(aws servicecatalog describe-provisioned-product \
      --id "$PP_ID" \
      --query 'ProvisionedProductDetail.Status' \
      --output text)
    if [ "$PP_STATUS" = "AVAILABLE" ]; then
      echo "Provisioned product available: ${PP_ID}"
      break
    elif [ "$PP_STATUS" = "ERROR" ] || [ "$PP_STATUS" = "TAINTED" ]; then
      echo "Provisioning failed with status: ${PP_STATUS}" >&2
      exit 1
    fi
    echo "Waiting for provisioning (status: ${PP_STATUS})..."
    sleep 15
  done
fi

echo "Done."
