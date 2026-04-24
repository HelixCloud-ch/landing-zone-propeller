#!/usr/bin/env bash
set -euo pipefail
set -x

: "${AWS_REGION:=${AWS_DEFAULT_REGION:?AWS_REGION or AWS_DEFAULT_REGION is required}}"
: "${LOG_ARCHIVE_EMAIL:=}"
: "${AUDIT_EMAIL:=}"
: "${BACKUP_ADMIN_EMAIL:=}"
: "${BACKUP_CENTRAL_EMAIL:=}"
: "${CREATE_IAM_ROLES:=true}"
: "${TF_DIR:=projects/management/control-tower-prerequisites/terraform}"
: "${TF_VERSION:=1.14.9}"
: "${STATE_BUCKET_PREFIX:=state-iac}"
: "${TF_STATE_KEY:=tf-states/platform/management/control-tower-prerequisites/terraform.tfstate}"
: "${ACTION:=plan}"

# ── Resolve MPA account ID and state bucket ──────────────────────────────────
MPA_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
STATE_BUCKET="${STATE_BUCKET_PREFIX}-${MPA_ACCOUNT_ID}-${AWS_REGION}"

echo "  MPA account  : ${MPA_ACCOUNT_ID}"
echo "  State bucket : ${STATE_BUCKET}"
echo "  TF state key : ${TF_STATE_KEY}"
echo "  Action       : ${ACTION}"

# ── Install Terraform if not available ───────────────────────────────────────
if ! command -v terraform &>/dev/null; then
  echo "--- Installing Terraform ${TF_VERSION} ---"
  curl -sL "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip" \
    -o /tmp/terraform.zip
  unzip -qo /tmp/terraform.zip -d /usr/local/bin
  terraform version
fi

# ── Validate Terraform directory ─────────────────────────────────────────────
if [ ! -d "$TF_DIR" ]; then
  echo "Terraform directory not found: ${TF_DIR}" >&2
  exit 1
fi

# ── Build optional var flags ──────────────────────────────────────────────────
BACKUP_VARS=""
if [ -n "$BACKUP_ADMIN_EMAIL" ] && [ -n "$BACKUP_CENTRAL_EMAIL" ]; then
  BACKUP_VARS="-var=backup_admin_account_email=${BACKUP_ADMIN_EMAIL} -var=backup_central_account_email=${BACKUP_CENTRAL_EMAIL}"
  echo "  Backup       : enabled (admin + central accounts)"
else
  echo "  Backup       : disabled (no backup emails provided)"
fi

echo "  IAM roles    : ${CREATE_IAM_ROLES}"

# ── Run Terraform ────────────────────────────────────────────────────────────
echo "--- Terraform init ---"
terraform -chdir="$TF_DIR" init \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="key=${TF_STATE_KEY}" \
  -backend-config="region=${AWS_REGION}"

if [ "$ACTION" = "apply" ]; then
  echo "--- Terraform apply ---"
  terraform -chdir="$TF_DIR" apply -auto-approve \
    -var="region=${AWS_REGION}" \
    -var="log_archive_account_email=${LOG_ARCHIVE_EMAIL}" \
    -var="audit_account_email=${AUDIT_EMAIL}" \
    -var="create_iam_roles=${CREATE_IAM_ROLES}" \
    $BACKUP_VARS
else
  echo "--- Terraform plan ---"
  terraform -chdir="$TF_DIR" plan \
    -var="region=${AWS_REGION}" \
    -var="log_archive_account_email=${LOG_ARCHIVE_EMAIL}" \
    -var="audit_account_email=${AUDIT_EMAIL}" \
    -var="create_iam_roles=${CREATE_IAM_ROLES}" \
    $BACKUP_VARS
fi

echo "Done."
