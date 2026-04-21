#!/usr/bin/env bash
set -euo pipefail
set -x

: "${AWS_REGION:=${AWS_DEFAULT_REGION:?AWS_REGION or AWS_DEFAULT_REGION is required}}"
: "${OPERATION_ACCOUNT_NAME:=operations}"
: "${OPERATION_ROLE_NAME:=AWSControlTowerExecution}"
: "${STS_REGION:=us-east-1}"
: "${PORTFOLIO_DISPLAY_NAME:=landing-zone-propeller}"
: "${PRODUCT_NAME:=deploy-runner}"
: "${PROVISIONED_PRODUCT_NAME:=deploy-runner}"
: "${CB_PROJECT_NAME:=deploy-runner}"

# ── Resolve operation account ID ─────────────────────────────────────────────
if [ -z "${OPERATION_ACCOUNT_ID:-}" ]; then
  echo "--- Resolving operation account '${OPERATION_ACCOUNT_NAME}' from org root ---"
  ORG_ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
  OPERATION_ACCOUNT_ID=$(aws organizations list-accounts-for-parent \
    --parent-id "$ORG_ROOT_ID" \
    --query "Accounts[?Name=='${OPERATION_ACCOUNT_NAME}' && Status=='ACTIVE'].Id | [0]" \
    --output text)
  if [ "$OPERATION_ACCOUNT_ID" = "None" ] || [ -z "$OPERATION_ACCOUNT_ID" ]; then
    echo "Account '${OPERATION_ACCOUNT_NAME}' not found." >&2
    exit 1
  fi
fi
echo "Operation account ID: ${OPERATION_ACCOUNT_ID}"

: "${OPERATION_SOURCE_BUCKET:=source-${OPERATION_ACCOUNT_ID}-${AWS_REGION}}"

# ── Assume role in operation account ─────────────────────────────────────────
ROLE_ARN="arn:aws:iam::${OPERATION_ACCOUNT_ID}:role/${OPERATION_ROLE_NAME}"
echo "--- Assuming ${OPERATION_ROLE_NAME} in ${OPERATION_ACCOUNT_ID} (via ${STS_REGION}) ---"

CREDS=$(aws sts assume-role \
  --region "$STS_REGION" \
  --role-arn "$ROLE_ARN" \
  --role-session-name "bootstrap-deploy-product" \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)

export $(printf "AWS_ACCESS_KEY_ID=%s AWS_SECRET_ACCESS_KEY=%s AWS_SESSION_TOKEN=%s" $CREDS)

CURRENT_ACCOUNT=$(aws sts get-caller-identity --region "$STS_REGION" --query Account --output text)
echo "Now operating as: ${CURRENT_ACCOUNT} ($(aws sts get-caller-identity --region "$STS_REGION" --query Arn --output text))"

if [ "$CURRENT_ACCOUNT" != "$OPERATION_ACCOUNT_ID" ]; then
  echo "Account mismatch" >&2
  exit 1
fi

# ── Accept portfolio share from organization ─────────────────────────────────
echo "--- Accept portfolio share ---"
PORTFOLIO_ID=$(aws servicecatalog list-accepted-portfolio-shares \
  --region "$AWS_REGION" \
  --portfolio-share-type AWS_ORGANIZATIONS \
  --query "PortfolioDetails[?DisplayName=='${PORTFOLIO_DISPLAY_NAME}'].Id | [0]" \
  --output text)

if [ "$PORTFOLIO_ID" != "None" ] && [ -n "$PORTFOLIO_ID" ]; then
  echo "Portfolio share already accepted: ${PORTFOLIO_ID}"
else
  # List available org shares and accept the matching one
  PORTFOLIO_ID=$(aws servicecatalog list-portfolios \
    --region "$AWS_REGION" \
    --query "PortfolioDetails[?DisplayName=='${PORTFOLIO_DISPLAY_NAME}'].Id | [0]" \
    --output text)

  if [ "$PORTFOLIO_ID" = "None" ] || [ -z "$PORTFOLIO_ID" ]; then
    echo "Portfolio '${PORTFOLIO_DISPLAY_NAME}' not found. Run share-service-catalog first." >&2
    exit 1
  fi

  aws servicecatalog accept-portfolio-share \
    --region "$AWS_REGION" \
    --portfolio-id "$PORTFOLIO_ID" \
    --portfolio-share-type AWS_ORGANIZATIONS
  echo "Portfolio share accepted: ${PORTFOLIO_ID}"
fi

