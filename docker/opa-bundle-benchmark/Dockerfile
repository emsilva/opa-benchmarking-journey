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

# Create directories for bundles and server config
RUN mkdir -p /app/bundles /app/config

# Build optimized OPA bundles (use only consolidated data to avoid merge conflicts)
RUN opa build -O 1 \
    -e rbac/allow \
    -e api/authz/allow \
    -e finance/risk/approve_loan \
    policies/ data/benchmark_data.json -o bundles/optimized-bundle.tar.gz

# Also build a non-optimized bundle for comparison
RUN opa build \
    policies/ data/benchmark_data.json -o bundles/standard-bundle.tar.gz

# Expose OPA server port
EXPOSE 8181

# Start script that launches OPA server with bundles
CMD ["./scripts/opa-bundle-benchmark.sh"]