#!/usr/bin/env bash
set -euo pipefail
# Determine analysis type based on context
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

# Validate required vars
if [ -z "$PIPELINE_AGENT_URL" ] || [ -z "$PROCESSING_JWT" ] || \
   [ -z "$PROJECT_ID" ] || [ -z "$TARGET_BRANCH" ] || \
   [ -z "$COMMIT_HASH" ]; then
  usage
fi

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

#TODO: archive files for RAG indexing
# Create archive for RAG indexing
#ARCHIVE_FILE="$(mktemp --suffix=.tar.gz)"
#echo "Creating repository archive..."
#tar -czf "$ARCHIVE_FILE" \
#  --exclude='.git' \
#  --exclude='node_modules' \
#  --exclude='target' \
#  --exclude='build' \
#  --exclude='dist' \
#  --exclude='*.class' \
#  --exclude='*.jar' \
#  --exclude='*.war' \
#  .
#
#ARCHIVE_SIZE=$(stat -f%z "$ARCHIVE_FILE" 2>/dev/null || stat -c%s "$ARCHIVE_FILE")
#echo "Archive created: $(du -h "$ARCHIVE_FILE" | cut -f1)"

PAYLOAD_FILE="$(mktemp --suffix=.json)"

# Build JSON payload
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
    "${PIPELINE_AGENT_URL%/}/api/processing/webhook/pr" \
    | while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] && echo "EVENT: $line"
      done
else
  #TODO: archive for a RAG \
#  curl "${CURL_OPTS[@]}" \
#    -H "Authorization: Bearer ${PROCESSING_JWT}" \
#    -H 'Accept: application/x-ndjson' \
#    -F "request=@${PAYLOAD_FILE};type=application/json" \
#    -F "archive=@${ARCHIVE_FILE};type=application/gzip" \
#    "${PIPELINE_AGENT_URL%/}/api/processing/bitbucket/webhook/branch" \
#    | while IFS= read -r line || [ -n "$line" ]; do
#        [ -n "$line" ] && echo "EVENT: $line"
#      done
  curl "${CURL_OPTS[@]}" \
    -H "Authorization: Bearer ${PROCESSING_JWT}" \
    -H 'Accept: application/x-ndjson' \
    -F "request=@${PAYLOAD_FILE};type=application/json" \
    "${PIPELINE_AGENT_URL%/}/api/processing/webhook/branch" \
    | while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] && echo "EVENT: $line"
      done
fi

HTTP_EXIT=${PIPESTATUS[0]:-0}

# TODO: archive Cleanup
#rm -f "$PAYLOAD_FILE" "$ARCHIVE_FILE"

if [ $HTTP_EXIT -ne 0 ]; then
  echo "Analysis request failed with exit code $HTTP_EXIT"
  exit $HTTP_EXIT
fi

echo "Analysis request sent successfully."