/**
 * Shared constants for the Propeller Autopilot pipeline executor.
 */

/** SSM prefix for account metadata (id, region). */
export const ACCOUNTS_SSM_PREFIX = "/propeller/accounts";

/** SSM prefix for pipeline project blobs. */
export const PIPELINE_SSM_PREFIX = "/propeller";

/** Sentinel value stored in SSM to represent an intentionally empty string. */
export const EMPTY_SENTINEL = "__EMPTY__";

/** Default CodeBuild project name for running deployments. */
export const CODEBUILD_PROJECT_NAME = "deploy-runner";

/** Default IAM role name assumed in target accounts for CodeBuild execution. */
export const RUN_ROLE_NAME = "deploy-runner-run-role";

/** Interval in seconds between CodeBuild status polls. */
export const POLL_INTERVAL_SECONDS = 15;

/** Terminal build statuses that indicate a build has completed. */
export const TERMINAL_BUILD_STATUSES: Set<string> = new Set([
  "SUCCEEDED",
  "FAILED",
  "FAULT",
  "STOPPED",
  "TIMED_OUT",
]);

/** Default buildspec used by CodeBuild for running project deploys. */
export const BUILDSPEC = `version: 0.2

env:
  variables:
    PROJECT_NAME: ""
    PROPELLER_NAMESPACE: ""
    DEPLOY_ACTION: "plan"
    AWS_ACCOUNT_ID: ""
    AWS_REGION: ""
    TF_VERSION: "1.14.9"
    JUST_VERSION: "1.51.0"
    PROPELLER_OUTPUTS_JSON: "{}"
    PROPELLER_FRAMEWORK_TAGS_JSON: "{}"
    PROPELLER_CONSUMER_TAGS_JSON: "{}"
    PROPELLER_EXECUTION_ID: ""
    PROPELLER_VERSION: ""
    PROPELLER_SAVED_PLAN: ""
    PROPELLER_SLEEP_MODE: ""
  exported-variables:
    - PROPELLER_OUTPUTS_JSON

phases:
  install:
    commands:
      # Each install is guarded so a baked image (with the tools already present,
      # and an offline/private VPC with no egress) does no downloads.
      - command -v terraform >/dev/null || { curl -fsSL "https://releases.hashicorp.com/terraform/\${TF_VERSION}/terraform_\${TF_VERSION}_linux_amd64.zip" -o /tmp/tf.zip && unzip -o /tmp/tf.zip -d /usr/local/bin/; }
      - command -v just >/dev/null || curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --tag \${JUST_VERSION} --to /usr/local/bin

  build:
    commands:
      - cd bundle
      # Resolve the project's bundle dir from the lock with jq. The engine is no
      # longer used at deploy; just runs the project's justfile directly.
      - PROJECT_DIR="$PWD/$(jq -r --arg p "$PROJECT_NAME" '.stages[].steps[] | select(.project == $p) | .source' pipeline.lock.json)"
      - test -d "$PROJECT_DIR" || { echo "project '$PROJECT_NAME' not found in pipeline.lock.json"; exit 1; }
      - cd "$PROJECT_DIR"
      - just $DEPLOY_ACTION
      - export PROPELLER_OUTPUTS_JSON=$(cat "$PROJECT_DIR/.propeller-outputs.json" 2>/dev/null || echo '{}')
`;
