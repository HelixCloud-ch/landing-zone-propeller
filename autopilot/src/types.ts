/**
 * Core type definitions for the Propeller Autopilot pipeline executor.
 *
 * These types model the full pipeline event shape, step configuration,
 * build results, SSM state, and sleep/wake behavior.
 */

// --- Pipeline Event (Lambda input) ---

/** Top-level event received by the autopilot Lambda handler. */
export interface PipelineEvent {
  /** The pipeline definition with stages and steps. */
  pipeline: PipelineDefinition;
  /** S3 URI to the bundled source artifact (e.g. s3://bucket/key.zip). */
  bundle_s3_uri: string;
  /** Deployment action: apply, plan, destroy, sleep, or wake. */
  deploy_action: DeployAction;
  /** Git commit SHA that triggered this execution. */
  git_sha?: string;
  /** Optional filter — only execute these project names. */
  only?: string[];
  /** Deploy mode: "supervised" pauses every project for approval after plan. */
  deploy_mode?: "autopilot" | "supervised";
  /** When true, allows destroy action to target all projects (safety gate). */
  destroy_all?: boolean;
  /** Named sleep preset to use (resolved from pipeline.sleep_presets). */
  sleep_preset?: string;
  /** Force apply even if pipeline is in sleeping state. */
  force?: boolean;
}

export type DeployAction = "apply" | "plan" | "destroy" | "sleep" | "wake";

export interface PipelineDefinition {
  /** Version of the pipeline schema (currently "1"). */
  version: string;
  /** Pipeline namespace — typically the platform name (e.g. "test-gecotinext"). */
  namespace: string;
  /** Ordered list of stages to execute. */
  stages: Stage[];
  /** Propeller framework version used to generate this pipeline. */
  propeller_version?: string;
  /** Consumer-defined tags applied to all resources. */
  consumer_tags?: Record<string, string>;
  /**
   * Named sleep presets. Each preset maps project names to sleep modes.
   * Projects not listed in a preset don't participate in that sleep cycle.
   */
  sleep_presets?: Record<string, Record<string, string>>;
}

export interface Stage {
  /** Stage name (e.g. "network", "cluster"). */
  name: string;
  /** Steps within this stage — may run in parallel respecting depends_on. */
  steps: StepConfig[];
  /** If true (default), all steps in this stage must complete before the next stage starts. If false, this stage is purely a visual group and steps are eligible as soon as their dependencies are met. */
  barrier?: boolean;
}

// --- Step Configuration ---

/** Configuration for a single project deployment step within a stage. */
export interface StepConfig {
  /** Unique project name within the pipeline (e.g. "workload-vpc"). */
  project: string;
  /** Source project template name (defaults to project name if omitted). */
  source?: string;
  /** Target account alias (resolved via SSM). */
  target?: string;
  /** Custom CodeBuild runner project name. */
  runner?: string;
  /** Projects this step depends on (must complete first). */
  depends_on?: string[];
  /** Input variable mappings. */
  inputs?: StepInput[];
  /** Output definitions to persist after successful apply. */
  outputs?: StepOutput[];
  /** @deprecated Use sleep_presets on PipelineDefinition instead. */
  sleep?: boolean;
  /** @deprecated Use sleep_presets on PipelineDefinition instead. */
  sleep_config?: SleepConfig;
  /** Build timeout override in minutes. */
  timeout?: number;
  /** Framework-injected tags for this step. */
  propeller_tags?: Record<string, string>;
  /** If "required", this project pauses for approval after plan (even in autopilot mode). */
  approval?: "required";
}

/**
 * Resolved input variable mapping for a step.
 *
 * This is the format AFTER the resolver processes the pipeline — the
 * Lambda receives these, not the shorthand "name" format from pipeline.yaml.
 */
export interface StepInput {
  /** SSM parameter path to read (e.g. "/propeller/test-platform/vpc"). */
  key: string;
  /** Field name within the project blob JSON. If absent, reads the raw parameter value. */
  field?: string;
  /** Variable name exposed to the build environment as PROPELLER_INPUT_<var>. */
  var: string;
}

