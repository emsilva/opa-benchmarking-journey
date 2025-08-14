#!/bin/bash

# OPA Bundle API Policy Benchmarking Script with Optimization
# Usage: ./opa-bundle-benchmark.sh <iterations>

set -e

ITERATIONS=${1:-100}
TEMP_DIR="/tmp/opa-benchmark"
OPA_SERVER_URL="http://localhost:8181"

echo "OPA Bundle API Policy Benchmarking"
echo "=================================="
echo "Iterations per policy: $ITERATIONS"
echo "Server URL: $OPA_SERVER_URL"
echo "Optimization: --optimize-store-for-read-speed"
echo "Timestamp: $(date)"
echo ""

# Create temp directory for results
mkdir -p "$TEMP_DIR"

# Test data for each policy
RBAC_INPUT='{"input": {"user": {"id": "user_001", "role": "admin"}, "action": "delete", "resource": {"owner": "user_002"}}}'
API_INPUT='{"input": {"user": {"id": "user_001", "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyXzAwMSIsImlhdCI6MTcyMzUzNjAwMCwiZXhwIjo5OTk5OTk5OTk5fQ.sig", "permissions": ["users:read"], "tier": "premium", "department": "engineering"}, "method": "GET", "path": "/api/users", "client_ip": "192.168.1.1"}}'
FINANCIAL_INPUT='{"input": {"loan_application": {"amount": 500000, "monthly_payment": 3200, "collateral_value": 750000, "collateral_type": "residential_property", "applicant": {"id": "applicant_001", "country": "US", "monthly_income": 12000, "total_monthly_debt": 4500, "credit_scores": {"experian": 780, "equifax": 775, "transunion": 785}, "employment": {"industry": "technology", "title": "Senior Engineer", "tenure_months": 48, "verified": true, "income_verified": true}, "payment_history": [{"days_late": 0}, {"days_late": 0}, {"days_late": 0}]}}}}'

# Function to start OPA server with optimization
start_opa_server() {
    local optimization_mode="$1"
    
    echo "Starting OPA server with $optimization_mode..."
    
    if [ "$optimization_mode" = "optimized" ]; then
        # Load policies with read-speed optimization
        opa run --server --addr 0.0.0.0:8181 \
            --optimize-store-for-read-speed \
            policies/ data/benchmark_data.json >/dev/null 2>&1 &
    else
        # Load policies without optimization
        opa run --server --addr 0.0.0.0:8181 \
            policies/ data/benchmark_data.json >/dev/null 2>&1 &
    fi
    
    OPA_PID=$!
    echo "OPA server started with PID: $OPA_PID"
    
    # Wait for server to be ready
    echo "Waiting for OPA server to be ready..."
    for i in {1..30}; do
        if curl -s "$OPA_SERVER_URL/health" >/dev/null 2>&1; then
            echo "OPA server is ready!"
            return 0
        fi
        sleep 1
        echo -n "."
    done
    
    echo ""
    echo "ERROR: OPA server failed to start within 30 seconds"
    return 1
}

# Function to stop OPA server
stop_opa_server() {
    if [ ! -z "$OPA_PID" ]; then
        echo "Stopping OPA server (PID: $OPA_PID)..."
        kill $OPA_PID 2>/dev/null || true
        wait $OPA_PID 2>/dev/null || true
        echo "OPA server stopped"
    fi
}

# Function to benchmark a policy
benchmark_policy() {
    local policy_name="$1"
    local endpoint="$2"
    local input_data="$3"
    
    echo "Benchmarking: $policy_name"
    echo "----------------------------"
    
    # Warmup runs
    echo "Performing warmup..."
    for i in {1..10}; do
        curl -s -X POST "$OPA_SERVER_URL/v1/data/$endpoint" \
            -H "Content-Type: application/json" \
            -d "$input_data" >/dev/null 2>&1 || true
    done
    
    # Actual benchmark
    echo "Running $ITERATIONS iterations..."
    
    # Use /proc/uptime for better precision timing
    start_time=$(awk '{print $1}' /proc/uptime)
    
    for ((i=1; i<=ITERATIONS; i++)); do
        curl -s -X POST "$OPA_SERVER_URL/v1/data/$endpoint" \
            -H "Content-Type: application/json" \
            -d "$input_data" >/dev/null 2>&1 || true
        if [ $((i % 10)) -eq 0 ]; then
            echo -n "."
        fi
    done
    echo ""
    
    end_time=$(awk '{print $1}' /proc/uptime)
    duration=$(echo "$end_time - $start_time" | bc -l)
    
    # Ensure minimum duration to avoid division by zero
    if [ "$(echo "$duration < 0.001" | bc -l)" -eq 1 ]; then
        duration="0.001"
    fi
    
    # Calculate policies per second
    policies_per_second=$(echo "scale=2; $ITERATIONS / $duration" | bc -l)
    avg_latency_ms=$(echo "scale=2; ($duration * 1000) / $ITERATIONS" | bc -l)
    
    echo "Results:"
    echo "  Total time: ${duration}s"
    echo "  Average latency: ${avg_latency_ms}ms"
    echo "  Policies per second: ${policies_per_second}"
    echo ""
    
    # Store results
    echo "$policy_name,$ITERATIONS,$duration,$policies_per_second,$avg_latency_ms" >> "$TEMP_DIR/results.csv"
}

