#!/bin/bash

# OPA Profiling Benchmark Script
# Profile-guided optimization analysis using Go pprof
# Usage: ./opa-profiling-benchmark.sh <iterations>

set -e

ITERATIONS=${1:-1000}
TEMP_DIR="/tmp/opa-benchmark"
OPA_SERVER_URL="http://localhost:8181"
PROFILE_DIR="/app/profiles"
ANALYSIS_DIR="/app/analysis"

echo "OPA Profiling Benchmark"
echo "======================="
echo "Iterations per policy: $ITERATIONS"
echo "Server URL: $OPA_SERVER_URL"
echo "Profile Directory: $PROFILE_DIR"
echo "Analysis Directory: $ANALYSIS_DIR"
echo "Timestamp: $(date)"
echo ""

# Create directories
mkdir -p "$TEMP_DIR" "$PROFILE_DIR" "$ANALYSIS_DIR"

# Test data for each policy
RBAC_INPUT='{"input": {"user": {"id": "user_001", "role": "admin"}, "action": "delete", "resource": {"owner": "user_002"}}}'
API_INPUT='{"input": {"user": {"id": "user_001", "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyXzAwMSIsImlhdCI6MTcyMzUzNjAwMCwiZXhwIjo5OTk5OTk5OTk5fQ.sig", "permissions": ["users:read"], "tier": "premium", "department": "engineering"}, "method": "GET", "path": "/api/users", "client_ip": "192.168.1.1"}}'
FINANCIAL_INPUT='{"input": {"loan_application": {"amount": 500000, "monthly_payment": 3200, "collateral_value": 750000, "collateral_type": "residential_property", "applicant": {"id": "applicant_001", "country": "US", "monthly_income": 12000, "total_monthly_debt": 4500, "credit_scores": {"experian": 780, "equifax": 775, "transunion": 785}, "employment": {"industry": "technology", "title": "Senior Engineer", "tenure_months": 48, "verified": true, "income_verified": true}, "payment_history": [{"days_late": 0}, {"days_late": 0}, {"days_late": 0}]}}}}' 

