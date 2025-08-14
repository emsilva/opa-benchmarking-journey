# Cloud-Optimized OPA Benchmark Container
# Combines all proven optimizations:
# - WASM-enabled OPA build
# - Profile-guided optimized policies
# - WASM compilation for compute-intensive policies
# - Multi-node distributed benchmarking capabilities

FROM golang:1.23-bullseye AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y git make bash build-essential && rm -rf /var/lib/apt/lists/*

# Build OPA with WASM support for maximum performance on complex policies
WORKDIR /build
RUN git clone --depth 1 --branch v0.68.0 https://github.com/open-policy-agent/opa.git
WORKDIR /build/opa

# Build with WASM support enabled - CGO required for optimal performance
ENV CGO_ENABLED=1
ENV GOOS=linux
ENV GOARCH=amd64
RUN make build WASM_ENABLED=1

# Production runtime container
FROM debian:bullseye-slim

# Install runtime dependencies including network tools for cloud benchmarking
RUN apt-get update && apt-get install -y \
    curl \
    bash \
    bc \
    jq \
    file \
    dnsutils \
    netcat \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Copy WASM-enabled OPA binary from builder
COPY --from=builder /build/opa/opa_linux_amd64 /usr/local/bin/opa
RUN chmod +x /usr/local/bin/opa

# Create working directory
WORKDIR /app

# Copy optimized policies (profile-guided optimizations applied)
COPY policies-optimized/ ./policies-optimized/

# Copy original policies for comparison testing
COPY policies/ ./policies/

# Copy benchmark data
COPY data/ ./data/

# Copy benchmark scripts
COPY scripts/ ./scripts/
RUN chmod +x scripts/*.sh

# Create directories for WASM modules and results
RUN mkdir -p /app/wasm /app/results /app/k8s-results

# Verify OPA build supports WASM
RUN /usr/local/bin/opa version

# Compile policies to WASM bundles
# Based on our benchmarks:
# - Simple RBAC: Keep as Rego (WASM adds 3.9% overhead)
# - API Authorization: Keep as Rego (WASM equivalent performance)  
# - Financial Risk: Compile to WASM (23% performance boost)

# Compile optimized policies
RUN /usr/local/bin/opa build -t wasm -e rbac/allow \
    policies-optimized/simple_rbac_optimized.rego \
    -o wasm/rbac-optimized-bundle.tar.gz

RUN /usr/local/bin/opa build -t wasm -e api/authz/allow \
    policies-optimized/api_authorization_optimized.rego \
    data/benchmark_data.json \
    -o wasm/api-optimized-bundle.tar.gz

# Financial Risk gets WASM compilation for maximum performance (23% boost)
RUN /usr/local/bin/opa build -t wasm -e finance/risk/approve_loan \
    policies-optimized/financial_risk_assessment_optimized.rego \
    data/benchmark_data.json \
    -o wasm/financial-optimized-bundle.tar.gz

# Verify WASM bundles created successfully
RUN ls -la wasm/ && echo "=== WASM Bundle Contents ===" && \
    tar -tzf wasm/financial-optimized-bundle.tar.gz | head -10

# Expose OPA server port
EXPOSE 8181

# Default to cloud benchmark script (can be overridden in K8s deployment)
CMD ["./scripts/opa-cloud-benchmark.sh"]