# Profile-Guided Optimization Benchmark
# Uses WASM-enabled OPA build for better profiling capabilities
FROM golang:1.23-bullseye AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y git make bash build-essential && rm -rf /var/lib/apt/lists/*

# Build OPA with WASM support for better profiling
WORKDIR /build
RUN git clone --depth 1 --branch v1.7.1 https://github.com/open-policy-agent/opa.git
WORKDIR /build/opa

# Build with WASM support enabled - CGO is required for wasmtime and better profiling
ENV CGO_ENABLED=1
ENV GOOS=linux
ENV GOARCH=amd64
RUN make build WASM_ENABLED=1

FROM debian:bullseye-slim

# Install runtime dependencies including profiling tools
RUN apt-get update && apt-get install -y curl bash bc jq file graphviz && rm -rf /var/lib/apt/lists/*

# Copy WASM-enabled OPA binary from builder (has better profiling support)
COPY --from=builder /build/opa/opa_linux_amd64 /usr/local/bin/opa
RUN chmod +x /usr/local/bin/opa

# Create working directory
WORKDIR /app

# Copy both original and optimized policies
COPY policies/ ./policies/
COPY policies-optimized/ ./policies-optimized/
COPY data/ ./data/
COPY scripts/ ./scripts/

# Make scripts executable
RUN chmod +x scripts/*.sh

# Create directories for results and profiling
RUN mkdir -p /app/results /app/profiles /app/analysis

# Test OPA version and WASM support
RUN /usr/local/bin/opa version

# Expose OPA server port and profiling port
EXPOSE 8181 8282

# Start script that runs optimization benchmarks
CMD ["./scripts/opa-optimization-benchmark.sh"]