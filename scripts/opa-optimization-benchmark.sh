#!/bin/bash

# OPA Profile-Guided Optimization Benchmark Script
# Compares original vs optimized policies based on profiling analysis
# Usage: ./opa-optimization-benchmark.sh <iterations>

set -e

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/benchmark-utils.sh"

ITERATIONS=${1:-1000}
TEMP_DIR="/tmp/opa-benchmark"
OPA_SERVER_URL="http://localhost:8181"
RESULTS_DIR="/app/results"
PROFILE_DIR="/app/profiles"

echo "OPA Profile-Guided Optimization Benchmark"
echo "========================================="
echo "Iterations per policy: $ITERATIONS"
echo "Server URL: $OPA_SERVER_URL"
echo "Results Directory: $RESULTS_DIR"
echo "Timestamp: $(date)"
echo ""

# Create directories
mkdir -p "$TEMP_DIR" "$RESULTS_DIR" "$PROFILE_DIR"

# Test data for each policy
RBAC_INPUT='{"input": {"user": {"id": "user_001", "role": "editor"}, "action": "write", "resource": {"owner": "user_002"}}}'
API_INPUT='{"input": {"user": {"id": "user_001", "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyXzAwMSIsImlhdCI6MTcyMzUzNjAwMCwiZXhwIjo5OTk5OTk5OTk5fQ.sig", "permissions": ["users:read"], "tier": "premium", "department": "engineering"}, "method": "GET", "path": "/api/users", "client_ip": "192.168.1.1"}}'
FINANCIAL_INPUT='{"input": {"loan_application": {"amount": 500000, "monthly_payment": 3200, "collateral_value": 750000, "collateral_type": "residential_property", "applicant": {"id": "applicant_001", "country": "US", "monthly_income": 12000, "total_monthly_debt": 4500, "credit_scores": {"experian": 780, "equifax": 775, "transunion": 785}, "employment": {"industry": "technology", "title": "Senior Engineer", "tenure_months": 48, "verified": true, "income_verified": true}, "payment_history": [{"days_late": 0}, {"days_late": 0}, {"days_late": 0}]}}}}' 

# Function to start OPA server
start_opa_server() {
    local policy_dir="$1"
    local mode="$2"
    
    echo "Starting OPA server ($mode mode) with policies from $policy_dir..."
    
    # Start OPA server with profiling enabled
    /usr/local/bin/opa run --server --addr 0.0.0.0:8181 \
        --diagnostic-addr 0.0.0.0:8282 \
        "$policy_dir/" data/benchmark_data.json >/dev/null 2>&1 &
    
    OPA_PID=$!
    echo "OPA server started with PID: $OPA_PID ($mode mode)"
    
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
        OPA_PID=""
    fi
}

# Function to benchmark a policy
benchmark_policy() {
    local policy_name="$1"
    local endpoint="$2"
    local input_data="$3"
    local mode="$4"  # "original" or "optimized"
    
    echo "Benchmarking: $policy_name ($mode)"
    echo "---------------------------------------"
    
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
        
        # Test one request and verify it works
        if [ $i -eq 1 ]; then
            response=$(curl -s -X POST "$OPA_SERVER_URL/v1/data/$endpoint" \
                -H "Content-Type: application/json" \
                -d "$input_data")
            echo "  First response: $response"
        else
            curl -s -X POST "$OPA_SERVER_URL/v1/data/$endpoint" \
                -H "Content-Type: application/json" \
                -d "$input_data" >/dev/null 2>&1 || true
        fi
        
        local request_end=$(date +%s.%N)
        
        # Calculate and store latency in milliseconds with high precision
        local latency_ms=$(echo "scale=6; ($request_end - $request_start) * 1000" | bc -l)
        echo "$latency_ms" >> "$latencies_file"
        
        if [ $((i % 100)) -eq 0 ]; then
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
    echo "$policy_name,$mode,$ITERATIONS,$total_duration,$policies_per_second,$mean,$p50,$p95,$p99,$min,$max" >> "$RESULTS_DIR/optimization_results.csv"
    
    # Clean up temporary file
    rm -f "$latencies_file"
}

# Function to collect CPU profile during execution
collect_optimization_profile() {
    local policy_name="$1"
    local endpoint="$2"
    local input_data="$3"
    local mode="$4"
    
    echo "Collecting CPU profile for: $policy_name ($mode)"
    
    # Start CPU profiling in background
    local profile_file="$PROFILE_DIR/${policy_name// /_}_${mode}_cpu.prof"
    curl -s "http://localhost:8282/debug/pprof/profile?seconds=15" > "$profile_file" &
    local profile_pid=$!
    
    # Run policy evaluations during profiling
    echo "Running policy evaluations during profiling..."
    for ((i=1; i<=500; i++)); do
        curl -s -X POST "$OPA_SERVER_URL/v1/data/$endpoint" \
            -H "Content-Type: application/json" \
            -d "$input_data" >/dev/null 2>&1 || true
    done
    
    # Wait for profiling to complete
    wait $profile_pid
    
    if [ -f "$profile_file" ] && [ -s "$profile_file" ]; then
        echo "Profile saved: $profile_file ($(du -h "$profile_file" | cut -f1))"
    else
        echo "WARNING: Profile collection failed"
    fi
    echo ""
}

