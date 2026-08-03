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
    PROPELLER_SAVED_PLAN: ""
    PROPELLER_SLEEP_MODE: ""
  exported-variables:
    - PROPELLER_OUTPUTS_JSON

phases:
  install:
    commands:
      - curl -fsSL "https://releases.hashicorp.com/terraform/\${TF_VERSION}/terraform_\${TF_VERSION}_linux_amd64.zip" -o /tmp/tf.zip
      - unzip -o /tmp/tf.zip -d /usr/local/bin/
      - curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --tag \${JUST_VERSION} --to /usr/local/bin
      - curl -LsSf https://astral.sh/uv/install.sh | sh
      - export PATH="$HOME/.local/bin:$PATH"

  build:
    commands:
      - cd bundle
      - PROJECT_DIR=$(uv run --project engine propeller-deploy --pipeline pipeline.lock.yaml --project "$PROJECT_NAME" project-dir)
      - |
        if [ -f "$PROJECT_DIR/justfile" ]; then
          cd "$PROJECT_DIR"
          just $DEPLOY_ACTION
        else
          # Legacy path — remove once all projects have justfiles
          uv run --project engine propeller-deploy --pipeline pipeline.lock.yaml --project "$PROJECT_NAME" init
          uv run --project engine propeller-deploy --pipeline pipeline.lock.yaml --project "$PROJECT_NAME" $DEPLOY_ACTION
        fi
      - export PROPELLER_OUTPUTS_JSON=$(cat "$PROJECT_DIR/.propeller-outputs.json" 2>/dev/null || echo '{}')
`;
