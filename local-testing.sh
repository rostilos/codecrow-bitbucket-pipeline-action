#!/usr/bin/env bash
set -euo pipefail

# analysis-executor.sh
#
# Entrypoint for the bitbucket-pipeline-uploader image.
# - Builds a small payload JSON using environment variables
# - Posts multipart/form-data to pipeline-agent's webhook-multipart endpoint and streams NDJSON output
#
# Required environment variables:
#   PIPELINE_AGENT_URL   e.g. http://pipeline-agent-host:8082
#   PROCESSING_JWT       Bearer token used by the pipeline-agent for authentication
#   PROJECT_ID           numeric project id
#   PULL_REQUEST_ID      numeric pull request id
#   TARGET_BRANCH        target branch name
#   SOURCE_BRANCH        source branch name
#   COMMIT_HASH          commit hash
#
# Optional:
#   TIMEOUT              curl timeout seconds (default 0 = no timeout)
#
# Notes:
# - The script prints NDJSON lines from the pipeline-agent / streams events as they arrive.
# - The pipeline job will fail if the HTTP request returns a non-success status.
# - Use -N with curl to disable buffering when inspecting output locally; the script uses curl --no-buffer.

PIPELINE_AGENT_URL="http://localhost:8082"
PROCESSING_JWT="eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIiwidXNlcklkIjoiMSIsImlhdCI6MTc2MjI2Nzc1MiwiZXhwIjoxNzY0ODU5NzUyfQ.DFcz0OGiIrePw8VcUnk-eHnLTrOPmIOcmx8-LJmxerU"
PROJECT_ID="1"
PULL_REQUEST_ID="128"
TARGET_BRANCH="develop"
SOURCE_BRANCH="master"
COMMIT_HASH="39b506fa94f1"
TIMEOUT="${TIMEOUT:-0}"

usage() {
  cat <<EOF
Usage: set environment variables and run this script
Required:
  PIPELINE_AGENT_URL PROCESSING_JWT PROJECT_ID PULL_REQUEST_ID TARGET_BRANCH SOURCE_BRANCH COMMIT_HASH
EOF
  exit 1
}

if [ -z "$PIPELINE_AGENT_URL" ] || [ -z "$PROCESSING_JWT" ] || [ -z "$PROJECT_ID" ] || [ -z "$PULL_REQUEST_ID" ] || [ -z "$TARGET_BRANCH" ] || [ -z "$SOURCE_BRANCH" ] || [ -z "$COMMIT_HASH" ]; then
  echo "Missing required environment variables."
  usage
fi

# Ensure we are in the checked-out repo. Default working dir is /workspace (as set in Dockerfile).
WORKDIR=${WORKDIR:-./workspace}
cd "$WORKDIR"

# Create payload.json in a temp file
PAYLOAD_FILE="$(mktemp --suffix=.json)"
cat > "$PAYLOAD_FILE" <<JSON
{
  "projectId": ${PROJECT_ID},
  "pullRequestId": ${PULL_REQUEST_ID},
  "targetBranchName": "${TARGET_BRANCH}",
  "sourceBranchName": "${SOURCE_BRANCH}",
  "commitHash": "${COMMIT_HASH}"
}
JSON

# Build curl command
CURL_OPTS=(--silent --no-buffer --show-error --fail)
if [ "${TIMEOUT}" -ne 0 ]; then
  CURL_OPTS+=(--max-time "${TIMEOUT}")
fi

AUTH_HEADER="Authorization: Bearer ${PROCESSING_JWT}"

# POST multipart and stream NDJSON as it arrives
curl "${CURL_OPTS[@]}" -H "$AUTH_HEADER" \
  --header 'Accept: application/x-ndjson' \
  --header 'Content-Type: application/json' \
  --data-binary @"${PAYLOAD_FILE}" \
  "${PIPELINE_AGENT_URL%/}/api/processing/bitbucket/webhook" \
  | while IFS= read -r line || [ -n "$line" ]; do
      [ -n "$line" ] && echo "EVENT: $line"
    done

HTTP_EXIT=${PIPESTATUS[0]:-0}

if [ $HTTP_EXIT -ne 0 ]; then
  echo "Analysis request failed with exit code $HTTP_EXIT"
  exit $HTTP_EXIT
fi

echo "Analysis request sent successfully."
