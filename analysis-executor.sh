#!/usr/bin/env bash
set -euo pipefail

# analysis-executor.sh (auto-binding version)
#
# Automatically maps Bitbucket variables to required inputs if CodeCrow-specific ones are not provided.

# Prefer CodeCrow variables; fallback to Bitbucket native env vars
PIPELINE_AGENT_URL="${CODECROW_BASE_URL:-${PIPELINE_AGENT_URL:-}}"
PROCESSING_JWT="${CODECROW_PROJECT_TOKEN:-${PROCESSING_JWT:-}}"
PROJECT_ID="${CODECROW_PROJECT_ID:-${PROJECT_ID:-}}"
PULL_REQUEST_ID="${BITBUCKET_PR_ID:-${PULL_REQUEST_ID:-}}"
TARGET_BRANCH="${BITBUCKET_PR_DESTINATION_BRANCH:-${TARGET_BRANCH:-}}"
SOURCE_BRANCH="${BITBUCKET_BRANCH:-${SOURCE_BRANCH:-}}"
COMMIT_HASH="${BITBUCKET_COMMIT:-${COMMIT_HASH:-}}"
TIMEOUT="${TIMEOUT:-0}"

usage() {
  cat <<EOF
Missing required environment variables.
Required (one of the following for each):
  PIPELINE_AGENT_URL or CODECROW_BASE_URL
  PROCESSING_JWT or CODECROW_PROJECT_TOKEN
  PROJECT_ID or CODECROW_PROJECT_ID
  PULL_REQUEST_ID or BITBUCKET_PR_ID
  TARGET_BRANCH or BITBUCKET_PR_DESTINATION_BRANCH
  SOURCE_BRANCH or BITBUCKET_BRANCH
  COMMIT_HASH or BITBUCKET_COMMIT
EOF
  exit 1
}

# Validate required vars exist after auto-binding
if [ -z "$PIPELINE_AGENT_URL" ] || [ -z "$PROCESSING_JWT" ] || \
   [ -z "$PROJECT_ID" ] || [ -z "$PULL_REQUEST_ID" ] || \
   [ -z "$TARGET_BRANCH" ] || [ -z "$SOURCE_BRANCH" ] || \
   [ -z "$COMMIT_HASH" ]; then
  usage
fi

WORKDIR=${WORKDIR:-/workspace}
cd "$WORKDIR"

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

CURL_OPTS=(--silent --no-buffer --show-error --fail)
if [ "${TIMEOUT}" -ne 0 ]; then
  CURL_OPTS+=(--max-time "${TIMEOUT}")
fi

curl "${CURL_OPTS[@]}" \
  -H "Authorization: Bearer ${PROCESSING_JWT}" \
  -H 'Accept: application/x-ndjson' \
  -H 'Content-Type: application/json' \
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
