# OPA Benchmarking Journey Makefile

.PHONY: help build build-cli build-server build-bundle build-concurrent build-wasm build-profiling build-optimization opa-cli-benchmark opa-server-benchmark opa-bundle-benchmark opa-concurrent-benchmark opa-wasm-benchmark opa-profiling-benchmark opa-optimization-benchmark baseline clean validate shell-cli shell-server shell-bundle shell-concurrent shell-wasm shell-profiling shell-optimization

# Default target
help:
	@echo "OPA Benchmarking Journey"
	@echo ""
	@echo "Available targets:"
	@echo "  build               - Build all benchmark containers"
	@echo "  build-cli           - Build OPA CLI benchmark container"
	@echo "  build-server        - Build OPA Server benchmark container"
	@echo "  build-bundle        - Build OPA Bundle API benchmark container"
	@echo "  build-concurrent    - Build OPA Concurrent benchmark container"
	@echo "  build-wasm          - Build OPA WebAssembly benchmark container"
	@echo "  build-profiling     - Build OPA Profiling benchmark container"
	@echo "  build-optimization  - Build OPA Profile-Guided Optimization benchmark container"
	@echo "  opa-cli-benchmark   - Run OPA CLI benchmark with custom iterations (default: 100)"
	@echo "                        Usage: make opa-cli-benchmark [ITERATIONS=number]"
	@echo "                        Example: make opa-cli-benchmark ITERATIONS=1000"
	@echo "  opa-server-benchmark - Run OPA Server benchmark with custom iterations (default: 100)"
	@echo "                         Usage: make opa-server-benchmark [ITERATIONS=number]"
	@echo "                         Example: make opa-server-benchmark ITERATIONS=1000"
	@echo "  opa-bundle-benchmark - Run OPA Bundle API benchmark with optimization"
	@echo "                         Usage: make opa-bundle-benchmark [ITERATIONS=number]"
	@echo "                         Example: make opa-bundle-benchmark ITERATIONS=1000"
	@echo "  opa-concurrent-benchmark - Run OPA Concurrent benchmark with multiple workers"
	@echo "                           Usage: make opa-concurrent-benchmark [ITERATIONS=number]"
	@echo "                           Example: make opa-concurrent-benchmark ITERATIONS=1000"
	@echo "  opa-wasm-benchmark     - Run OPA WebAssembly vs Rego performance comparison"
	@echo "                         Usage: make opa-wasm-benchmark [ITERATIONS=number]"
	@echo "                         Example: make opa-wasm-benchmark ITERATIONS=1000"
	@echo "  opa-profiling-benchmark - Run OPA profiling analysis with CPU and memory profiling"
	@echo "                          Usage: make opa-profiling-benchmark [ITERATIONS=number]"
	@echo "                          Example: make opa-profiling-benchmark ITERATIONS=1000"
	@echo "  opa-optimization-benchmark - Compare original vs profile-guided optimized policies"
	@echo "                             Usage: make opa-optimization-benchmark [ITERATIONS=number]"
	@echo "                             Example: make opa-optimization-benchmark ITERATIONS=1000"
	@echo "  baseline            - Run both CLI and Server benchmarks with 1000 iterations"
	@echo "  clean               - Remove Docker images and containers"
	@echo "  validate            - Validate OPA policies"
	@echo "  shell-cli           - Start interactive shell in CLI benchmark container"
	@echo "  shell-server        - Start interactive shell in Server benchmark container"
	@echo "  shell-bundle        - Start interactive shell in Bundle benchmark container"
	@echo "  shell-concurrent    - Start interactive shell in Concurrent benchmark container"
	@echo "  shell-wasm          - Start interactive shell in WebAssembly benchmark container"
	@echo "  shell-profiling     - Start interactive shell in Profiling benchmark container"
	@echo "  shell-optimization  - Start interactive shell in Optimization benchmark container"
	@echo ""

# Build all containers
build: build-cli build-server build-bundle build-concurrent build-wasm build-profiling build-optimization

# Build CLI benchmark container
build-cli:
	@echo "Building OPA CLI benchmark container..."
	docker build -f docker/opa-cli-benchmark/Dockerfile -t opa-cli-benchmark .
	@echo "OPA CLI benchmark container built successfully!"

# Build Server benchmark container
build-server:
	@echo "Building OPA Server benchmark container..."
	docker build -f docker/opa-server-benchmark/Dockerfile -t opa-server-benchmark .
	@echo "OPA Server benchmark container built successfully!"

# Build Bundle benchmark container
build-bundle:
	@echo "Building OPA Bundle API benchmark container..."
	docker build -f docker/opa-bundle-benchmark/Dockerfile -t opa-bundle-benchmark .
	@echo "OPA Bundle API benchmark container built successfully!"

# Build Concurrent benchmark container
build-concurrent:
	@echo "Building OPA Concurrent benchmark container..."
	docker build -f docker/opa-concurrent-benchmark/Dockerfile -t opa-concurrent-benchmark .
	@echo "OPA Concurrent benchmark container built successfully!"

# Build WebAssembly benchmark container
build-wasm:
	@echo "Building OPA WebAssembly benchmark container..."
	docker build -f docker/opa-wasm-benchmark/Dockerfile -t opa-wasm-benchmark .
	@echo "OPA WebAssembly benchmark container built successfully!"

# Build Profiling benchmark container
build-profiling:
	@echo "Building OPA Profiling benchmark container..."
	docker build -f docker/opa-profiling-benchmark/Dockerfile -t opa-profiling-benchmark .
	@echo "OPA Profiling benchmark container built successfully!"

