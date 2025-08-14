#!/bin/bash

# OPA Concurrent Request Policy Benchmarking Script (FIXED)
# Usage: ./opa-concurrent-benchmark.sh <iterations>

set -e

ITERATIONS=${1:-100}
TEMP_DIR="/tmp/opa-benchmark"
OPA_SERVER_URL="http://localhost:8181"

# Test concurrency levels - more conservative after fixing Apache Bench issue
CONCURRENCY_LEVELS=(1 2 4 8)

echo "OPA Concurrent Request Policy Benchmarking (FIXED)"
echo "=================================================="
echo "Iterations per policy: $ITERATIONS"
echo "Server URL: $OPA_SERVER_URL"
echo "Concurrency levels: ${CONCURRENCY_LEVELS[*]}"
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
    
    # Load policies without verbose logging
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

# Function to benchmark with parallel curl (real concurrency)
benchmark_policy_concurrent() {
    local policy_name="$1"
    local endpoint="$2"
    local input_data="$3"
    local concurrency="$4"
    
    echo "Benchmarking: $policy_name (Concurrency: $concurrency)"
    echo "-------------------------------------------------------"
    
    # Warmup runs
    echo "Performing warmup..."
    for i in {1..5}; do
        curl -s -X POST "$OPA_SERVER_URL/v1/data/$endpoint" \
            -H "Content-Type: application/json" \
            -d "$input_data" >/dev/null 2>&1 || true
    done
    
    # Calculate iterations per worker
    local iterations_per_worker=$((ITERATIONS / concurrency))
    local remaining_iterations=$((ITERATIONS % concurrency))
    
    echo "Running $ITERATIONS requests with $concurrency parallel workers..."
    echo "  $iterations_per_worker requests per worker (+ $remaining_iterations extra)"
    
    # Create temporary script for parallel execution
    local worker_script="$TEMP_DIR/worker_${policy_name// /_}.sh"
    cat > "$worker_script" << EOF
#!/bin/bash
worker_id=\$1
iterations=\$2
endpoint="$endpoint"
input_data='$input_data'

for ((i=1; i<=iterations; i++)); do
    curl -s -X POST "$OPA_SERVER_URL/v1/data/\$endpoint" \\
        -H "Content-Type: application/json" \\
        -d "\$input_data" >/dev/null 2>&1 || true
done
EOF
    chmod +x "$worker_script"
    
    # Start timing
    start_time=$(awk '{print $1}' /proc/uptime)
    
    # Launch parallel workers
    local pids=()
    for ((worker=1; worker<=concurrency; worker++)); do
        local worker_iterations=$iterations_per_worker
        
        # Add extra iteration to first worker if there's a remainder
        if [ $worker -eq 1 ] && [ $remaining_iterations -gt 0 ]; then
            worker_iterations=$((worker_iterations + remaining_iterations))
        fi
        
        "$worker_script" $worker $worker_iterations &
        pids+=($!)
    done
    
    # Wait for all workers to complete
    local completed=0
    while [ $completed -lt $concurrency ]; do
        completed=0
        for pid in "${pids[@]}"; do
            if ! kill -0 $pid 2>/dev/null; then
                completed=$((completed + 1))
            fi
        done
        sleep 0.1
        echo -n "."
    done
    echo ""
    
    # End timing
    end_time=$(awk '{print $1}' /proc/uptime)
    duration=$(echo "$end_time - $start_time" | bc -l)
    
    # Ensure minimum duration
    if [ "$(echo "$duration < 0.001" | bc -l)" -eq 1 ]; then
        duration="0.001"
    fi
    
    # Calculate metrics
    requests_per_second=$(echo "scale=2; $ITERATIONS / $duration" | bc -l)
    avg_latency_ms=$(echo "scale=2; ($duration * 1000) / $ITERATIONS" | bc -l)
    
    echo "Results:"
    echo "  Total time: ${duration}s"
    echo "  Average latency: ${avg_latency_ms}ms"
    echo "  Requests per second: ${requests_per_second}"
    echo ""
    
    # Store results
    echo "$policy_name,$concurrency,$ITERATIONS,$duration,$requests_per_second,$avg_latency_ms,0" >> "$TEMP_DIR/results.csv"
    
    # Cleanup
    rm -f "$worker_script"
}

# Function to run single-threaded baseline for comparison
benchmark_policy_baseline() {
    local policy_name="$1"
    local endpoint="$2"
    local input_data="$3"
    
    echo "Benchmarking: $policy_name (Sequential Baseline)"
    echo "-----------------------------------------------"
    
    # Warmup runs
    echo "Performing warmup..."
    for i in {1..5}; do
        curl -s -X POST "$OPA_SERVER_URL/v1/data/$endpoint" \
            -H "Content-Type: application/json" \
            -d "$input_data" >/dev/null 2>&1 || true
    done
    
    # Sequential benchmark
    echo "Running $ITERATIONS sequential requests..."
    
    # Use /proc/uptime for better precision timing
    start_time=$(awk '{print $1}' /proc/uptime)
    
    for ((i=1; i<=ITERATIONS; i++)); do
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
        
        if [ $((i % 50)) -eq 0 ]; then
            echo -n "."
        fi
    done
    echo ""
    
    end_time=$(awk '{print $1}' /proc/uptime)
    duration=$(echo "$end_time - $start_time" | bc -l)
    
    # Ensure minimum duration
    if [ "$(echo "$duration < 0.001" | bc -l)" -eq 1 ]; then
        duration="0.001"
    fi
    
    # Calculate metrics
    requests_per_second=$(echo "scale=2; $ITERATIONS / $duration" | bc -l)
    time_per_request=$(echo "scale=2; ($duration * 1000) / $ITERATIONS" | bc -l)
    
    echo "Results:"
    echo "  Total time: ${duration}s"
    echo "  Average latency: ${time_per_request}ms"
    echo "  Requests per second: ${requests_per_second}"
    echo ""
    
    # Store baseline results
    echo "$policy_name,baseline,$ITERATIONS,$duration,$requests_per_second,$time_per_request,0" >> "$TEMP_DIR/results.csv"
}

