#!/usr/bin/env bash
set -euo pipefail

# analysis-executor.sh
#
# Entrypoint for the bitbucket-pipeline-uploader image.
# - Creates a repo archive from current working directory (/workspace is the repo checkout)
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
#   ARCHIVE_NAME         default: repo.tar.gz
#   TIMEOUT              curl timeout seconds (default 0 = no timeout)
#
# Notes:
# - The script prints NDJSON lines from the pipeline-agent / streams events as they arrive.
# - The pipeline job will fail if the HTTP request returns a non-success status.
# - Use -N with curl to disable buffering when inspecting output locally; the script uses curl --no-buffer.

PIPELINE_AGENT_URL="${CODECROW_BASE_URL:-}"
PROCESSING_JWT="${CODECROW_PROJECT_TOKEN:-}"
PROJECT_ID="${CODECROW_PROJECT_ID:-}"
PULL_REQUEST_ID="${PULL_REQUEST_ID:-}"
TARGET_BRANCH="${TARGET_BRANCH:-}"
SOURCE_BRANCH="${SOURCE_BRANCH:-}"
COMMIT_HASH="${COMMIT_HASH:-}"
ARCHIVE_NAME="${ARCHIVE_NAME:-repo.tar.gz}"
TIMEOUT="${TIMEOUT:-0}"

usage() {
  cat <<EOF
Usage: set environment variables and run this script
Required:
  PIPELINE_AGENT_URL PROCESSING_JWT PROJECT_ID PULL_REQUEST_ID TARGET_BRANCH SOURCE_BRANCH COMMIT_HASH
Optional:
  ARCHIVE_NAME (default: repo.tar.gz) TIMEOUT (curl timeout seconds, 0 = none)
EOF
  exit 1
}

if [ -z "$PIPELINE_AGENT_URL" ] || [ -z "$PROCESSING_JWT" ] || [ -z "$PROJECT_ID" ] || [ -z "$PULL_REQUEST_ID" ] || [ -z "$TARGET_BRANCH" ] || [ -z "$SOURCE_BRANCH" ] || [ -z "$COMMIT_HASH" ]; then
  echo "Missing required environment variables."
  usage
fi

# Ensure we are in the checked-out repo. Default working dir is /workspace (as set in Dockerfile).
WORKDIR=${WORKDIR:-/workspace}
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

# Create archive (tar.gz) of repository root. Exclude pipeline-specific directories if needed.
ARCHIVE_PATH="$(mktemp --suffix=.tar.gz)"
echo "Creating archive $ARCHIVE_PATH from $WORKDIR ..."
tar --exclude='.git' --exclude='node_modules' -czf - . | pv > "$ARCHIVE_PATH"

# Build curl command
CURL_OPTS=(--no-buffer --show-error --fail)
if [ "${TIMEOUT}" -ne 0 ]; then
  CURL_OPTS+=(--max-time "${TIMEOUT}")
fi

AUTH_HEADER="Authorization: Bearer ${PROCESSING_JWT}"

echo "Uploading archive to ${PIPELINE_AGENT_URL}/api/processing/bitbucket/webhook-multipart"
echo "Payload: $(cat "$PAYLOAD_FILE")"
echo "Archive: $ARCHIVE_PATH"

# POST multipart and stream NDJSON as it arrives
curl "${CURL_OPTS[@]}" -H "$AUTH_HEADER" \
  -F "payload=@${PAYLOAD_FILE};type=application/json" \
  -F "file=@${ARCHIVE_PATH};type=application/gzip" \
  "${PIPELINE_AGENT_URL%/}/api/processing/bitbucket/webhook-multipart" \
  | while IFS= read -r line || [ -n "$line" ]; do
      if [ -n "$line" ]; then
        echo "EVENT: $line"
      fi
    done

HTTP_EXIT=${PIPESTATUS[0]:-0}

# Cleanup
rm -f "$PAYLOAD_FILE" "$ARCHIVE_PATH"

if [ $HTTP_EXIT -ne 0 ]; then
  echo "Upload failed with exit code $HTTP_EXIT"
  exit $HTTP_EXIT
fi

echo "Upload completed successfully."