# Build Optimization benchmark container
build-optimization:
	@echo "Building OPA Profile-Guided Optimization benchmark container..."
	docker build -f docker/opa-optimization-benchmark/Dockerfile -t opa-optimization-benchmark .
	@echo "OPA Optimization benchmark container built successfully!"

# Run CLI benchmark with custom iterations (default: 100)
# Usage: make opa-cli-benchmark [ITERATIONS=number]
opa-cli-benchmark: build-cli
	$(eval ITERATIONS ?= 100)
	@echo "Running OPA CLI Benchmark - $(ITERATIONS) evaluations per policy"
	@echo "================================================================="
	docker run --rm opa-cli-benchmark ./scripts/opa-cli-benchmark.sh $(ITERATIONS)

# Run Server benchmark with custom iterations (default: 100)
# Usage: make opa-server-benchmark [ITERATIONS=number]
opa-server-benchmark: build-server
	$(eval ITERATIONS ?= 100)
	@echo "Running OPA Server Benchmark - $(ITERATIONS) evaluations per policy"
	@echo "===================================================================="
	docker run --rm opa-server-benchmark ./scripts/opa-server-benchmark.sh $(ITERATIONS)

# Run Bundle API benchmark with optimization (default: 100)
# Usage: make opa-bundle-benchmark [ITERATIONS=number]
opa-bundle-benchmark: build-bundle
	$(eval ITERATIONS ?= 100)
	@echo "Running OPA Bundle API Benchmark - $(ITERATIONS) evaluations per policy"
	@echo "======================================================================="
	docker run --rm opa-bundle-benchmark ./scripts/opa-bundle-benchmark.sh $(ITERATIONS)

# Run Concurrent benchmark with multiple workers (default: 100)
# Usage: make opa-concurrent-benchmark [ITERATIONS=number]
opa-concurrent-benchmark: build-concurrent
	$(eval ITERATIONS ?= 100)
	@echo "Running OPA Concurrent Benchmark - $(ITERATIONS) evaluations per policy"
	@echo "========================================================================"
	docker run --rm opa-concurrent-benchmark ./scripts/opa-concurrent-benchmark.sh $(ITERATIONS)

# Run WebAssembly benchmark comparing Rego vs WASM performance (default: 100)
# Usage: make opa-wasm-benchmark [ITERATIONS=number]
opa-wasm-benchmark: build-wasm
	$(eval ITERATIONS ?= 100)
	@echo "Running OPA WebAssembly Benchmark - $(ITERATIONS) evaluations per policy"
	@echo "========================================================================="
	docker run --rm opa-wasm-benchmark ./scripts/opa-wasm-benchmark.sh $(ITERATIONS)

# Run Profiling benchmark with CPU and memory analysis (default: 100)
# Usage: make opa-profiling-benchmark [ITERATIONS=number]
opa-profiling-benchmark: build-profiling
	$(eval ITERATIONS ?= 100)
	@echo "Running OPA Profiling Benchmark - $(ITERATIONS) evaluations per policy"
	@echo "========================================================================="
	docker run --rm opa-profiling-benchmark ./scripts/opa-profiling-benchmark.sh $(ITERATIONS)

# Run Optimization benchmark comparing original vs optimized policies (default: 100)
# Usage: make opa-optimization-benchmark [ITERATIONS=number]
opa-optimization-benchmark: build-optimization
	$(eval ITERATIONS ?= 100)
	@echo "Running OPA Profile-Guided Optimization Benchmark - $(ITERATIONS) evaluations per policy"
	@echo "=========================================================================================="
	docker run --rm opa-optimization-benchmark ./scripts/opa-optimization-benchmark.sh $(ITERATIONS)

# Run baseline benchmarks with 1000 iterations
baseline: 
	@echo "Running Baseline Benchmarks (1000 iterations each)"
	@echo "=================================================="
	@echo ""
	@echo "1/2: OPA CLI Benchmark"
	@echo "======================"
	@$(MAKE) opa-cli-benchmark ITERATIONS=1000
	@echo ""
	@echo "2/2: OPA Server Benchmark"
	@echo "========================="
	@$(MAKE) opa-server-benchmark ITERATIONS=1000

# Clean up Docker resources
clean:
	@echo "Cleaning up Docker resources..."
	-docker rmi opa-cli-benchmark opa-server-benchmark opa-bundle-benchmark opa-concurrent-benchmark opa-wasm-benchmark opa-profiling-benchmark opa-optimization-benchmark
	-docker system prune -f
	@echo "Cleanup complete!"

# Interactive containers for debugging
shell-cli: build-cli
	@echo "Starting interactive shell in CLI benchmark container..."
	docker run --rm -it opa-cli-benchmark bash

shell-server: build-server
	@echo "Starting interactive shell in Server benchmark container..."
	docker run --rm -it opa-server-benchmark bash

shell-bundle: build-bundle
	@echo "Starting interactive shell in Bundle benchmark container..."
	docker run --rm -it opa-bundle-benchmark bash

shell-concurrent: build-concurrent
	@echo "Starting interactive shell in Concurrent benchmark container..."
	docker run --rm -it opa-concurrent-benchmark bash

shell-wasm: build-wasm
	@echo "Starting interactive shell in WebAssembly benchmark container..."
	docker run --rm -it opa-wasm-benchmark bash

shell-profiling: build-profiling
	@echo "Starting interactive shell in Profiling benchmark container..."
	docker run --rm -it opa-profiling-benchmark bash

shell-optimization: build-optimization
	@echo "Starting interactive shell in Optimization benchmark container..."
	docker run --rm -it opa-optimization-benchmark bash

# Validate policies before benchmarking
validate: build-cli
	@echo "Validating OPA policies..."
	docker run --rm opa-cli-benchmark opa fmt --diff policies/
	@echo "Policy validation complete!"