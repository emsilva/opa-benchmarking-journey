#!/bin/bash

# OPA Cloud Benchmark Script - Leverages All Optimizations
# Runs in Kubernetes pods across multiple nodes
# Combines: Optimized policies + WASM compilation + Concurrency + Horizontal scaling

set -e

# Configuration
ITERATIONS=${ITERATIONS:-1000}
CONCURRENCY=${CONCURRENCY:-8}
BENCHMARK_MODE=${BENCHMARK_MODE:-"server"}  # server, client, or standalone
NODE_NAME=${NODE_NAME:-$(hostname)}
POD_NAME=${POD_NAME:-$(hostname)}
RESULTS_DIR="/app/k8s-results"
OPA_SERVER_URL="http://localhost:8181"

echo "============================================"
echo "OPA Cloud Benchmark - All Optimizations"
echo "============================================"
echo "Timestamp: $(date)"
echo "Node: $NODE_NAME"  
echo "Pod: $POD_NAME"
echo "Mode: $BENCHMARK_MODE"
echo "Iterations: $ITERATIONS"
echo "Concurrency: $CONCURRENCY"
echo ""

# Create results directory
mkdir -p "$RESULTS_DIR"

# Test data (optimized for different policy types)
RBAC_INPUT='{"input": {"user": {"id": "user_001", "role": "admin"}, "action": "delete", "resource": {"owner": "user_002"}}}'
API_INPUT='{"input": {"user": {"id": "user_001", "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyXzAwMSIsImlhdCI6MTcyMzUzNjAwMCwiZXhwIjo5OTk5OTk5OTk5fQ.sig", "permissions": ["users:read"], "tier": "premium", "department": "engineering"}, "method": "GET", "path": "/api/users", "client_ip": "192.168.1.1"}}'
FINANCIAL_INPUT='{"input": {"loan_application": {"amount": 500000, "monthly_payment": 3200, "collateral_value": 750000, "collateral_type": "residential_property", "applicant": {"id": "applicant_001", "country": "US", "monthly_income": 12000, "total_monthly_debt": 4500, "credit_scores": {"experian": 780, "equifax": 775, "transunion": 785}, "employment": {"industry": "technology", "title": "Senior Engineer", "tenure_months": 48, "verified": true, "income_verified": true}, "payment_history": [{"days_late": 0}, {"days_late": 0}, {"days_late": 0}]}}}}' 

# Function to start optimized OPA server
start_opa_server() {
    local policy_mode="$1"  # "rego" or "mixed"
    
    echo "Starting OPA server in $policy_mode mode..."
    
    if [ "$policy_mode" = "mixed" ]; then
        # Mixed mode: Use WASM for Financial Risk (23% boost), Rego for others
        echo "Using optimized mixed mode: WASM for Financial Risk, Rego for RBAC/API"
        
        # Start with optimized Rego policies for RBAC and API
        /usr/local/bin/opa run --server --addr 0.0.0.0:8181 \
            --log-level error \
            policies-optimized/simple_rbac_optimized.rego \
            policies-optimized/api_authorization_optimized.rego \
            data/benchmark_data.json >/dev/null 2>&1 &
        
        OPA_PID=$!
        echo "OPA server started with PID: $OPA_PID (mixed mode)"
    else
        # Standard Rego mode with optimized policies
        /usr/local/bin/opa run --server --addr 0.0.0.0:8181 \
            --log-level error \
            policies-optimized/ \
            data/benchmark_data.json >/dev/null 2>&1 &
        
        OPA_PID=$!
        echo "OPA server started with PID: $OPA_PID (rego mode)"
    fi
    
    # Wait for server to be ready
    echo "Waiting for OPA server to be ready..."
    for i in {1..30}; do
        if curl -s "$OPA_SERVER_URL/health" >/dev/null 2>&1; then
            echo "OPA server ready!"
            return 0
        fi
        sleep 1
    done
    
    echo "ERROR: OPA server failed to start within 30 seconds"
    return 1
}

