#!/bin/bash

# OPA Bundle API Policy Benchmarking Script with Optimization
# Usage: ./opa-bundle-benchmark.sh <iterations>

set -e

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/benchmark-utils.sh"

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
    local results_file="$4"
    
    echo "Benchmarking: $policy_name"
    echo "----------------------------"
    
    # Warmup runs
    echo "Performing warmup..."
    for i in {1..10}; do
        curl -s -X POST "$OPA_SERVER_URL/v1/data/$endpoint" \
            -H "Content-Type: application/json" \
            -d "$input_data" >/dev/null 2>&1 || true
    done
    
    # Create temporary file for individual latencies
    local latencies_file=$(create_latency_temp_file)
    
    # Actual benchmark with individual timing
    echo "Running $ITERATIONS iterations..."
    
    local total_start_time=$(date +%s.%N)
    
    for ((i=1; i<=ITERATIONS; i++)); do
        # Time each individual HTTP request with nanosecond precision
        local request_start=$(date +%s.%N)
        curl -s -X POST "$OPA_SERVER_URL/v1/data/$endpoint" \
            -H "Content-Type: application/json" \
            -d "$input_data" >/dev/null 2>&1 || true
        local request_end=$(date +%s.%N)
        
        # Calculate and store latency in milliseconds with high precision
        local latency_ms=$(echo "scale=6; ($request_end - $request_start) * 1000" | bc -l)
        echo "$latency_ms" >> "$latencies_file"
        
        if [ $((i % 10)) -eq 0 ]; then
            echo -n "."
        fi
    done
    echo ""
    
    local total_end_time=$(date +%s.%N)
    local total_duration=$(echo "scale=6; $total_end_time - $total_start_time" | bc -l)
    
    # Calculate basic statistics
    local stats=$(calculate_basic_stats "$latencies_file")
    local count=$(echo $stats | cut -d' ' -f1)
    local sum=$(echo $stats | cut -d' ' -f2)
    local mean=$(echo $stats | cut -d' ' -f3)
    local min=$(echo $stats | cut -d' ' -f4)
    local max=$(echo $stats | cut -d' ' -f5)
    
    # Calculate percentiles
    local percentiles=$(calculate_percentiles "$latencies_file" "$ITERATIONS")
    local p50=$(echo $percentiles | cut -d' ' -f1)
    local p95=$(echo $percentiles | cut -d' ' -f2)
    local p99=$(echo $percentiles | cut -d' ' -f3)
    
    # Calculate policies per second
    local policies_per_second=$(echo "scale=2; $ITERATIONS / $total_duration" | bc -l)
    
    echo "Results:"
    echo "  Total time: ${total_duration}s"
    echo "  Average latency: ${mean}ms"
    echo "  Policies per second: ${policies_per_second}"
    
    # Display percentile information
    format_percentiles "$p50" "$p95" "$p99"
    
    echo "  Latency range: ${min}ms - ${max}ms"
    echo ""
    
    # Store results (extended format)
    echo "$policy_name,$ITERATIONS,$total_duration,$policies_per_second,$mean,$p50,$p95,$p99,$min,$max" >> "$results_file"
    
    # Clean up temporary file
    rm -f "$latencies_file"
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
    echo "Policy,Iterations,Duration(s),Policies/Second,Avg_Latency(ms),P50(ms),P95(ms),P99(ms),Min(ms),Max(ms)" > "$results_file"
    
    # Test server connectivity
    echo "Testing server connectivity..."
    if ! curl -s "$OPA_SERVER_URL/health" >/dev/null; then
        echo "ERROR: Cannot connect to OPA server"
        exit 1
    fi
    echo "Server connectivity OK"
    echo ""
    
    # Benchmark 1: Simple RBAC Policy
    benchmark_policy "Simple RBAC" "rbac/allow" "$RBAC_INPUT" "$results_file"
    
    # Benchmark 2: API Authorization Policy
    benchmark_policy "API Authorization" "api/authz/allow" "$API_INPUT" "$results_file"
    
    # Benchmark 3: Financial Risk Assessment Policy
    benchmark_policy "Financial Risk Assessment" "finance/risk/approve_loan" "$FINANCIAL_INPUT" "$results_file"
    
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

# Print comparison table with percentiles
printf "%-25s %10s %12s %12s %12s %12s\\n" "Policy" "Mode" "Requests/Sec" "Avg Latency" "P95 Latency" "P99 Latency"
printf "%-25s %10s %12s %12s %12s %12s\\n" "------" "----" "------------" "-----------" "-----------" "-----------"

# Show standard results
while IFS=',' read -r policy iterations duration policies_per_sec avg_latency p50 p95 p99 min max; do
    if [ "$policy" != "Policy" ]; then
        printf "%-25s %10s %12s %9.2f ms %9.2f ms %9.2f ms\\n" "$policy" "standard" "$policies_per_sec" "$avg_latency" "$p95" "$p99"
    fi
done < "$TEMP_DIR/results-standard.csv"

echo ""

# Show optimized results
while IFS=',' read -r policy iterations duration policies_per_sec avg_latency p50 p95 p99 min max; do
    if [ "$policy" != "Policy" ]; then
        printf "%-25s %10s %12s %9.2f ms %9.2f ms %9.2f ms\\n" "$policy" "optimized" "$policies_per_sec" "$avg_latency" "$p95" "$p99"
    fi
done < "$TEMP_DIR/results-optimized.csv"

echo ""
echo "=== OPTIMIZATION IMPACT ANALYSIS ==="
echo ""

# Show improvement analysis
while IFS=',' read -r policy iterations duration policies_per_sec avg_latency p50 p95 p99 min max; do
    if [ "$policy" != "Policy" ]; then
        # Get corresponding optimized result
        opt_result=$(awk -F',' -v p="$policy" '$1==p {print $4}' "$TEMP_DIR/results-optimized.csv")
        opt_latency=$(awk -F',' -v p="$policy" '$1==p {print $5}' "$TEMP_DIR/results-optimized.csv")
        opt_p95=$(awk -F',' -v p="$policy" '$1==p {print $7}' "$TEMP_DIR/results-optimized.csv")
        
        if [ -n "$opt_result" ]; then
            improvement=$(echo "scale=2; ($opt_result - $policies_per_sec) / $policies_per_sec * 100" | bc -l)
            latency_improvement=$(echo "scale=2; ($avg_latency - $opt_latency) / $avg_latency * 100" | bc -l)
            echo "--- $policy Optimization Impact ---"
            echo "  Requests/sec: $policies_per_sec → $opt_result (${improvement}% improvement)"
            echo "  Avg latency: ${avg_latency}ms → ${opt_latency}ms (${latency_improvement}% improvement)"
            echo "  P95 latency: ${p95}ms → ${opt_p95}ms"
            echo ""
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