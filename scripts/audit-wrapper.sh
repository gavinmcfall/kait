#!/usr/bin/env bash
# Audit wrapper for KAIT commands
# Logs all command executions to stdout in JSON format for Loki/Promtail
#
# Usage in hooks.yaml:
#   execute-command: /app/scripts/audit-wrapper.sh
#   pass-arguments-to-command:
#     - source: string
#       name: /scripts/my-handler.sh
#     - source: payload
#       name: alertname
#
# The first argument is the actual script to run, remaining args are passed through

set -euo pipefail

# Get the actual command and arguments
COMMAND="${1:-}"
shift || true

if [[ -z "$COMMAND" ]]; then
    echo '{"level":"error","msg":"No command specified","component":"audit"}' >&2
    exit 1
fi

# Generate unique request ID
REQUEST_ID=$(date +%s%N | sha256sum | head -c 8)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Capture stdin if present
STDIN_DATA=""
if [[ ! -t 0 ]]; then
    STDIN_DATA=$(cat)
fi

# Log start
jq -nc \
    --arg id "$REQUEST_ID" \
    --arg ts "$TIMESTAMP" \
    --arg cmd "$COMMAND" \
    --argjson args "$(printf '%s\n' "$@" | jq -R . | jq -s .)" \
    --arg stdin "$STDIN_DATA" \
    '{
        level: "info",
        component: "audit",
        event: "start",
        request_id: $id,
        timestamp: $ts,
        command: $cmd,
        arguments: $args,
        stdin: (if $stdin == "" then null else ($stdin | fromjson? // $stdin) end)
    }'

# Execute the command
START_TIME=$(date +%s%N)
set +e
if [[ -n "$STDIN_DATA" ]]; then
    OUTPUT=$(echo "$STDIN_DATA" | "$COMMAND" "$@" 2>&1)
else
    OUTPUT=$("$COMMAND" "$@" 2>&1)
fi
EXIT_CODE=$?
set -e
END_TIME=$(date +%s%N)
DURATION_MS=$(( (END_TIME - START_TIME) / 1000000 ))

# Log completion
TIMESTAMP_END=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LEVEL="info"
[[ $EXIT_CODE -ne 0 ]] && LEVEL="error"

jq -nc \
    --arg level "$LEVEL" \
    --arg id "$REQUEST_ID" \
    --arg ts "$TIMESTAMP_END" \
    --argjson exit "$EXIT_CODE" \
    --argjson duration "$DURATION_MS" \
    --arg output "$OUTPUT" \
    '{
        level: $level,
        component: "audit",
        event: "complete",
        request_id: $id,
        timestamp: $ts,
        exit_code: $exit,
        duration_ms: $duration,
        output: $output
    }'

# Output the result (webhook captures this for response)
echo "$OUTPUT" >&2
exit $EXIT_CODE