# Function to start OPA server with profiling enabled
start_opa_server_with_profiling() {
    echo "Starting OPA server with profiling enabled..."
    
    # Start OPA server with profiling endpoints enabled
    /usr/local/bin/opa run --server --addr 0.0.0.0:8181 \
        --diagnostic-addr 0.0.0.0:8282 \
        policies/ data/benchmark_data.json >/dev/null 2>&1 &
    
    OPA_PID=$!
    echo "OPA server started with PID: $OPA_PID (profiling enabled on :8282)"
    
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

# Function to collect CPU profile during policy execution
collect_cpu_profile() {
    local policy_name="$1"
    local endpoint="$2"
    local input_data="$3"
    local profile_duration="30s"
    
    echo "Collecting CPU profile for: $policy_name"
    echo "Profile duration: $profile_duration"
    
    # Start CPU profiling in background
    local profile_file="$PROFILE_DIR/${policy_name// /_}_cpu.prof"
    curl -s "http://localhost:8282/debug/pprof/profile?seconds=30" > "$profile_file" &
    local profile_pid=$!
    
    # Run policy evaluations during profiling
    echo "Running $ITERATIONS policy evaluations during profiling..."
    for ((i=1; i<=ITERATIONS; i++)); do
        curl -s -X POST "$OPA_SERVER_URL/v1/data/$endpoint" \
            -H "Content-Type: application/json" \
            -d "$input_data" >/dev/null 2>&1 || true
        
        if [ $((i % 100)) -eq 0 ]; then
            echo -n "."
        fi
    done
    echo ""
    
    # Wait for profiling to complete
    echo "Waiting for profiling to complete..."
    wait $profile_pid
    
    if [ -f "$profile_file" ] && [ -s "$profile_file" ]; then
        echo "CPU profile saved: $profile_file"
        local file_size=$(du -h "$profile_file" | cut -f1)
        echo "Profile size: $file_size"
    else
        echo "WARNING: CPU profile collection failed or empty"
    fi
    echo ""
}

# Function to collect memory profile
collect_memory_profile() {
    local policy_name="$1"
    local endpoint="$2"
    local input_data="$3"
    
    echo "Collecting memory profile for: $policy_name"
    
    # Warm up with some requests
    for i in {1..50}; do
        curl -s -X POST "$OPA_SERVER_URL/v1/data/$endpoint" \
            -H "Content-Type: application/json" \
            -d "$input_data" >/dev/null 2>&1 || true
    done
    
    # Collect heap profile
    local heap_profile_file="$PROFILE_DIR/${policy_name// /_}_heap.prof"
    curl -s "http://localhost:8282/debug/pprof/heap" > "$heap_profile_file"
    
    # Collect allocs profile
    local allocs_profile_file="$PROFILE_DIR/${policy_name// /_}_allocs.prof"
    curl -s "http://localhost:8282/debug/pprof/allocs" > "$allocs_profile_file"
    
    if [ -f "$heap_profile_file" ] && [ -s "$heap_profile_file" ]; then
        echo "Heap profile saved: $heap_profile_file"
        local heap_size=$(du -h "$heap_profile_file" | cut -f1)
        echo "Heap profile size: $heap_size"
    else
        echo "WARNING: Heap profile collection failed"
    fi
    
    if [ -f "$allocs_profile_file" ] && [ -s "$allocs_profile_file" ]; then
        echo "Allocs profile saved: $allocs_profile_file"
        local allocs_size=$(du -h "$allocs_profile_file" | cut -f1)
        echo "Allocs profile size: $allocs_size"
    else
        echo "WARNING: Allocs profile collection failed"
    fi
    echo ""
}

# Function to analyze profiles and generate reports
analyze_profiles() {
    local policy_name="$1"
    local safe_name="${policy_name// /_}"
    
    echo "Analyzing profiles for: $policy_name"
    echo "=================================="
    
    local cpu_profile="$PROFILE_DIR/${safe_name}_cpu.prof"
    local heap_profile="$PROFILE_DIR/${safe_name}_heap.prof"
    local allocs_profile="$PROFILE_DIR/${safe_name}_allocs.prof"
    
    # Analyze CPU profile
    if [ -f "$cpu_profile" ] && [ -s "$cpu_profile" ]; then
        echo "CPU Profile Analysis:"
        echo "--------------------"
        
        # Generate text report
        go tool pprof -text -cum "$cpu_profile" > "$ANALYSIS_DIR/${safe_name}_cpu_analysis.txt" 2>/dev/null || {
            echo "CPU profile analysis failed - using alternative method"
            echo "CPU profile file exists but analysis tools unavailable" > "$ANALYSIS_DIR/${safe_name}_cpu_analysis.txt"
        }
        
        if [ -f "$ANALYSIS_DIR/${safe_name}_cpu_analysis.txt" ]; then
            echo "Top CPU consumers:"
            head -20 "$ANALYSIS_DIR/${safe_name}_cpu_analysis.txt" | grep -v "^$" | head -10 || echo "No CPU data available"
        fi
        echo ""
    else
        echo "No CPU profile available for analysis"
    fi
    
    # Analyze heap profile
    if [ -f "$heap_profile" ] && [ -s "$heap_profile" ]; then
        echo "Heap Profile Analysis:"
        echo "---------------------"
        
        # Generate text report
        go tool pprof -text -cum "$heap_profile" > "$ANALYSIS_DIR/${safe_name}_heap_analysis.txt" 2>/dev/null || {
            echo "Heap profile analysis failed - using alternative method"
            echo "Heap profile file exists but analysis tools unavailable" > "$ANALYSIS_DIR/${safe_name}_heap_analysis.txt"
        }
        
        if [ -f "$ANALYSIS_DIR/${safe_name}_heap_analysis.txt" ]; then
            echo "Top memory allocators:"
            head -20 "$ANALYSIS_DIR/${safe_name}_heap_analysis.txt" | grep -v "^$" | head -10 || echo "No heap data available"
        fi
        echo ""
    else
        echo "No heap profile available for analysis"
    fi
    
    # Analyze allocs profile
    if [ -f "$allocs_profile" ] && [ -s "$allocs_profile" ]; then
        echo "Allocation Profile Analysis:"
        echo "---------------------------"
        
        # Generate text report
        go tool pprof -text -cum "$allocs_profile" > "$ANALYSIS_DIR/${safe_name}_allocs_analysis.txt" 2>/dev/null || {
            echo "Allocs profile analysis failed - using alternative method"
            echo "Allocs profile file exists but analysis tools unavailable" > "$ANALYSIS_DIR/${safe_name}_allocs_analysis.txt"
        }
        
        if [ -f "$ANALYSIS_DIR/${safe_name}_allocs_analysis.txt" ]; then
            echo "Top allocation sites:"
            head -20 "$ANALYSIS_DIR/${safe_name}_allocs_analysis.txt" | grep -v "^$" | head -10 || echo "No allocs data available"
        fi
        echo ""
    else
        echo "No allocs profile available for analysis"
    fi
}

# Function to generate summary report
generate_summary_report() {
    echo "Generating profiling summary report..."
    
    local summary_file="$ANALYSIS_DIR/profiling_summary.txt"
    
    cat > "$summary_file" << EOF
OPA Profiling Benchmark Summary
===============================
Date: $(date)
Iterations per policy: $ITERATIONS
OPA Version: $(/usr/local/bin/opa version | head -1)
Profiling Duration: 30 seconds per policy

Profile Files Generated:
EOF
    
    echo "" >> "$summary_file"
    echo "Profile Files:" >> "$summary_file"
    ls -la "$PROFILE_DIR"/*.prof 2>/dev/null >> "$summary_file" || echo "No profile files found" >> "$summary_file"
    
    echo "" >> "$summary_file"
    echo "Analysis Files:" >> "$summary_file"
    ls -la "$ANALYSIS_DIR"/*.txt 2>/dev/null >> "$summary_file" || echo "No analysis files found" >> "$summary_file"
    
    echo "" >> "$summary_file"
    echo "Policy Complexity Comparison:" >> "$summary_file"
    echo "=============================" >> "$summary_file"
    echo "1. Simple RBAC (28 lines): Basic role-based access control" >> "$summary_file"
    echo "2. API Authorization (130 lines): Moderate complexity with rate limiting" >> "$summary_file"
    echo "3. Financial Risk Assessment (455+ lines): Complex calculations and data lookups" >> "$summary_file"
    
    echo "" >> "$summary_file"
    echo "Key Profiling Insights:" >> "$summary_file"
    echo "======================" >> "$summary_file"
    echo "- Profile data can identify performance bottlenecks in policy evaluation" >> "$summary_file"
    echo "- Memory allocation patterns show where garbage collection pressure occurs" >> "$summary_file"
    echo "- CPU profiles reveal which policy rules consume most computational resources" >> "$summary_file"
    echo "- Complex policies with multiple calculations show different performance characteristics" >> "$summary_file"
    
    echo "Summary report saved: $summary_file"
}

echo "=== OPA PROFILING BENCHMARK ===" 
echo ""

# Check if Go profiling tools are available
if ! command -v go &> /dev/null; then
    echo "WARNING: Go tools not available, profile analysis will be limited"
fi

# Trap to ensure server cleanup
trap stop_opa_server EXIT

# Start OPA server with profiling enabled
start_opa_server_with_profiling

# Test server connectivity
echo "Testing server connectivity..."
if ! curl -s "$OPA_SERVER_URL/health" >/dev/null; then
    echo "ERROR: Cannot connect to OPA server"
    exit 1
fi

# Test profiling endpoint
echo "Testing profiling endpoint..."
if curl -s "http://localhost:8282/debug/pprof/" | grep -q "Profile"; then
    echo "Profiling endpoint is available"
else
    echo "WARNING: Profiling endpoint may not be available"
fi
echo ""

echo "=== PROFILING POLICY EXECUTION ==="
echo ""

# Profile Simple RBAC
echo "1/3: Profiling Simple RBAC Policy"
echo "=================================="
collect_cpu_profile "Simple RBAC" "rbac/allow" "$RBAC_INPUT"
collect_memory_profile "Simple RBAC" "rbac/allow" "$RBAC_INPUT"
analyze_profiles "Simple RBAC"

# Profile API Authorization
echo "2/3: Profiling API Authorization Policy"
echo "======================================="
collect_cpu_profile "API Authorization" "api/authz/allow" "$API_INPUT"
collect_memory_profile "API Authorization" "api/authz/allow" "$API_INPUT"
analyze_profiles "API Authorization"

# Profile Financial Risk Assessment
echo "3/3: Profiling Financial Risk Assessment Policy"
echo "==============================================="
collect_cpu_profile "Financial Risk Assessment" "finance/risk/approve_loan" "$FINANCIAL_INPUT"
collect_memory_profile "Financial Risk Assessment" "finance/risk/approve_loan" "$FINANCIAL_INPUT"
analyze_profiles "Financial Risk Assessment"

# Stop server
stop_opa_server
trap - EXIT

echo ""
echo "=== PROFILING ANALYSIS COMPLETE ===" 
echo ""

# Generate summary report
generate_summary_report

echo "=== BENCHMARK COMPLETE ==="
echo "Mode: OPA Profile-Guided Optimization Analysis"
echo "Profile Directory: $PROFILE_DIR"
echo "Analysis Directory: $ANALYSIS_DIR"
echo "Container: $(hostname)"
echo "OPA Version: $(/usr/local/bin/opa version)"
echo ""
echo "Key Insight: Profiling data enables identification of performance bottlenecks"
echo "in policy evaluation, helping optimize both policy design and OPA configuration."
echo "Complex policies show different CPU and memory patterns that can guide optimization efforts."
echo ""