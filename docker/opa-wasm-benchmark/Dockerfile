# Build OPA with WASM support from source
FROM golang:1.23-bullseye AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y git make bash build-essential && rm -rf /var/lib/apt/lists/*

# Build OPA with WASM support
WORKDIR /build
RUN git clone --depth 1 --branch v1.7.1 https://github.com/open-policy-agent/opa.git
WORKDIR /build/opa

# Build with WASM support enabled - CGO is required for wasmtime
ENV CGO_ENABLED=1
ENV GOOS=linux
ENV GOARCH=amd64
RUN make build WASM_ENABLED=1

FROM debian:bullseye-slim

# Install runtime dependencies  
RUN apt-get update && apt-get install -y curl bash bc jq file && rm -rf /var/lib/apt/lists/*

# Copy WASM-enabled OPA binary from builder
COPY --from=builder /build/opa/opa_linux_amd64 /usr/local/bin/opa
RUN chmod +x /usr/local/bin/opa

# Create working directory
WORKDIR /app

# Copy policies and data
COPY policies/ ./policies/
COPY data/ ./data/
COPY scripts/ ./scripts/

# Make scripts executable
RUN chmod +x scripts/*.sh

# Create directories for WASM modules
RUN mkdir -p /app/wasm

# Test OPA version and WASM support
RUN /usr/local/bin/opa version

# Compile policies to WASM bundles
# Keep as bundles since OPA server needs the complete bundle structure
RUN /usr/local/bin/opa build -t wasm -e rbac/allow policies/simple_rbac.rego -o wasm/rbac-bundle.tar.gz
RUN /usr/local/bin/opa build -t wasm -e api/authz/allow policies/api_authorization.rego data/benchmark_data.json -o wasm/api-bundle.tar.gz  
RUN /usr/local/bin/opa build -t wasm -e finance/risk/approve_loan policies/financial_risk_assessment.rego data/benchmark_data.json -o wasm/financial-bundle.tar.gz

# Verify WASM bundles were created
RUN ls -la wasm/ && echo "Bundle contents:" && tar -tzf wasm/rbac-bundle.tar.gz | head -10

# Expose OPA server port
EXPOSE 8181

# Start script that runs WASM benchmarks
CMD ["./scripts/opa-wasm-benchmark.sh"]