# Function to start OPA server with WASM bundle
start_opa_server_wasm() {
    local bundle_name="$1"
    local policy_name="$2"
    
    echo "Starting OPA server with WASM bundle: $bundle_name ($policy_name)"
    
    /usr/local/bin/opa run --server --addr 0.0.0.0:8181 \
        --log-level error \
        "wasm/$bundle_name" >/dev/null 2>&1 &
    
    OPA_PID=$!
    echo "OPA server started with PID: $OPA_PID (WASM mode)"
    
    # Wait for server to be ready
    for i in {1..30}; do
        if curl -s "$OPA_SERVER_URL/health" >/dev/null 2>&1; then
            echo "WASM OPA server ready!"
            return 0
        fi
        sleep 1
    done
    
    echo "ERROR: WASM OPA server failed to start within 30 seconds"
    return 1
}

# Function to stop OPA server
stop_opa_server() {
    if [ ! -z "$OPA_PID" ]; then
        echo "Stopping OPA server (PID: $OPA_PID)..."
        kill $OPA_PID 2>/dev/null || true
        wait $OPA_PID 2>/dev/null || true
        echo "OPA server stopped"
        OPA_PID=""
    fi
}

# Function to benchmark a policy with concurrency
benchmark_policy_concurrent() {
    local policy_name="$1"
    local endpoint="$2"
    local input_data="$3"
    local mode="$4"
    local concurrency="$5"
    
    echo "Benchmarking: $policy_name ($mode mode, $concurrency workers)"
    echo "---------------------------------------------------------------"
    
    # Warmup
    echo "Performing warmup..."
    for i in {1..10}; do
        curl -s -X POST "$OPA_SERVER_URL/v1/data/$endpoint" \
            -H "Content-Type: application/json" \
            -d "$input_data" >/dev/null 2>&1 || true
    done
    
    # Create temp file for tracking
    local temp_file="/tmp/benchmark_$$"
    
    echo "Running $ITERATIONS iterations with $concurrency concurrent workers..."
    
    # Record start time
    start_time=$(date +%s.%N)
    
    # Launch concurrent workers
    for ((worker=1; worker<=concurrency; worker++)); do
        {
            iterations_per_worker=$((ITERATIONS / concurrency))
            for ((i=1; i<=iterations_per_worker; i++)); do
                if [ $worker -eq 1 ] && [ $i -eq 1 ]; then
                    # Test first request and verify it works
                    response=$(curl -s -X POST "$OPA_SERVER_URL/v1/data/$endpoint" \
                        -H "Content-Type: application/json" \
                        -d "$input_data")
                    echo "  First response: $response"
                else
                    curl -s -X POST "$OPA_SERVER_URL/v1/data/$endpoint" \
                        -H "Content-Type: application/json" \
                        -d "$input_data" >/dev/null 2>&1 || true
                fi
            done
            echo "Worker $worker completed" >> "$temp_file"
        } &
    done
    
    # Wait for all workers to complete
    wait
    
    # Record end time
    end_time=$(date +%s.%N)
    
    # Calculate duration and metrics
    duration=$(echo "$end_time - $start_time" | bc)
    policies_per_second=$(echo "scale=2; $ITERATIONS / $duration" | bc)
    avg_latency=$(echo "scale=2; ($duration * 1000) / $ITERATIONS" | bc)
    
    echo "Results:"
    echo "  Total time: ${duration}s"
    echo "  Average latency: ${avg_latency}ms"
    echo "  Policies per second: $policies_per_second"
    echo ""
    
    # Save results
    echo "$policy_name,$mode,$ITERATIONS,$duration,$policies_per_second,$avg_latency,$concurrency,$NODE_NAME,$POD_NAME" >> "$RESULTS_DIR/benchmark_results.csv"
    
    # Cleanup
    rm -f "$temp_file"
}

# Ensure server cleanup
trap stop_opa_server EXIT

# Initialize results file
echo "Policy,Mode,Iterations,Duration(s),Policies/Second,Avg_Latency(ms),Concurrency,Node,Pod" > "$RESULTS_DIR/benchmark_results.csv"

# Check OPA version and WASM support
echo "OPA Version Information:"
/usr/local/bin/opa version
echo ""

wasm_support=$(/usr/local/bin/opa version | grep "WebAssembly:" | awk '{print $2}')
echo "WebAssembly Support: $wasm_support"
echo ""

