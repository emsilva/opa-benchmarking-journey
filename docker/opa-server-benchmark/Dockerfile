FROM alpine:3.19

# Install curl and basic tools
RUN apk add --no-cache curl bash bc jq

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

# Create OPA server configuration directory
RUN mkdir -p /app/config

# Copy OPA server configuration
COPY docker/opa-server-benchmark/config/ ./config/

# Expose OPA server port
EXPOSE 8181

# Start script that launches OPA server and runs benchmarks
CMD ["./scripts/opa-server-benchmark.sh"]