# shared/recipes/terraform.just
#
# Standard terraform recipes for propeller projects.
# Import from project justfiles:
#   import "../../shared/recipes/terraform.just"
#
# Environment variables (set by engine via CodeBuild):
#   PROJECT_NAME, PROPELLER_NAMESPACE, AWS_ACCOUNT_ID, AWS_REGION,
#   DEPLOY_ACTION, PROPELLER_INPUT_*, PROPELLER_FRAMEWORK_TAGS_JSON,
#   PROPELLER_CONSUMER_TAGS_JSON, PROPELLER_EXECUTION_ID
#
# Optional (opt-in features):
#   PROPELLER_ARCHIVE_BUCKET  — if set, uploads parsed state after apply
#   PROPELLER_PLAN_BUCKET     — if set, stores plan JSON for approval flow

_state_bucket := "state-iac-" + env("AWS_ACCOUNT_ID") + "-" + env("AWS_REGION") + "-an"
_state_key := "propeller/" + env("PROPELLER_NAMESPACE") + "/" + env("PROJECT_NAME") + "/terraform.tfstate"
_tf_dir := "terraform"
_namespace := env("PROPELLER_NAMESPACE")
_project := env("PROJECT_NAME")
_execution_id := env("PROPELLER_EXECUTION_ID", "")

# ── Core recipes ──────────────────────────────────────────────────────────────

[private]
tf-init:
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{ _tf_dir }}
    terraform init \
      -backend-config="bucket={{ _state_bucket }}" \
      -backend-config="key={{ _state_key }}" \
      -backend-config="region=${AWS_REGION}" \
      -reconfigure

[private]
tf-plan: tf-init
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{ _tf_dir }}
    terraform plan -out=tfplan $(just _propeller-vars)
    # Store plan for approval UI (opt-in)
    if [[ -n "${PROPELLER_PLAN_BUCKET:-}" ]]; then
      terraform show -json tfplan > /tmp/plan.json
      PLAN_KEY="plans/{{ _namespace }}/{{ _project }}"
      if [[ -n "{{ _execution_id }}" ]]; then
        PLAN_KEY="${PLAN_KEY}/{{ _execution_id }}.json"
      else
        PLAN_KEY="${PLAN_KEY}/latest.json"
      fi
      aws s3 cp /tmp/plan.json "s3://${PROPELLER_PLAN_BUCKET}/${PLAN_KEY}" \
        --content-type application/json
      rm -f /tmp/plan.json
    fi

[private]
tf-apply: tf-init
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{ _tf_dir }}
    terraform apply -auto-approve $(just _propeller-vars)
    just _propeller-outputs
    # Archive state (opt-in, uncomment when UI data layer is ready)
    # if [[ -n "${PROPELLER_ARCHIVE_BUCKET:-}" ]]; then
    #   just _propeller-archive-state
    # fi

[private]
tf-destroy: tf-init
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{ _tf_dir }}
    terraform destroy -auto-approve $(just _propeller-vars)

[private]
tf-outputs: tf-init
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{ _tf_dir }}
    just _propeller-outputs

# ── Sleep/Wake ────────────────────────────────────────────────────────────────
# Projects that participate in sleep/wake MUST override these recipes.
# Default: error out to prevent accidental destruction.

[private]
tf-sleep:
    @echo "ERROR: this project does not define a sleep recipe" && exit 1

[private]
tf-wake:
    @echo "ERROR: this project does not define a wake recipe" && exit 1

# ── Helpers (private) ─────────────────────────────────────────────────────────

[private]
_propeller-vars:
    #!/usr/bin/env bash
    # Collect PROPELLER_INPUT_* env vars into terraform -var flags
    ARGS=""
    while IFS='=' read -r key value; do
      var_name="${key#PROPELLER_INPUT_}"
      ARGS="$ARGS -var ${var_name}=${value}"
    done < <(env | grep '^PROPELLER_INPUT_' | sort || true)
    # Add tag vars
    if [[ -n "${PROPELLER_FRAMEWORK_TAGS_JSON:-}" ]]; then
      ARGS="$ARGS -var propeller_tags=${PROPELLER_FRAMEWORK_TAGS_JSON}"
    fi
    if [[ -n "${PROPELLER_CONSUMER_TAGS_JSON:-}" ]]; then
      ARGS="$ARGS -var consumer_tags=${PROPELLER_CONSUMER_TAGS_JSON}"
    fi
    echo "$ARGS"

[private]
_propeller-outputs:
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{ _tf_dir }}
    TF_OUT=$(terraform output -json 2>/dev/null || echo '{}')
    python3 -c "
    import json, sys
    tf = json.load(sys.stdin)
    out = {}
    for k, v in tf.items():
        val = v.get('value', '')
        out[k] = json.dumps(val) if isinstance(val, (list, dict)) else str(val)
    json.dump(out, sys.stdout, indent=2)
    " <<< "$TF_OUT" > ../.propeller-outputs.json

# [private]
# _propeller-archive-state:
#     #!/usr/bin/env bash
#     set -euo pipefail
#     cd {{ _tf_dir }}
#     TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
#     terraform show -json > /tmp/state.json
#     aws s3 cp /tmp/state.json \
#       "s3://${PROPELLER_ARCHIVE_BUCKET}/raw/{{ _namespace }}/{{ _project }}/${TS}.json" \
#       --content-type application/json
#     rm -f /tmp/state.json