# Function to analyze optimization results
analyze_optimization_results() {
    echo "=== OPTIMIZATION ANALYSIS ==="
    echo ""
    
    local results_file="$RESULTS_DIR/optimization_results.csv"
    
    if [ ! -f "$results_file" ]; then
        echo "ERROR: Results file not found"
        return 1
    fi
    
    echo "Performance Comparison with Percentiles (Original vs Optimized):"
    echo "================================================================"
    printf "%-25s %12s %12s %12s %12s %12s\\n" "Policy" "Version" "Requests/Sec" "Avg Latency" "P95 Latency" "P99 Latency"
    printf "%-25s %12s %12s %12s %12s %12s\\n" "------" "-------" "------------" "-----------" "-----------" "-----------"
    
    # Show original results first
    while IFS=',' read -r policy version iterations duration rps avg_latency p50 p95 p99 min max; do
        if [ "$policy" != "Policy" ] && [ "$version" = "original" ]; then
            printf "%-25s %12s %12s %9.2f ms %9.2f ms %9.2f ms\\n" "$policy" "$version" "$rps" "$avg_latency" "$p95" "$p99"
        fi
    done < "$results_file"
    
    echo ""
    
    # Show optimized results
    while IFS=',' read -r policy version iterations duration rps avg_latency p50 p95 p99 min max; do
        if [ "$policy" != "Policy" ] && [ "$version" = "optimized" ]; then
            printf "%-25s %12s %12s %9.2f ms %9.2f ms %9.2f ms\\n" "$policy" "$version" "$rps" "$avg_latency" "$p95" "$p99"
        fi
    done < "$results_file"
    
    echo ""
    echo "=== DETAILED IMPROVEMENT ANALYSIS ==="
    echo ""
    
    # Analyze each policy
    for policy_name in "Simple RBAC" "API Authorization" "Financial Risk Assessment"; do
        # Get original performance
        original_rps=$(awk -F',' -v p="$policy_name" '$1==p && $2=="original" {print $5}' "$results_file")
        original_latency=$(awk -F',' -v p="$policy_name" '$1==p && $2=="original" {print $6}' "$results_file")
        original_p95=$(awk -F',' -v p="$policy_name" '$1==p && $2=="original" {print $8}' "$results_file")
        
        # Get optimized performance  
        optimized_rps=$(awk -F',' -v p="$policy_name" '$1==p && $2=="optimized" {print $5}' "$results_file")
        optimized_latency=$(awk -F',' -v p="$policy_name" '$1==p && $2=="optimized" {print $6}' "$results_file")
        optimized_p95=$(awk -F',' -v p="$policy_name" '$1==p && $2=="optimized" {print $8}' "$results_file")
        
        if [ -n "$original_rps" ] && [ -n "$optimized_rps" ]; then
            # Calculate improvements
            rps_improvement=$(echo "scale=1; (($optimized_rps - $original_rps) / $original_rps) * 100" | bc -l)
            latency_improvement=$(echo "scale=1; (($original_latency - $optimized_latency) / $original_latency) * 100" | bc -l)
            p95_improvement=$(echo "scale=1; (($original_p95 - $optimized_p95) / $original_p95) * 100" | bc -l)
            
            echo "--- $policy_name Optimization Impact ---"
            echo "  Throughput: $original_rps → $optimized_rps req/s (${rps_improvement}% improvement)"
            echo "  Avg Latency: ${original_latency}ms → ${optimized_latency}ms (${latency_improvement}% improvement)"
            echo "  P95 Latency: ${original_p95}ms → ${optimized_p95}ms (${p95_improvement}% improvement)"
            echo ""
        fi
    done
}

