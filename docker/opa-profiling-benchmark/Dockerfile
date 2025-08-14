# OPA Profiling Benchmark
# Profile-guided optimization analysis using Go pprof
FROM alpine:3.19

# Install dependencies for profiling
RUN apk add --no-cache curl bash bc jq file graphviz go

# Download OPA binary
RUN curl -L -o /usr/local/bin/opa https://github.com/open-policy-agent/opa/releases/download/v1.7.1/opa_linux_amd64_static
RUN chmod +x /usr/local/bin/opa

# Create working directory
WORKDIR /app

# Copy policies and data
COPY policies/ ./policies/
COPY data/ ./data/
COPY scripts/ ./scripts/

# Make scripts executable
RUN chmod +x scripts/*.sh

# Create directories for profiling output
RUN mkdir -p /app/profiles /app/analysis

# Test OPA version
RUN /usr/local/bin/opa version

# Expose OPA server port
EXPOSE 8181

# Start script that runs profiling benchmarks
CMD ["./scripts/opa-profiling-benchmark.sh"]