# The container's entrypoint script (upload_repo.sh) will read environment variables (PIPELINE_AGENT_URL, PROCESSING_JWT, etc).
# It will create archive repo.tar.gz from the current working directory (the repo checkout) and POST it.

FROM atlassian/default-image:latest

USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl jq gzip tar ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# Copy the script
COPY analysis-executor.sh /usr/local/bin/analysis-executor.sh
RUN chmod +x /usr/local/bin/analysis-executor.sh

# Create a shorter alias
RUN ln -s /usr/local/bin/analysis-executor.sh /usr/local/bin/analysis-executor

ENTRYPOINT ["analysis-executor"]