/**
 * Resolved output definition for a step.
 *
 * After a successful apply, the engine reads PROPELLER_OUTPUTS_JSON from
 * the build and writes each output to SSM.
 */
export interface StepOutput {
  /** SSM parameter path to write (for individual params) or blob path. */
  key: string;
  /** Output field name as it appears in PROPELLER_OUTPUTS_JSON. */
  ref: string;
  /** If present, stores this output as a field in the project's JSON blob rather than as an individual SSM parameter. */
  field?: string;
}

// --- Sleep/Wake ---

export type SleepAction = "destroy" | "command" | "skip";

/** Sleep configuration from project.yaml. */
export interface SleepConfig {
  /** How this project sleeps: destroy infra, run a command, or skip. */
  action: SleepAction;
  /** Shell command to run on sleep (when action = "command"). */
  command?: string;
  /** Shell command to run on wake (when action = "command"). */
  wake_command?: string;
  /** Optional timeout override for sleep/wake builds. */
  timeout?: number;
}

// --- Build / CodeBuild ---

export type BuildStatus =
  | "IN_PROGRESS"
  | "SUCCEEDED"
  | "FAILED"
  | "FAULT"
  | "STOPPED"
  | "TIMED_OUT";

/** Result of polling a CodeBuild build. */
export interface BuildPollResult {
  status: BuildStatus;
  exportedVars: ExportedVariable[];
}

export interface ExportedVariable {
  name: string;
  value: string;
}

/** Prepared build configuration (account, region, resolved inputs). */
export interface BuildConfig {
  accountId: string;
  region: string;
  codebuildProject: string;
  runner?: string;
  inputs: Record<string, string>;
}

// --- SSM State ---

/** Shape of the project blob stored in SSM at /propeller/<namespace>/<project>. */
export interface ProjectBlob {
  outputs: Record<string, string>;
  meta: ProjectMeta;
}

export interface ProjectMeta {
  propeller_version: string;
  deployed_at: string;
  build_id: string;
  git_sha: string;
}

// --- Execution Results ---

export type StepResultStatus = "succeeded" | "failed" | "skipped";

/** Result of executing a single project step. */
export interface StepResult {
  status: StepResultStatus;
  project: string;
  target?: string;
  account_id?: string;
  build_id?: string;
  error?: string;
  /** Duration in seconds (from build start to completion). */
  duration?: number;
}

/** Final pipeline execution result returned from the handler. */
export interface PipelineResult {
  status: "succeeded" | "failed";
  summary: {
    succeeded: number;
    failed: number;
    skipped: number;
  };
  results: StepResult[];
  /** Human-readable error description. */
  error?: string;
  /** Machine-readable error code for UI/automation consumption. */
  errorCode?: PipelineErrorCode;
  /** Non-fatal warnings (e.g. promotion failure, best-effort operations). */
  warnings?: string[];
}

/** Structured error codes for machine-readable failure classification. */
export type PipelineErrorCode =
  | "VALIDATION_ERROR"
  | "CONCURRENT_EXECUTION"
  | "SLEEPING_PIPELINE"
  | "STAGE_FAILED"
  | "APPROVAL_REJECTED"
  | "INTERNAL_ERROR";

// --- DAG ---

/** Dependency graph: project name → set of project names it depends on. */
export type DependencyGraph = Map<string, Set<string>>;

// --- Internal Context ---

/** Shared pipeline context threaded through all stages. */
export interface PipelineContext {
  bundleS3Uri: string;
  deployAction: DeployAction;
  namespace: string;
  propellerVersion: string;
  gitSha: string;
  consumerTags: Record<string, string>;
  executionId: string;
  supervised: boolean;
  /** Resolved sleep mode map: project name → mode string. */
  sleepModes: Record<string, string>;
}

// --- Services (dependency injection container) ---

/** Injectable service container passed to pipeline execution functions. */
export interface Services {
  ssm: import("@aws-sdk/client-ssm").SSMClient;
  sts: import("@aws-sdk/client-sts").STSClient;
}
