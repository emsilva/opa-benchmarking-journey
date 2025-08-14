#!/bin/bash

# OPA Server-based Policy Benchmarking Script
# Usage: ./benchmark2.sh <iterations>

set -e

ITERATIONS=${1:-100}
TEMP_DIR="/tmp/opa-benchmark"
OPA_SERVER_URL="http://localhost:8181"

echo "OPA Server-based Policy Benchmarking"
echo "====================================="
echo "Iterations per policy: $ITERATIONS"
echo "Server URL: $OPA_SERVER_URL"
echo "Timestamp: $(date)"
echo ""

# Create temp directory for results
mkdir -p "$TEMP_DIR"

# Test data for each policy
RBAC_INPUT='{"input": {"user": {"id": "user_001", "role": "admin"}, "action": "delete", "resource": {"owner": "user_002"}}}'
API_INPUT='{"input": {"user": {"id": "user_001", "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyXzAwMSIsImlhdCI6MTcyMzUzNjAwMCwiZXhwIjo5OTk5OTk5OTk5fQ.sig", "permissions": ["users:read"], "tier": "premium", "department": "engineering"}, "method": "GET", "path": "/api/users", "client_ip": "192.168.1.1"}}'
FINANCIAL_INPUT='{"input": {"loan_application": {"amount": 500000, "monthly_payment": 3200, "collateral_value": 750000, "collateral_type": "residential_property", "applicant": {"id": "applicant_001", "country": "US", "monthly_income": 12000, "total_monthly_debt": 4500, "credit_scores": {"experian": 780, "equifax": 775, "transunion": 785}, "employment": {"industry": "technology", "title": "Senior Engineer", "tenure_months": 48, "verified": true, "income_verified": true}, "payment_history": [{"days_late": 0}, {"days_late": 0}, {"days_late": 0}]}}}}'

# Function to start OPA server
start_opa_server() {
    echo "Starting OPA server..."
    
    # Load policies and data into server (suppress logging for performance)
    opa run --server --addr 0.0.0.0:8181 \
        policies/ data/benchmark_data.json >/dev/null 2>&1 &
    
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

# Function to benchmark a policy via HTTP API
benchmark_policy_http() {
    local policy_name="$1"
    local endpoint="$2"
    local input_data="$3"
    
    echo "Benchmarking: $policy_name (HTTP API)"
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

# Trap to ensure server cleanup
trap stop_opa_server EXIT

# Check if bc is available, install if needed
if ! command -v bc &> /dev/null; then
    echo "Installing bc calculator..."
    apk add --no-cache bc
fi

# Start OPA server
start_opa_server

# Initialize results file
echo "Policy,Iterations,Duration(s),Policies/Second,Avg_Latency(ms)" > "$TEMP_DIR/results.csv"

echo "Starting benchmarks..."
echo ""

# Test server connectivity
echo "Testing server connectivity..."
if ! curl -s "$OPA_SERVER_URL/health" >/dev/null; then
    echo "ERROR: Cannot connect to OPA server"
    exit 1
fi
echo "Server connectivity OK"
echo ""

# Benchmark 1: Simple RBAC Policy
benchmark_policy_http "Simple RBAC" "rbac/allow" "$RBAC_INPUT"

# Benchmark 2: API Authorization Policy
benchmark_policy_http "API Authorization" "api/authz/allow" "$API_INPUT"

# Benchmark 3: Financial Risk Assessment Policy
benchmark_policy_http "Financial Risk Assessment" "finance/risk/approve_loan" "$FINANCIAL_INPUT"

echo "=== BENCHMARK SUMMARY ==="
echo ""

# Print summary table
printf "%-25s %10s %15s %12s\n" "Policy" "Iterations" "Policies/Sec" "Avg Latency"
printf "%-25s %10s %15s %12s\n" "------" "----------" "------------" "-----------"

while IFS=',' read -r policy iterations duration policies_per_sec latency; do
    if [ "$policy" != "Policy" ]; then
        printf "%-25s %10s %15s %9s ms\n" "$policy" "$iterations" "$policies_per_sec" "$latency"
    fi
done < "$TEMP_DIR/results.csv"

echo ""

# Calculate complexity ratios
echo "=== COMPLEXITY ANALYSIS ==="
echo ""

simple_rate=$(awk -F',' '/Simple RBAC/ {print $4}' "$TEMP_DIR/results.csv")
api_rate=$(awk -F',' '/API Authorization/ {print $4}' "$TEMP_DIR/results.csv")
financial_rate=$(awk -F',' '/Financial Risk/ {print $4}' "$TEMP_DIR/results.csv")

if [ -n "$simple_rate" ] && [ -n "$api_rate" ] && [ -n "$financial_rate" ]; then
    api_ratio=$(echo "scale=2; $simple_rate / $api_rate" | bc -l)
    financial_ratio=$(echo "scale=2; $simple_rate / $financial_rate" | bc -l)
    
    echo "Performance impact of complexity (HTTP API):"
    echo "  API Authorization is ${api_ratio}x slower than Simple RBAC"
    echo "  Financial Risk is ${financial_ratio}x slower than Simple RBAC"
    echo ""
fi

# Lines of code comparison
echo "=== CODE COMPLEXITY ==="
echo ""
simple_loc=$(wc -l < policies/simple_rbac.rego)
api_loc=$(wc -l < policies/api_authorization.rego)
financial_loc=$(wc -l < policies/financial_risk_assessment.rego)

printf "%-25s %10s %15s\n" "Policy" "Lines" "Complexity"
printf "%-25s %10s %15s\n" "------" "-----" "----------"
printf "%-25s %10d %15s\n" "Simple RBAC" "$simple_loc" "1x (baseline)"
printf "%-25s %10d %15.1fx\n" "API Authorization" "$api_loc" "$(echo "scale=1; $api_loc / $simple_loc" | bc -l)"
printf "%-25s %10d %15.1fx\n" "Financial Risk" "$financial_loc" "$(echo "scale=1; $financial_loc / $simple_loc" | bc -l)"

echo ""
echo "=== BENCHMARK COMPLETE ==="
echo "Mode: OPA Server (HTTP API)"
echo "Raw results saved to: $TEMP_DIR/results.csv"
echo "Container: $(hostname)"
echo "OPA Version: $(opa version)"
echo ""