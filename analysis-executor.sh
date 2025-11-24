#!/usr/bin/env bash
set -euo pipefail
# Determine analysis type based on context
# If PULL_REQUEST_ID is set, it's a PR review; otherwise it's a branch analysis
COMMIT_HASH="${BITBUCKET_COMMIT:-${COMMIT_HASH:-}}"
TIMEOUT="${TIMEOUT:-0}"
PIPELINE_AGENT_URL="${CODECROW_BASE_URL:-${PIPELINE_AGENT_URL:-}}"
PROCESSING_JWT="${CODECROW_PROJECT_TOKEN:-${PROCESSING_JWT:-}}"
PROJECT_ID="${CODECROW_PROJECT_ID:-${PROJECT_ID:-}}"
PULL_REQUEST_ID="${BITBUCKET_PR_ID:-${PULL_REQUEST_ID:-}}"

if [ -n "$PULL_REQUEST_ID" ]; then
  ANALYSIS_TYPE="${ANALYSIS_TYPE:-PR_REVIEW}"
  TARGET_BRANCH="${BITBUCKET_PR_DESTINATION_BRANCH:-${TARGET_BRANCH:-}}"
  SOURCE_BRANCH="${BITBUCKET_BRANCH:-${SOURCE_BRANCH:-}}"
else
  ANALYSIS_TYPE="${ANALYSIS_TYPE:-BRANCH_ANALYSIS}"
  TARGET_BRANCH="${BITBUCKET_BRANCH:-${SOURCE_BRANCH:-}}"
fi

usage_pr() {
  cat <<EOF
Missing required environment variables.
Required (one of the following for each):
  SOURCE_BRANCH
  PULL_REQUEST_ID or BITBUCKET_PR_ID (required for PR_REVIEW)
EOF
  exit 1
}

usage() {
  cat <<EOF
Missing required environment variables.
Required (one of the following for each):
  PIPELINE_AGENT_URL or CODECROW_BASE_URL
  PROCESSING_JWT or CODECROW_PROJECT_TOKEN
  PROJECT_ID or CODECROW_PROJECT_ID
  TARGET_BRANCH or BITBUCKET_PR_DESTINATION_BRANCH
  COMMIT_HASH or BITBUCKET_COMMIT

Optional:
  ANALYSIS_TYPE (defaults to PR_REVIEW for PRs, BRANCH_ANALYSIS for branches)
  TIMEOUT (defaults to 0, meaning no timeout)
EOF
  exit 1
}

# Validate required vars exist after auto-binding
# Note: PULL_REQUEST_ID is only required for PR_REVIEW
if [ -z "$PIPELINE_AGENT_URL" ] || [ -z "$PROCESSING_JWT" ] || \
   [ -z "$PROJECT_ID" ] || [ -z "$TARGET_BRANCH" ] || \
   [ -z "$COMMIT_HASH" ]; then
  usage
fi

# For PR_REVIEW, PULL_REQUEST_ID is required
if [ "$ANALYSIS_TYPE" = "PR_REVIEW" ] && [ -z "$PULL_REQUEST_ID" ]; then
  echo "Error: PULL_REQUEST_ID is required for PR_REVIEW analysis type"
  usage_pr
fi

if [ "$ANALYSIS_TYPE" = "PR_REVIEW" ] && [ -z "$SOURCE_BRANCH" ]; then
  echo "Error: SOURCE_BRANCH is required for PR_REVIEW analysis type"
  usage_pr
fi

WORKDIR=${WORKDIR:-/workspace}
cd "$WORKDIR"

PAYLOAD_FILE="$(mktemp --suffix=.json)"

# Build JSON payload - handle optional PULL_REQUEST_ID
if [ -n "$PULL_REQUEST_ID" ]; then
  cat > "$PAYLOAD_FILE" <<JSON
{
  "projectId": ${PROJECT_ID},
  "pullRequestId": ${PULL_REQUEST_ID},
  "targetBranchName": "${TARGET_BRANCH}",
  "sourceBranchName": "${SOURCE_BRANCH}",
  "commitHash": "${COMMIT_HASH}",
  "analysisType": "${ANALYSIS_TYPE}"
}
JSON
else
  cat > "$PAYLOAD_FILE" <<JSON
{
  "projectId": ${PROJECT_ID},
  "targetBranchName": "${TARGET_BRANCH}",
  "commitHash": "${COMMIT_HASH}",
  "analysisType": "${ANALYSIS_TYPE}"
}
JSON
fi

echo "Sending ${ANALYSIS_TYPE} request..."

CURL_OPTS=(--silent --no-buffer --show-error --fail)
if [ "${TIMEOUT}" -ne 0 ]; then
  CURL_OPTS+=(--max-time "${TIMEOUT}")
fi

if [ -n "$PULL_REQUEST_ID" ]; then
  curl "${CURL_OPTS[@]}" \
    -H "Authorization: Bearer ${PROCESSING_JWT}" \
    -H 'Accept: application/x-ndjson' \
    -H 'Content-Type: application/json' \
    --data-binary @"${PAYLOAD_FILE}" \
    "${PIPELINE_AGENT_URL%/}/api/processing/bitbucket/webhook/pr" \
    | while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] && echo "EVENT: $line"
      done
else
  curl "${CURL_OPTS[@]}" \
    -H "Authorization: Bearer ${PROCESSING_JWT}" \
    -H 'Accept: application/x-ndjson' \
    -H 'Content-Type: application/json' \
    --data-binary @"${PAYLOAD_FILE}" \
    "${PIPELINE_AGENT_URL%/}/api/processing/bitbucket/webhook/branch" \
    | while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] && echo "EVENT: $line"
      done
fi



HTTP_EXIT=${PIPESTATUS[0]:-0}

if [ $HTTP_EXIT -ne 0 ]; then
  echo "Analysis request failed with exit code $HTTP_EXIT"
  exit $HTTP_EXIT
fi

echo "Analysis request sent successfully."