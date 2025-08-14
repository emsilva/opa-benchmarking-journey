#!/bin/bash

# OPA Policy Benchmarking Script
# Usage: ./benchmark.sh <iterations>

set -e

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/benchmark-utils.sh"

ITERATIONS=${1:-100}
TEMP_DIR="/tmp/opa-benchmark"

echo "OPA Policy Benchmarking"
echo "======================"
echo "Iterations per policy: $ITERATIONS"
echo "Timestamp: $(date)"
echo ""

# Create temp directory for results
mkdir -p "$TEMP_DIR"

# Test data for each policy
RBAC_INPUT='{"user": {"id": "user_001", "role": "admin"}, "action": "delete", "resource": {"owner": "user_002"}}'
API_INPUT='{"user": {"id": "user_001", "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyXzAwMSIsImlhdCI6MTcyMzUzNjAwMCwiZXhwIjo5OTk5OTk5OTk5fQ.sig", "permissions": ["users:read"], "tier": "premium", "department": "engineering"}, "method": "GET", "path": "/api/users", "client_ip": "192.168.1.1"}'
FINANCIAL_INPUT='{"loan_application": {"amount": 500000, "monthly_payment": 3200, "collateral_value": 750000, "collateral_type": "residential_property", "applicant": {"id": "applicant_001", "country": "US", "monthly_income": 12000, "total_monthly_debt": 4500, "credit_scores": {"experian": 780, "equifax": 775, "transunion": 785}, "employment": {"industry": "technology", "title": "Senior Engineer", "tenure_months": 48, "verified": true, "income_verified": true}, "payment_history": [{"days_late": 0}, {"days_late": 0}, {"days_late": 0}]}}}'

# Function to benchmark a policy
benchmark_policy() {
    local policy_name="$1"
    local policy_file="$2"
    local input_data="$3"
    local query="$4"
    local data_file="$5"
    
    echo "Benchmarking: $policy_name"
    echo "----------------------------"
    
    # Warmup runs
    echo "Performing warmup..."
    for i in {1..10}; do
        echo "$input_data" | opa eval -d "$policy_file" ${data_file:+-d "$data_file"} "$query" >/dev/null 2>&1 || true
    done
    
    # Create temporary file for individual latencies
    local latencies_file=$(create_latency_temp_file)
    
    # Actual benchmark with individual timing
    echo "Running $ITERATIONS iterations..."
    
    local total_start_time=$(date +%s.%N)
    
    for ((i=1; i<=ITERATIONS; i++)); do
        # Time each individual request with nanosecond precision
        local request_start=$(date +%s.%N)
        echo "$input_data" | opa eval -d "$policy_file" ${data_file:+-d "$data_file"} "$query" >/dev/null 2>&1 || true
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
    echo "$policy_name,$ITERATIONS,$total_duration,$policies_per_second,$mean,$p50,$p95,$p99,$min,$max" >> "$TEMP_DIR/results.csv"
    
    # Clean up temporary file
    rm -f "$latencies_file"
}

# Initialize results file with extended columns
echo "Policy,Iterations,Duration(s),Policies/Second,Avg_Latency(ms),P50(ms),P95(ms),P99(ms),Min(ms),Max(ms)" > "$TEMP_DIR/results.csv"

# Check if bc is available, install if needed
if ! command -v bc &> /dev/null; then
    echo "Installing bc calculator..."
    apk add --no-cache bc
fi

echo "Starting benchmarks..."
echo ""

# Benchmark 1: Simple RBAC Policy
benchmark_policy "Simple RBAC" "policies/simple_rbac.rego" "$RBAC_INPUT" "data.rbac.allow" ""

# Benchmark 2: API Authorization Policy  
benchmark_policy "API Authorization" "policies/api_authorization.rego" "$API_INPUT" "data.api.authz.allow" "data/benchmark_data.json"

# Benchmark 3: Financial Risk Assessment Policy
benchmark_policy "Financial Risk Assessment" "policies/financial_risk_assessment.rego" "$FINANCIAL_INPUT" "data.finance.risk.approve_loan" "data/benchmark_data.json"

echo "=== BENCHMARK SUMMARY ==="
echo ""

# Print summary table with percentiles
printf "%-25s %10s %15s %12s %12s %12s\n" "Policy" "Iterations" "Policies/Sec" "Avg Latency" "P95 Latency" "P99 Latency"
printf "%-25s %10s %15s %12s %12s %12s\n" "------" "----------" "------------" "-----------" "-----------" "-----------"

while IFS=',' read -r policy iterations duration policies_per_sec avg_latency p50 p95 p99 min max; do
    if [ "$policy" != "Policy" ]; then
        printf "%-25s %10s %15s %9.2f ms %9.2f ms %9.2f ms\n" "$policy" "$iterations" "$policies_per_sec" "$avg_latency" "$p95" "$p99"
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
    
    echo "Performance impact of complexity:"
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
echo "Raw results saved to: $TEMP_DIR/results.csv"
echo "Container: $(hostname)"
echo "OPA Version: $(opa version)"
echo ""