# Function to generate optimization summary
generate_optimization_summary() {
    echo "=== OPTIMIZATION SUMMARY ==="
    echo ""
    
    local summary_file="$RESULTS_DIR/optimization_summary.txt"
    
    cat > "$summary_file" << EOF
Profile-Guided Optimization Results
===================================
Date: $(date)
Iterations per policy: $ITERATIONS
OPA Version: $(/usr/local/bin/opa version | head -1)

Optimizations Applied:
=====================

Simple RBAC Policy:
- Early success for admin users (immediate approval)
- Reordered role checks based on usage patterns  
- Combined rules to reduce evaluation overhead
- Optimized rule structure for common cases

API Authorization Policy:
- Early rejection for common failure cases
- Cached token validation results
- Reordered permission checks (most common first)
- Streamlined rate limiting logic
- Optimized resource classification

Financial Risk Assessment Policy:
- Early rejection rules (fail fast on common criteria)
- Cached expensive calculations (credit scores, ratios)
- Lookup tables instead of conditional chains
- Simplified risk calculation algorithm
- Removed expensive market condition analysis

Key Optimization Principles:
===========================
1. Fail Fast: Early rejection/approval for common cases
2. Cache Expensive Operations: Avoid recalculating complex values
3. Reorder Rules: Most likely matches first
4. Lookup Tables: Replace conditional chains with O(1) lookups
5. Simplify Logic: Remove unnecessary complexity where possible

Profile Data:
=============
CPU profiles collected for both original and optimized versions
Profile files stored in: $PROFILE_DIR
EOF

    # Add performance results to summary
    echo "" >> "$summary_file"
    echo "Performance Results:" >> "$summary_file"
    echo "===================" >> "$summary_file"
    cat "$RESULTS_DIR/optimization_results.csv" >> "$summary_file"
    
    echo "Optimization summary saved: $summary_file"
}

# Check if bc is available
if ! command -v bc &> /dev/null; then
    echo "Installing bc calculator..."
    apt-get update && apt-get install -y bc
fi

echo "=== OPA PROFILE-GUIDED OPTIMIZATION BENCHMARK ===" 
echo ""

# Check OPA version and WASM support
echo "OPA Version Information:"
/usr/local/bin/opa version
echo ""

# Trap to ensure server cleanup
trap stop_opa_server EXIT

# Initialize results file
echo "Policy,Version,Iterations,Duration(s),Requests/Sec,Avg_Latency(ms),P50(ms),P95(ms),P99(ms),Min(ms),Max(ms)" > "$RESULTS_DIR/optimization_results.csv"

echo "=== TESTING ORIGINAL POLICIES ==="
echo ""

# Start OPA server with original policies
start_opa_server "policies" "original"

# Test server connectivity
echo "Testing server connectivity..."
if ! curl -s "$OPA_SERVER_URL/health" >/dev/null; then
    echo "ERROR: Cannot connect to OPA server"
    exit 1
fi
echo "Server connectivity OK"
echo ""

# Benchmark original policies
benchmark_policy "Simple RBAC" "rbac/allow" "$RBAC_INPUT" "original"
collect_optimization_profile "Simple RBAC" "rbac/allow" "$RBAC_INPUT" "original"

benchmark_policy "API Authorization" "api/authz/allow" "$API_INPUT" "original"
collect_optimization_profile "API Authorization" "api/authz/allow" "$API_INPUT" "original"

benchmark_policy "Financial Risk Assessment" "finance/risk/approve_loan" "$FINANCIAL_INPUT" "original"
collect_optimization_profile "Financial Risk Assessment" "finance/risk/approve_loan" "$FINANCIAL_INPUT" "original"

# Stop original server
stop_opa_server

echo ""
echo "=== TESTING OPTIMIZED POLICIES ==="
echo ""

# Start OPA server with optimized policies
start_opa_server "policies-optimized" "optimized"

# Test server connectivity
echo "Testing server connectivity..."
if ! curl -s "$OPA_SERVER_URL/health" >/dev/null; then
    echo "ERROR: Cannot connect to OPA server"
    exit 1
fi
echo "Server connectivity OK"
echo ""

# Benchmark optimized policies
benchmark_policy "Simple RBAC" "rbac/allow" "$RBAC_INPUT" "optimized"
collect_optimization_profile "Simple RBAC" "rbac/allow" "$RBAC_INPUT" "optimized"

benchmark_policy "API Authorization" "api/authz/allow" "$API_INPUT" "optimized"
collect_optimization_profile "API Authorization" "api/authz/allow" "$API_INPUT" "optimized"

benchmark_policy "Financial Risk Assessment" "finance/risk/approve_loan" "$FINANCIAL_INPUT" "optimized"
collect_optimization_profile "Financial Risk Assessment" "finance/risk/approve_loan" "$FINANCIAL_INPUT" "optimized"

# Stop optimized server
stop_opa_server
trap - EXIT

echo ""
echo "=== OPTIMIZATION ANALYSIS ==="
echo ""

# Analyze results
analyze_optimization_results

# Generate summary
generate_optimization_summary

echo ""
echo "=== BENCHMARK COMPLETE ==="
echo "Mode: Profile-Guided Optimization Analysis"
echo "Results Directory: $RESULTS_DIR"
echo "Profile Directory: $PROFILE_DIR"
echo "Container: $(hostname)"
echo "OPA Version: $(/usr/local/bin/opa version)"
echo ""
echo "Key Insight: Profile-guided optimizations can provide measurable performance"
echo "improvements by applying targeted optimizations based on actual execution patterns."
echo "Early rejection, caching, and rule reordering are particularly effective techniques."
echo ""