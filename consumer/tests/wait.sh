#!/usr/bin/env bash
# Tests `just wait` exit codes against a stubbed aws CLI.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/repo/dist/p"
cp "$ROOT/consumer/justfile" "$TMP/repo/justfile"
echo -n "p__apply__sha__ts" > "$TMP/repo/dist/p/execution-name"
echo "v0.0.0" > "$TMP/repo/.propeller-version"

# Stub: first get-durable-execution call reports RUNNING, the rest return $FINAL.
cat > "$TMP/bin/aws" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *list-durable-executions-by-function*) echo "arn:listed" ;;
  *get-durable-execution*--no-include-execution-data*)
    n=$(cat "$STUB_DIR/calls" 2>/dev/null || echo 0); echo $((n + 1)) > "$STUB_DIR/calls"
    if [[ $n -eq 0 ]]; then echo RUNNING; else jq -r .Status <<<"$FINAL"; fi ;;
  *get-durable-execution*) echo "$FINAL" ;;
esac
EOF
chmod +x "$TMP/bin/aws"

fail=0
run() { # name expected-exit expected-output arn final
  rm -f "$TMP/calls"
  echo -n "$4" > "$TMP/repo/dist/p/execution-arn"
  set +e
  out=$(cd "$TMP/repo" && PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" FINAL="$5" \
    PROPELLER_WAIT_INTERVAL=0 PROPELLER_LAMBDA_ARN=arn:fn just wait p 2>&1)
  got=$?
  set -e
  if [[ $got -eq $2 && "$out" == *"$3"* ]]; then
    echo "ok   $1"
  else
    echo "FAIL $1: expected exit $2 with '$3', got $got:"; echo "$out"; fail=1
  fi
}

ok_result='{"status":"succeeded","summary":{"succeeded":1,"failed":0,"skipped":0},"results":[]}'
bad_result='{"status":"failed","error":"boom","summary":{"succeeded":0,"failed":1,"skipped":0},"results":[{"project":"x","status":"failed","error":"e"}]}'
exec_resp() { jq -nc --arg s "$1" --arg r "$2" '{Status: $s, Result: $r, Error: {ErrorMessage: "lambda died"}}'; }

run "succeeded"                  0 "Pipeline succeeded" "arn:x" "$(exec_resp SUCCEEDED "$ok_result")"
run "succeeded, pipeline failed" 1 "x: e"               "arn:x" "$(exec_resp SUCCEEDED "$bad_result")"
run "execution failed"           1 "Execution FAILED"   "arn:x" "$(exec_resp FAILED "")"
run "execution timed out"        1 "Execution TIMED_OUT" "arn:x" "$(exec_resp TIMED_OUT "")"
run "execution stopped"          1 "Execution STOPPED"  "arn:x" "$(exec_resp STOPPED "")"
run "arn resolved by name"       0 "Pipeline succeeded" ""      "$(exec_resp SUCCEEDED "$ok_result")"

exit $fail
