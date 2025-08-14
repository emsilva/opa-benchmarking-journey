FROM alpine:3.19

# Install curl, bash, bc, jq, and apache bench
RUN apk add --no-cache curl bash bc jq apache2-utils

# Download and install OPA
RUN curl -L -o /usr/local/bin/opa https://openpolicyagent.org/downloads/latest/opa_linux_amd64_static && \
    chmod +x /usr/local/bin/opa

# Create working directory
WORKDIR /app

# Copy policies and data
COPY policies/ ./policies/
COPY data/ ./data/
COPY scripts/ ./scripts/

# Make scripts executable
RUN chmod +x scripts/*.sh

# Expose OPA server port
EXPOSE 8181

# Start script that runs concurrent benchmarks
CMD ["./scripts/opa-concurrent-benchmark.sh"]