# ── Grant caller access to the portfolio ─────────────────────────────────────
echo "--- Grant portfolio access ---"
CALLER_ARN=$(aws sts get-caller-identity --region "$STS_REGION" --query Arn --output text)
if echo "$CALLER_ARN" | grep -q ':assumed-role/'; then
  ACCOUNT=$(echo "$CALLER_ARN" | cut -d: -f5)
  ROLE_NAME_PART=$(echo "$CALLER_ARN" | sed 's|.*:assumed-role/||; s|/.*||')
  CALLER_ARN="arn:aws:iam::${ACCOUNT}:role/${ROLE_NAME_PART}"
fi
echo "  Caller ARN: ${CALLER_ARN}"

aws servicecatalog associate-principal-with-portfolio \
  --region "$AWS_REGION" \
  --portfolio-id "$PORTFOLIO_ID" \
  --principal-arn "$CALLER_ARN" \
  --principal-type IAM
echo "Portfolio access granted"

# ── Resolve product and artifact ─────────────────────────────────────────────
echo "--- Resolve product ---"
PRODUCT_ID=$(aws servicecatalog search-products \
  --region "$AWS_REGION" \
  --query "ProductViewSummaries[?Name=='${PRODUCT_NAME}'].ProductId | [0]" \
  --output text)

if [ "$PRODUCT_ID" = "None" ] || [ -z "$PRODUCT_ID" ]; then
  echo "Product '${PRODUCT_NAME}' not found in accepted portfolios." >&2
  exit 1
fi
echo "Product ID: ${PRODUCT_ID}"

echo "--- Resolve latest active artifact ---"
ARTIFACT_ID=$(aws servicecatalog list-provisioning-artifacts \
  --region "$AWS_REGION" \
  --product-id "$PRODUCT_ID" \
  --query "ProvisioningArtifactDetails[?Active==\`true\` && Guidance=='DEFAULT'] | sort_by(@, &CreatedTime) | [-1].Id" \
  --output text)

if [ "$ARTIFACT_ID" = "None" ] || [ -z "$ARTIFACT_ID" ]; then
  echo "No active provisioning artifact found for product '${PRODUCT_ID}'" >&2
  exit 1
fi
echo "Artifact ID: ${ARTIFACT_ID}"

# ── Check existing provisioned product ───────────────────────────────────────
echo "--- Provision product in operation account ---"
echo "  Product ID       : ${PRODUCT_ID}"
echo "  Artifact ID      : ${ARTIFACT_ID}"
echo "  Provisioned name : ${PROVISIONED_PRODUCT_NAME}"
echo "  CB project name  : ${CB_PROJECT_NAME}"
echo "  Source bucket     : ${OPERATION_SOURCE_BUCKET}"

PP_STATUS=$(aws servicecatalog search-provisioned-products \
  --region "$AWS_REGION" \
  --query "ProvisionedProducts[?Name=='${PROVISIONED_PRODUCT_NAME}'].Status | [0]" \
  --output text)

# ── Terminate if in error state ──────────────────────────────────────────────
if [ "$PP_STATUS" = "ERROR" ] || [ "$PP_STATUS" = "TAINTED" ]; then
  echo "Previous provisioning in ${PP_STATUS} state, terminating..."
  FAILED_PP_ID=$(aws servicecatalog search-provisioned-products \
    --region "$AWS_REGION" \
    --query "ProvisionedProducts[?Name=='${PROVISIONED_PRODUCT_NAME}'].Id | [0]" \
    --output text)
  aws servicecatalog terminate-provisioned-product \
    --region "$AWS_REGION" \
    --provisioned-product-id "$FAILED_PP_ID"

  while true; do
    TERM_CHECK=$(aws servicecatalog search-provisioned-products \
      --region "$AWS_REGION" \
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

# ── Provision if not already available ───────────────────────────────────────
if [ "$PP_STATUS" = "AVAILABLE" ]; then
  echo "Product already provisioned in operation account"
else
  PP_ID=$(aws servicecatalog provision-product \
    --region "$AWS_REGION" \
    --product-id "$PRODUCT_ID" \
    --provisioning-artifact-id "$ARTIFACT_ID" \
    --provisioned-product-name "$PROVISIONED_PRODUCT_NAME" \
    --provisioning-parameters \
      "Key=ProjectName,Value=${CB_PROJECT_NAME}" \
      "Key=CreateBucket,Value=true" \
      "Key=S3ReadBuckets,Value=${OPERATION_SOURCE_BUCKET}" \
    --query 'RecordDetail.ProvisionedProductId' \
    --output text)
  echo "Provisioning started: ${PP_ID}"

  while true; do
    PP_STATUS=$(aws servicecatalog describe-provisioned-product \
      --region "$AWS_REGION" \
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
