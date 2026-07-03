#!/usr/bin/env bash
# Runs a bootstrap script inside the CodeBuild bootstrap project.
# See bootstrap/README.md for setup instructions.
#
# Usage:
#   $RUN <script-name> [KEY=VALUE ...]
#
# Examples:
#   $RUN deploy-autopilot.sh
#   $RUN create-operations-account.sh OPERATIONS_EMAIL=ops@acme.com
#   $RUN provision-product-mpa.sh

set -euo pipefail

# ── Validate prerequisites ───────────────────────────────────────────────────
: "${TARGET_REGION:?TARGET_REGION is required}"
: "${LZP_ZIP_URL:?LZP_ZIP_URL is required}"
: "${CB_PROJECT:?CB_PROJECT is required}"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <script-name> [KEY=VALUE ...]" >&2
  exit 1
fi

SCRIPT_NAME="$1"
shift

# ── Build environment variable overrides ─────────────────────────────────────
# LZP_ZIP_URL is always injected so the script can download the source.
ENV_OVERRIDES=("name=LZP_ZIP_URL,value=${LZP_ZIP_URL},type=PLAINTEXT")

for kv in "$@"; do
  KEY="${kv%%=*}"
  VAL="${kv#*=}"
  ENV_OVERRIDES+=("name=${KEY},value=${VAL},type=PLAINTEXT")
done

# ── Inline buildspec — identical for every script ────────────────────────────
INLINE_BUILDSPEC="version: 0.2
phases:
  build:
    commands:
      - curl -sL \"\$LZP_ZIP_URL\" -o /tmp/lzp.zip
      - unzip -qo /tmp/lzp.zip -d /tmp/lzp
      - |
        cd /tmp/lzp/landing-zone-propeller-*
        chmod +x bootstrap/scripts/${SCRIPT_NAME}
        ./bootstrap/scripts/${SCRIPT_NAME}"

# ── Start build ───────────────────────────────────────────────────────────────
echo "Starting build: ${SCRIPT_NAME}"
echo "  Project : ${CB_PROJECT}"
echo "  Region  : ${TARGET_REGION}"
echo "  Source  : ${LZP_ZIP_URL}"

BUILD_ID=$(aws codebuild start-build \
  --region "$TARGET_REGION" \
  --project-name "$CB_PROJECT" \
  --buildspec-override "$INLINE_BUILDSPEC" \
  --environment-variables-override "${ENV_OVERRIDES[@]}" \
  --query 'build.id' --output text)

echo "Build ID: ${BUILD_ID}"
echo "Console : https://${TARGET_REGION}.console.aws.amazon.com/codesuite/codebuild/projects/${CB_PROJECT}/build/${BUILD_ID}/log"

# ── Poll until complete ───────────────────────────────────────────────────────
while true; do
  STATUS=$(aws codebuild batch-get-builds \
    --region "$TARGET_REGION" \
    --ids "$BUILD_ID" \
    --query 'builds[0].buildStatus' --output text)
  echo "Status: ${STATUS}"
  [ "$STATUS" != "IN_PROGRESS" ] && break
  sleep 15
done

if [ "$STATUS" != "SUCCEEDED" ]; then
  echo "Build ${STATUS}. Check logs in the CodeBuild console." >&2
  exit 1
fi

echo "Done."