# Function to run full benchmark suite
run_benchmark_suite() {
    local optimization_mode="$1"
    local results_file="$2"
    
    echo "=== RUNNING BENCHMARK SUITE: $optimization_mode ==="
    echo ""
    
    # Trap to ensure server cleanup
    trap stop_opa_server EXIT
    
    # Start OPA server
    start_opa_server "$optimization_mode"
    
    # Initialize results file
    echo "Policy,Iterations,Duration(s),Policies/Second,Avg_Latency(ms)" > "$results_file"
    
    # Test server connectivity
    echo "Testing server connectivity..."
    if ! curl -s "$OPA_SERVER_URL/health" >/dev/null; then
        echo "ERROR: Cannot connect to OPA server"
        exit 1
    fi
    echo "Server connectivity OK"
    echo ""
    
    # Benchmark 1: Simple RBAC Policy
    benchmark_policy "Simple RBAC" "rbac/allow" "$RBAC_INPUT"
    
    # Benchmark 2: API Authorization Policy
    benchmark_policy "API Authorization" "api/authz/allow" "$API_INPUT"
    
    # Benchmark 3: Financial Risk Assessment Policy
    benchmark_policy "Financial Risk Assessment" "finance/risk/approve_loan" "$FINANCIAL_INPUT"
    
    # Stop server
    stop_opa_server
    trap - EXIT
}

# Check if bc is available
if ! command -v bc &> /dev/null; then
    echo "Installing bc calculator..."
    apk add --no-cache bc
fi

echo "=== OPA STORE OPTIMIZATION BENCHMARK ==="
echo ""

# Run standard server (no optimization)
run_benchmark_suite "standard" "$TEMP_DIR/results-standard.csv"

echo ""
echo "Waiting 5 seconds before next benchmark..."
sleep 5
echo ""

# Run optimized server
run_benchmark_suite "optimized" "$TEMP_DIR/results-optimized.csv"

echo ""
echo "=== STORE OPTIMIZATION COMPARISON ==="
echo ""

# Print comparison table
printf "%-25s %15s %15s %15s %15s\\n" "Policy" "Standard" "Optimized" "Improvement" "Latency"
printf "%-25s %15s %15s %15s %15s\\n" "------" "---------" "---------" "-----------" "-------"

while IFS=',' read -r policy iterations duration policies_per_sec latency; do
    if [ "$policy" != "Policy" ]; then
        # Get corresponding optimized result
        opt_result=$(awk -F',' -v p="$policy" '$1==p {print $4}' "$TEMP_DIR/results-optimized.csv")
        opt_latency=$(awk -F',' -v p="$policy" '$1==p {print $5}' "$TEMP_DIR/results-optimized.csv")
        
        if [ -n "$opt_result" ]; then
            improvement=$(echo "scale=2; ($opt_result - $policies_per_sec) / $policies_per_sec * 100" | bc -l)
            printf "%-25s %15s %15s %14s%% %12s ms\\n" "$policy" "$policies_per_sec" "$opt_result" "$improvement" "$opt_latency"
        fi
    fi
done < "$TEMP_DIR/results-standard.csv"

echo ""
echo "=== BENCHMARK COMPLETE ==="
echo "Mode: OPA Server with Store Optimization"
echo "Standard: $TEMP_DIR/results-standard.csv"
echo "Optimized: $TEMP_DIR/results-optimized.csv"
echo "Container: $(hostname)"
echo "OPA Version: $(opa version)"
echo ""
echo "Key Insight: --optimize-store-for-read-speed trades memory for faster policy evaluation"
echo ""