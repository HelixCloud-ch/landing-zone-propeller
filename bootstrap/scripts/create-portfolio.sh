#!/usr/bin/env bash
set -euo pipefail
set -x

echo "PWD: $(pwd)"
echo "PATH: $PATH"
echo "AWS CLI: $(which aws 2>/dev/null || echo 'not found')"

: "${PORTFOLIO_DISPLAY_NAME:=landing-zone-propeller}"
: "${PORTFOLIO_PROVIDER_NAME:=landing-zone-propeller}"
: "${PRODUCT_NAME:=deploy-runner}"
: "${PRODUCT_TEMPLATE_PATH:=bootstrap/cloudformation/deploy-runner.yaml}"
: "${PRODUCT_VERSION:=v1.0.2}"

# CodeBuild exposes AWS_DEFAULT_REGION; normalise to AWS_REGION for consistency
: "${AWS_REGION:=${AWS_DEFAULT_REGION:?AWS_REGION or AWS_DEFAULT_REGION is required}}"

cleanup() {
  if [ -n "${TEMP_BUCKET:-}" ]; then
    echo "--- Cleanup ephemeral bucket ---"
    aws s3 rm "s3://${TEMP_BUCKET}" --recursive 2>/dev/null || true
    aws s3api delete-bucket --bucket "$TEMP_BUCKET" 2>/dev/null || true
    echo "Ephemeral bucket deleted: ${TEMP_BUCKET}"
  fi
}
trap cleanup EXIT

# ── Validate template ────────────────────────────────────────────────────────
if [ ! -f "$PRODUCT_TEMPLATE_PATH" ]; then
  echo "Template not found: ${PRODUCT_TEMPLATE_PATH}" >&2
  exit 1
fi

# ── Upload template to ephemeral bucket ──────────────────────────────────────
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
TIMESTAMP=$(date +%s)
TEMP_BUCKET="${TIMESTAMP}-${ACCOUNT_ID}-${AWS_REGION}"
TEMPLATE_KEY="$(basename "$PRODUCT_TEMPLATE_PATH")"

echo "Creating ephemeral bucket: ${TEMP_BUCKET}"
aws s3api create-bucket --bucket "$TEMP_BUCKET" \
  --create-bucket-configuration "LocationConstraint=${AWS_REGION}"
aws s3 cp "$PRODUCT_TEMPLATE_PATH" "s3://${TEMP_BUCKET}/${TEMPLATE_KEY}"
TEMPLATE_URL="https://${TEMP_BUCKET}.s3.${AWS_REGION}.amazonaws.com/${TEMPLATE_KEY}"
echo "Template URL: ${TEMPLATE_URL}"

# ── Create or resolve portfolio ──────────────────────────────────────────────
echo "--- Create Service Catalog portfolio ---"
PORTFOLIO_ID=$(aws servicecatalog list-portfolios \
  --query "PortfolioDetails[?DisplayName=='${PORTFOLIO_DISPLAY_NAME}'].Id | [0]" \
  --output text)

if [ "$PORTFOLIO_ID" != "None" ] && [ -n "$PORTFOLIO_ID" ]; then
  echo "Portfolio already exists: ${PORTFOLIO_ID}"
else
  PORTFOLIO_ID=$(aws servicecatalog create-portfolio \
    --display-name "$PORTFOLIO_DISPLAY_NAME" \
    --provider-name "$PORTFOLIO_PROVIDER_NAME" \
    --idempotency-token "bootstrap-portfolio-$(date +%s)" \
    --query 'PortfolioDetail.Id' \
    --output text)
  echo "Portfolio created: ${PORTFOLIO_ID}"
fi

# ── Create or resolve product ────────────────────────────────────────────────
echo "--- Create Service Catalog product ---"
PRODUCT_ID=$(aws servicecatalog search-products-as-admin \
  --query "ProductViewDetails[?ProductViewSummary.Name=='${PRODUCT_NAME}'].ProductViewSummary.ProductId | [0]" \
  --output text)

if [ "$PRODUCT_ID" != "None" ] && [ -n "$PRODUCT_ID" ]; then
  echo "Product already exists: ${PRODUCT_ID}"
  
  # Check if the desired version exists and is active
  echo "--- Check provisioning artifact version ---"
  ARTIFACT_STATUS=$(aws servicecatalog list-provisioning-artifacts \
    --product-id "$PRODUCT_ID" \
    --query "ProvisioningArtifactDetails[?Name=='${PRODUCT_VERSION}'] | [0].Active" \
    --output text)
  
  if [ "$ARTIFACT_STATUS" = "True" ]; then
    echo "Product version ${PRODUCT_VERSION} is already active"
  elif [ "$ARTIFACT_STATUS" = "False" ]; then
    echo "Product version ${PRODUCT_VERSION} exists but is inactive"
    # Get the artifact ID to update it
    ARTIFACT_ID=$(aws servicecatalog list-provisioning-artifacts \
      --product-id "$PRODUCT_ID" \
      --query "ProvisioningArtifactDetails[?Name=='${PRODUCT_VERSION}'].Id | [0]" \
      --output text)
    
    echo "Activating provisioning artifact: ${ARTIFACT_ID}"
    aws servicecatalog update-provisioning-artifact \
      --product-id "$PRODUCT_ID" \
      --provisioning-artifact-id "$ARTIFACT_ID" \
      --active
    echo "Product version ${PRODUCT_VERSION} activated"
  else
    echo "Product version ${PRODUCT_VERSION} does not exist, creating new provisioning artifact"
    aws servicecatalog create-provisioning-artifact \
      --product-id "$PRODUCT_ID" \
      --parameters \
        "Name=${PRODUCT_VERSION},Info={LoadTemplateFromURL=${TEMPLATE_URL}},Type=CLOUD_FORMATION_TEMPLATE" \
      --idempotency-token "bootstrap-artifact-$(date +%s)"
    echo "Product version ${PRODUCT_VERSION} created"
  fi
else
  echo "Product does not exist, creating new product with version ${PRODUCT_VERSION}"
  IDEMPOTENCY_TOKEN="bootstrap-product-$(echo "${CODEBUILD_BUILD_ID:-manual}" | tr -cd 'a-zA-Z0-9_-')"
  PRODUCT_ID=$(aws servicecatalog create-product \
    --name "$PRODUCT_NAME" \
    --owner "$PORTFOLIO_PROVIDER_NAME" \
    --product-type CLOUD_FORMATION_TEMPLATE \
    --provisioning-artifact-parameters \
      "Name=${PRODUCT_VERSION},Info={LoadTemplateFromURL=${TEMPLATE_URL}},Type=CLOUD_FORMATION_TEMPLATE" \
    --idempotency-token "$IDEMPOTENCY_TOKEN" \
    --query 'ProductViewDetail.ProductViewSummary.ProductId' \
    --output text)
  echo "Product created: ${PRODUCT_ID}"
fi

# ── Associate product with portfolio ─────────────────────────────────────────
echo "--- Associate product with portfolio ---"
EXISTING=$(aws servicecatalog list-portfolios-for-product \
  --product-id "$PRODUCT_ID" \
  --query "PortfolioDetails[?Id=='${PORTFOLIO_ID}'].Id | [0]" \
  --output text)

if [ "$EXISTING" != "None" ] && [ -n "$EXISTING" ]; then
  echo "Product already associated with portfolio"
else
  aws servicecatalog associate-product-with-portfolio \
    --product-id "$PRODUCT_ID" \
    --portfolio-id "$PORTFOLIO_ID"
  echo "Product associated with portfolio: ${PORTFOLIO_ID}"
fi

echo "Done."
