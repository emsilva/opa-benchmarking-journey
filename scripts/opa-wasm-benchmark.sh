#!/bin/bash

# OPA WebAssembly (WASM) Policy Benchmarking Script
# Usage: ./opa-wasm-benchmark.sh <iterations>

set -e

ITERATIONS=${1:-100}
TEMP_DIR="/tmp/opa-benchmark"
OPA_SERVER_URL="http://localhost:8181"

echo "OPA WebAssembly (WASM) Policy Benchmarking"
echo "=========================================="
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

# Function to start OPA server (Rego mode)
start_opa_server_rego() {
    echo "Starting OPA server (Rego mode)..."
    
    # Load policies without verbose logging
    /usr/local/bin/opa run --server --addr 0.0.0.0:8181 \
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

# Function to start OPA server (WASM mode) 
start_opa_server_wasm() {
    local bundle_file="$1"
    local policy_name="$2"
    
    echo "Starting OPA server (WASM mode) for $policy_name..."
    
    # Load WASM bundle without verbose logging
    /usr/local/bin/opa run --server --addr 0.0.0.0:8181 \
        "wasm/$bundle_file" >/dev/null 2>&1 &
    
    OPA_PID=$!
    echo "OPA server started with PID: $OPA_PID (WASM bundle: $bundle_file)"
    
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
    local mode="$4"  # "rego" or "wasm"
    
    echo "Benchmarking: $policy_name ($mode mode)"
    echo "---------------------------------------"
    
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
    echo "$policy_name,$mode,$ITERATIONS,$duration,$policies_per_second,$avg_latency_ms" >> "$TEMP_DIR/results.csv"
}

# Check if bc is available
if ! command -v bc &> /dev/null; then
    echo "Installing bc calculator..."
    apt-get update && apt-get install -y bc
fi

echo "=== OPA WEBASSEMBLY BENCHMARK ===" 
echo ""

# Check if OPA supports WASM
echo "Checking OPA WebAssembly support..."
wasm_support=$(/usr/local/bin/opa version | grep "WebAssembly:" | awk '{print $2}')
echo "OPA Version: $(/usr/local/bin/opa version | head -1)"
echo "WebAssembly Support: $wasm_support"
echo ""

if [ "$wasm_support" = "unavailable" ]; then
    echo "⚠️  WARNING: This OPA build does not support WebAssembly!"
    echo "WASM benchmarks will be skipped and marked as UNSUPPORTED."
    echo "To test WASM performance, use an OPA build with WASM support enabled."
    echo ""
    
    # Create results showing WASM is unsupported
    echo "Policy,Mode,Iterations,Duration(s),Policies/Second,Avg_Latency(ms)" > "$TEMP_DIR/results.csv"
    WASM_SUPPORTED=false
else
    echo "✅ OPA supports WebAssembly - proceeding with WASM benchmarks."
    echo ""
    WASM_SUPPORTED=true
fi

# Verify WASM compilation results
echo "Verifying WASM compilation..."
ls -la wasm/
echo ""

# Trap to ensure server cleanup
trap stop_opa_server EXIT

# Initialize results file (unless already created due to WASM unavailable)
if [ ! -f "$TEMP_DIR/results.csv" ]; then
    echo "Policy,Mode,Iterations,Duration(s),Policies/Second,Avg_Latency(ms)" > "$TEMP_DIR/results.csv"
fi

echo "=== BASELINE (REGO) TESTS ==="
echo ""

# Start OPA server in Rego mode
start_opa_server_rego

# Test server connectivity
echo "Testing server connectivity..."
if ! curl -s "$OPA_SERVER_URL/health" >/dev/null; then
    echo "ERROR: Cannot connect to OPA server"
    exit 1
fi
echo "Server connectivity OK"
echo ""

# Run Rego benchmarks
benchmark_policy "Simple RBAC" "rbac/allow" "$RBAC_INPUT" "rego"
benchmark_policy "API Authorization" "api/authz/allow" "$API_INPUT" "rego"
benchmark_policy "Financial Risk Assessment" "finance/risk/approve_loan" "$FINANCIAL_INPUT" "rego"

# Stop Rego server
stop_opa_server

echo ""
echo "=== WEBASSEMBLY (WASM) TESTS ==="
echo ""

# Skip WASM tests if not supported
if [ "$WASM_SUPPORTED" = "false" ]; then
    echo "Skipping WASM tests - WebAssembly not supported by this OPA build."
    echo "Simple RBAC,wasm,$ITERATIONS,UNSUPPORTED,UNSUPPORTED,UNSUPPORTED" >> "$TEMP_DIR/results.csv"
    echo "API Authorization,wasm,$ITERATIONS,UNSUPPORTED,UNSUPPORTED,UNSUPPORTED" >> "$TEMP_DIR/results.csv"
    echo "Financial Risk Assessment,wasm,$ITERATIONS,UNSUPPORTED,UNSUPPORTED,UNSUPPORTED" >> "$TEMP_DIR/results.csv"
else
    # Test Simple RBAC with WASM
    if [ -f "wasm/rbac-bundle.tar.gz" ]; then
    start_opa_server_wasm "rbac-bundle.tar.gz" "Simple RBAC"
    
    # Test connectivity and verify WASM endpoint works
    if curl -s "$OPA_SERVER_URL/health" >/dev/null; then
        benchmark_policy "Simple RBAC" "rbac/allow" "$RBAC_INPUT" "wasm"
    else
        echo "ERROR: Could not connect to RBAC WASM server"
        echo "Simple RBAC,wasm,$ITERATIONS,ERROR,ERROR,ERROR" >> "$TEMP_DIR/results.csv"
    fi
    
    stop_opa_server
    echo ""
else
    echo "WARNING: rbac-bundle.tar.gz not found, skipping RBAC WASM benchmark"
    echo "Simple RBAC,wasm,$ITERATIONS,MISSING,MISSING,MISSING" >> "$TEMP_DIR/results.csv"
fi

# Test API Authorization with WASM  
if [ -f "wasm/api-bundle.tar.gz" ]; then
    start_opa_server_wasm "api-bundle.tar.gz" "API Authorization"
    
    if curl -s "$OPA_SERVER_URL/health" >/dev/null; then
        benchmark_policy "API Authorization" "api/authz/allow" "$API_INPUT" "wasm"
    else
        echo "ERROR: Could not connect to API WASM server"
        echo "API Authorization,wasm,$ITERATIONS,ERROR,ERROR,ERROR" >> "$TEMP_DIR/results.csv"
    fi
    
    stop_opa_server
    echo ""
else
    echo "WARNING: api-bundle.tar.gz not found, skipping API WASM benchmark"
    echo "API Authorization,wasm,$ITERATIONS,MISSING,MISSING,MISSING" >> "$TEMP_DIR/results.csv"
fi

# Test Financial Risk with WASM
if [ -f "wasm/financial-bundle.tar.gz" ]; then
    start_opa_server_wasm "financial-bundle.tar.gz" "Financial Risk Assessment"
    
    if curl -s "$OPA_SERVER_URL/health" >/dev/null; then
        benchmark_policy "Financial Risk Assessment" "finance/risk/approve_loan" "$FINANCIAL_INPUT" "wasm"
    else
        echo "ERROR: Could not connect to Financial WASM server"
        echo "Financial Risk Assessment,wasm,$ITERATIONS,ERROR,ERROR,ERROR" >> "$TEMP_DIR/results.csv"
    fi
    
    stop_opa_server
    echo ""
else
    echo "WARNING: financial-bundle.tar.gz not found, skipping Financial WASM benchmark"
    echo "Financial Risk Assessment,wasm,$ITERATIONS,MISSING,MISSING,MISSING" >> "$TEMP_DIR/results.csv"
fi
fi  # End WASM_SUPPORTED check

# Stop any remaining server
stop_opa_server
trap - EXIT

echo ""
echo "=== WEBASSEMBLY BENCHMARK ANALYSIS ===" 
echo ""

# Print comparison table
printf "%-25s %12s %15s %15s %15s\\n" "Policy" "Mode" "Requests/Sec" "Latency(ms)" "Improvement"
printf "%-25s %12s %15s %15s %15s\\n" "------" "----" "------------" "-----------" "-----------"

# Show Rego results first
grep ",rego," "$TEMP_DIR/results.csv" | while IFS=',' read -r policy mode iterations duration rps latency; do
    printf "%-25s %12s %15s %15s %15s\\n" "$policy" "$mode" "$rps" "$latency" "baseline"
done

echo ""

# Show WASM results with comparison
grep ",wasm," "$TEMP_DIR/results.csv" | while IFS=',' read -r policy mode iterations duration rps latency; do
    # Get corresponding Rego result
    rego_rps=$(awk -F',' -v p="$policy" '$1==p && $2=="rego" {print $5}' "$TEMP_DIR/results.csv")
    
    if [ -n "$rego_rps" ] && [ "$rps" != "ERROR" ] && [ "$rps" != "MISSING" ]; then
        improvement=$(echo "scale=2; ($rps - $rego_rps) / $rego_rps * 100" | bc -l)
        printf "%-25s %12s %15s %15s %14s%%\\n" "$policy" "$mode" "$rps" "$latency" "$improvement"
    else
        printf "%-25s %12s %15s %15s %15s\\n" "$policy" "$mode" "$rps" "$latency" "N/A"
    fi
done

echo ""
echo "=== REGO vs WASM PERFORMANCE ANALYSIS ==="
echo ""

# Calculate performance ratios for each policy
for policy_short in "Simple RBAC" "API Authorization" "Financial Risk Assessment"; do
    echo "--- $policy_short Performance ---"
    
    # Get Rego performance
    rego_rps=$(awk -F',' -v p="$policy_short" '$1==p && $2=="rego" {print $5}' "$TEMP_DIR/results.csv")
    rego_latency=$(awk -F',' -v p="$policy_short" '$1==p && $2=="rego" {print $6}' "$TEMP_DIR/results.csv")
    
    # Get WASM performance  
    wasm_rps=$(awk -F',' -v p="$policy_short" '$1==p && $2=="wasm" {print $5}' "$TEMP_DIR/results.csv")
    wasm_latency=$(awk -F',' -v p="$policy_short" '$1==p && $2=="wasm" {print $6}' "$TEMP_DIR/results.csv")
    
    if [ -n "$rego_rps" ] && [ -n "$wasm_rps" ] && [ "$wasm_rps" != "ERROR" ] && [ "$wasm_rps" != "MISSING" ] && [ "$wasm_rps" != "UNSUPPORTED" ]; then
        speedup=$(echo "scale=2; $wasm_rps / $rego_rps" | bc -l)
        latency_improvement=$(echo "scale=2; ($rego_latency - $wasm_latency) / $rego_latency * 100" | bc -l)
        
        echo "  Rego: $rego_rps req/s, ${rego_latency}ms latency"
        echo "  WASM: $wasm_rps req/s, ${wasm_latency}ms latency"
        echo "  WASM Performance: ${speedup}x faster, ${latency_improvement}% lower latency"
    elif [ "$wasm_rps" = "UNSUPPORTED" ]; then
        echo "  Rego: $rego_rps req/s, ${rego_latency}ms latency"
        echo "  WASM: UNSUPPORTED - This OPA build lacks WebAssembly support"
    elif [ "$wasm_rps" = "ERROR" ]; then
        echo "  Rego: $rego_rps req/s, ${rego_latency}ms latency"
        echo "  WASM: COMPILATION OR RUNTIME ERROR"
    elif [ "$wasm_rps" = "MISSING" ]; then
        echo "  Rego: $rego_rps req/s, ${rego_latency}ms latency"
        echo "  WASM: COMPILATION FAILED - WASM FILE NOT CREATED"
    else
        echo "  Unable to compare - missing data"
    fi
    echo ""
done

echo "=== BENCHMARK COMPLETE ===" 
echo "Mode: OPA Rego vs WebAssembly Performance Comparison"
echo "Results: $TEMP_DIR/results.csv"
echo "Container: $(hostname)"
echo "OPA Version: $(/usr/local/bin/opa version)"
echo ""
if [ "$WASM_SUPPORTED" = "true" ]; then
    echo "Key Insight: WebAssembly compilation can provide significant performance"
    echo "improvements for complex policies, with trade-offs in compilation time and flexibility."
else
    echo "Key Insight: This OPA build does not support WebAssembly."
    echo "To enable WASM benchmarking, use an OPA build with WebAssembly support."
    echo "WASM can provide 2-10x performance improvements for complex policies."
fi
echo ""