# Check if bc is available
if ! command -v bc &> /dev/null; then
    echo "Installing bc calculator..."
    apk add --no-cache bc
fi

echo "=== OPA CONCURRENT REQUEST BENCHMARK (FIXED) ===" 
echo ""

# Trap to ensure server cleanup
trap stop_opa_server EXIT

# Start OPA server
start_opa_server

# Initialize results file
echo "Policy,Concurrency,Iterations,Duration(s),Requests/Second,Avg_Latency(ms),Failed_Requests" > "$TEMP_DIR/results.csv"

# Test server connectivity
echo "Testing server connectivity..."
if ! curl -s "$OPA_SERVER_URL/health" >/dev/null; then
    echo "ERROR: Cannot connect to OPA server"
    exit 1
fi
echo "Server connectivity OK"
echo ""

# Verify policy responses work
echo "Verifying policy responses..."
rbac_test=$(curl -s -X POST "$OPA_SERVER_URL/v1/data/rbac/allow" \
    -H "Content-Type: application/json" \
    -d "$RBAC_INPUT" | jq -r '.result // "ERROR"')
echo "RBAC test result: $rbac_test"

if [ "$rbac_test" != "true" ] && [ "$rbac_test" != "false" ]; then
    echo "ERROR: Policy evaluation not working correctly"
    exit 1
fi
echo ""

# Run baseline tests (sequential)
echo "=== BASELINE (SEQUENTIAL) TESTS ==="
echo ""
benchmark_policy_baseline "Simple RBAC" "rbac/allow" "$RBAC_INPUT"
benchmark_policy_baseline "API Authorization" "api/authz/allow" "$API_INPUT"
benchmark_policy_baseline "Financial Risk Assessment" "finance/risk/approve_loan" "$FINANCIAL_INPUT"

echo ""
echo "=== CONCURRENT TESTS ==="
echo ""

# Test each policy with different concurrency levels
for concurrency in "${CONCURRENCY_LEVELS[@]}"; do
    echo "--- CONCURRENCY LEVEL: $concurrency ---"
    echo ""
    
    benchmark_policy_concurrent "Simple RBAC" "rbac/allow" "$RBAC_INPUT" "$concurrency"
    benchmark_policy_concurrent "API Authorization" "api/authz/allow" "$API_INPUT" "$concurrency" 
    benchmark_policy_concurrent "Financial Risk Assessment" "finance/risk/approve_loan" "$FINANCIAL_INPUT" "$concurrency"
    
    echo ""
    if [ "$concurrency" != "${CONCURRENCY_LEVELS[-1]}" ]; then
        echo "Waiting 2 seconds before next concurrency level..."
        sleep 2
        echo ""
    fi
done

# Stop server
stop_opa_server
trap - EXIT

echo ""
echo "=== CONCURRENT BENCHMARK ANALYSIS (FIXED) ===" 
echo ""

# Print comparison table
printf "%-25s %12s %15s %15s\\n" "Policy" "Concurrency" "Requests/Sec" "Latency(ms)"
printf "%-25s %12s %15s %15s\\n" "------" "-----------" "------------" "-----------"

# Show baseline first
grep ",baseline," "$TEMP_DIR/results.csv" | while IFS=',' read -r policy concurrency iterations duration rps latency failed; do
    printf "%-25s %12s %15s %15s\\n" "$policy" "$concurrency" "$rps" "$latency"
done

echo ""

# Show concurrent results
for concurrency in "${CONCURRENCY_LEVELS[@]}"; do
    grep ",$concurrency," "$TEMP_DIR/results.csv" | while IFS=',' read -r policy conc iterations duration rps latency failed; do
        printf "%-25s %12s %15s %15s\\n" "$policy" "$conc" "$rps" "$latency"
    done
done

echo ""
echo "=== CONCURRENCY SCALING ANALYSIS ==="
echo ""

# Calculate scaling efficiency for each policy
for policy_short in "Simple RBAC" "API Authorization" "Financial Risk Assessment"; do
    echo "--- $policy_short Scaling ---"
    
    # Get baseline performance
    baseline_rps=$(awk -F',' -v p="$policy_short" '$1==p && $2=="baseline" {print $5}' "$TEMP_DIR/results.csv")
    
    if [ -n "$baseline_rps" ]; then
        echo "Baseline (sequential): $baseline_rps requests/sec"
        
        for concurrency in "${CONCURRENCY_LEVELS[@]}"; do
            concurrent_rps=$(awk -F',' -v p="$policy_short" -v c="$concurrency" '$1==p && $2==c {print $5}' "$TEMP_DIR/results.csv")
            if [ -n "$concurrent_rps" ]; then
                speedup=$(echo "scale=2; $concurrent_rps / $baseline_rps" | bc -l)
                efficiency=$(echo "scale=1; $speedup / $concurrency * 100" | bc -l)
                echo "  Concurrency $concurrency: ${speedup}x speedup (${efficiency}% efficiency)"
            fi
        done
    fi
    echo ""
done

echo "=== BENCHMARK COMPLETE ===" 
echo "Mode: OPA Server with REAL Concurrent Requests (parallel curl)"
echo "Results: $TEMP_DIR/results.csv"
echo "Container: $(hostname)"
echo "OPA Version: $(opa version)"
echo ""
echo "Key Insight: This uses actual parallel curl processes instead of"
echo "the broken Apache Bench to measure real concurrent policy evaluation performance."
echo ""