#!/usr/bin/env bash
set -euo pipefail
set -x

: "${PORTFOLIO_DISPLAY_NAME:=landing-zone-propeller}"

# ── Resolve portfolio ID ─────────────────────────────────────────────────────
echo "--- Resolve portfolio ID ---"
PORTFOLIO_ID=$(aws servicecatalog list-portfolios \
  --query "PortfolioDetails[?DisplayName=='${PORTFOLIO_DISPLAY_NAME}'].Id | [0]" \
  --output text)

if [ "$PORTFOLIO_ID" = "None" ] || [ -z "$PORTFOLIO_ID" ]; then
  echo "Portfolio '${PORTFOLIO_DISPLAY_NAME}' not found. Run deploy-service-catalog first." >&2
  exit 1
fi
echo "Portfolio ID: ${PORTFOLIO_ID}"

# ── Enable Service Catalog integration with Organizations ────────────────────
echo "--- Enable Service Catalog integration with Organizations ---"
aws organizations enable-aws-service-access \
  --service-principal servicecatalog.amazonaws.com

# ── Share portfolio with organization ────────────────────────────────────────
echo "--- Share portfolio with organization ---"
ORG_ID=$(aws organizations describe-organization \
  --query 'Organization.Id' --output text)

SHARED=$(aws servicecatalog describe-portfolio-shares \
  --portfolio-id "$PORTFOLIO_ID" \
  --type ORGANIZATION \
  --query "PortfolioShareDetails[?PrincipalId=='${ORG_ID}'].PrincipalId | [0]" \
  --output text)

if [ "$SHARED" != "None" ] && [ -n "$SHARED" ]; then
  echo "Portfolio already shared with organization ${ORG_ID}"
else
  aws servicecatalog create-portfolio-share \
    --portfolio-id "$PORTFOLIO_ID" \
    --organization-node "Type=ORGANIZATION,Value=${ORG_ID}"
  echo "Portfolio shared with organization: ${ORG_ID}"
fi

echo "Done."