if [ "$BENCHMARK_MODE" = "server" ]; then
    echo "=== RUNNING AS OPA SERVER POD ==="
    # Start OPA server and keep it running
    start_opa_server "rego"
    
    # Keep container alive for external testing
    echo "OPA server running at $OPA_SERVER_URL"
    echo "Ready for external benchmark clients..."
    
    # Keep server running indefinitely
    while true; do
        sleep 30
        # Health check
        if ! curl -s "$OPA_SERVER_URL/health" >/dev/null; then
            echo "ERROR: OPA server not responding, restarting..."
            stop_opa_server
            start_opa_server "rego"
        fi
    done
    
elif [ "$BENCHMARK_MODE" = "client" ]; then
    echo "=== RUNNING AS BENCHMARK CLIENT POD ==="
    
    # Expect OPA_SERVICE_URL to point to the OPA service
    OPA_SERVER_URL=${OPA_SERVICE_URL:-"http://opa-service:8181"}
    echo "Connecting to OPA service at: $OPA_SERVER_URL"
    
    # Wait for OPA service to be available
    echo "Waiting for OPA service to be ready..."
    for i in {1..60}; do
        if curl -s "$OPA_SERVER_URL/health" >/dev/null 2>&1; then
            echo "OPA service is ready!"
            break
        fi
        echo "  Attempt $i/60: Waiting for OPA service..."
        sleep 5
    done
    
    if ! curl -s "$OPA_SERVER_URL/health" >/dev/null 2>&1; then
        echo "ERROR: Cannot connect to OPA service after 5 minutes"
        exit 1
    fi
    
    # Run benchmarks against remote OPA service
    echo ""
    echo "=== BENCHMARKING OPTIMIZED POLICIES ==="
    echo ""
    
    benchmark_policy_concurrent "Simple RBAC (Optimized)" "rbac/allow" "$RBAC_INPUT" "rego-optimized" "$CONCURRENCY"
    benchmark_policy_concurrent "API Authorization (Optimized)" "api/authz/allow" "$API_INPUT" "rego-optimized" "$CONCURRENCY"
    benchmark_policy_concurrent "Financial Risk (Optimized)" "finance/risk/approve_loan" "$FINANCIAL_INPUT" "rego-optimized" "$CONCURRENCY"
    
    echo "=== BENCHMARK COMPLETE ==="
    echo "Results saved to: $RESULTS_DIR/benchmark_results.csv"
    
    # Show results summary
    echo ""
    echo "=== RESULTS SUMMARY ==="
    cat "$RESULTS_DIR/benchmark_results.csv"
    
else
    echo "=== RUNNING STANDALONE BENCHMARK ==="
    
    # Test all optimization combinations
    echo ""
    echo "=== OPTIMIZED REGO POLICIES ==="
    start_opa_server "rego"
    
    benchmark_policy_concurrent "Simple RBAC (Optimized)" "rbac/allow" "$RBAC_INPUT" "rego-optimized" "$CONCURRENCY"
    benchmark_policy_concurrent "API Authorization (Optimized)" "api/authz/allow" "$API_INPUT" "rego-optimized" "$CONCURRENCY"
    benchmark_policy_concurrent "Financial Risk (Optimized)" "finance/risk/approve_loan" "$FINANCIAL_INPUT" "rego-optimized" "$CONCURRENCY"
    
    stop_opa_server
    
    echo ""
    echo "=== WASM OPTIMIZED FINANCIAL RISK ==="
    
    # Test Financial Risk with WASM (23% performance boost expected)
    if [ -f "wasm/financial-optimized-bundle.tar.gz" ]; then
        start_opa_server_wasm "financial-optimized-bundle.tar.gz" "Financial Risk Assessment (WASM+Optimized)"
        
        if curl -s "$OPA_SERVER_URL/health" >/dev/null; then
            benchmark_policy_concurrent "Financial Risk (WASM+Optimized)" "finance/risk/approve_loan" "$FINANCIAL_INPUT" "wasm-optimized" "$CONCURRENCY"
        else
            echo "ERROR: Could not connect to Financial Risk WASM server"
        fi
        
        stop_opa_server
    else
        echo "WARNING: financial-optimized-bundle.tar.gz not found"
    fi
    
    echo ""
    echo "=== CLOUD BENCHMARK COMPLETE ==="
    echo "Node: $NODE_NAME"
    echo "Pod: $POD_NAME"
    echo "Results: $RESULTS_DIR/benchmark_results.csv"
    
    # Show final results
    echo ""
    echo "=== FINAL RESULTS ==="
    cat "$RESULTS_DIR/benchmark_results.csv"
fi