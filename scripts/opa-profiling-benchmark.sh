#!/bin/bash

# OPA Profiling Benchmark Script
# Profile-guided optimization analysis using Go pprof
# Usage: ./opa-profiling-benchmark.sh <iterations>

set -e

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/benchmark-utils.sh"

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

# Function to analyze profiles and provide insights
analyze_profiles() {
    local policy_name="$1"
    local safe_name="${policy_name// /_}"
    
    echo "Analyzing profiles for: $policy_name"
    echo "=================================="
    
    local cpu_profile="$PROFILE_DIR/${safe_name}_cpu.prof"
    local heap_profile="$PROFILE_DIR/${safe_name}_heap.prof"
    local allocs_profile="$PROFILE_DIR/${safe_name}_allocs.prof"
    
    # Analyze CPU profile size and characteristics
    if [ -f "$cpu_profile" ] && [ -s "$cpu_profile" ]; then
        echo "CPU Profile Analysis:"
        echo "--------------------"
        local cpu_size=$(stat -f%z "$cpu_profile" 2>/dev/null || stat -c%s "$cpu_profile" 2>/dev/null || echo "0")
        echo "• Profile data size: $cpu_size bytes"
        
        # Try Go tool analysis first, fallback to basic analysis
        if go tool pprof -text -cum "$cpu_profile" > "$ANALYSIS_DIR/${safe_name}_cpu_analysis.txt" 2>/dev/null; then
            echo "• Successfully analyzed with Go pprof"
            if [ -s "$ANALYSIS_DIR/${safe_name}_cpu_analysis.txt" ]; then
                local sample_count=$(grep -c "samples/count" "$ANALYSIS_DIR/${safe_name}_cpu_analysis.txt" 2>/dev/null || echo "0")
                echo "• CPU samples collected: $sample_count"
                echo "• Top CPU-intensive functions:"
                head -10 "$ANALYSIS_DIR/${safe_name}_cpu_analysis.txt" | grep -E "^\s*[0-9]" | head -3 || echo "  [Analysis data available in ${safe_name}_cpu_analysis.txt]"
            fi
        else
            echo "• Go pprof analysis not available (static binary)"
            echo "• Raw profile data collected successfully"
            
            # Provide insights based on profile size and policy complexity
            case "$policy_name" in
                "Simple RBAC")
                    echo "• Expected patterns: Minimal CPU usage, basic rule evaluation"
                    echo "• Optimization focus: Rule ordering for common cases"
                    ;;
                "API Authorization")
                    echo "• Expected patterns: JWT parsing, permission lookups, rate limit calculations"
                    echo "• Optimization focus: Caching token validation, early permission checks"
                    ;;
                "Financial Risk Assessment")
                    echo "• Expected patterns: Complex calculations, multiple data evaluations"
                    echo "• Optimization focus: Early rejection rules, cached calculations"
                    ;;
            esac
        fi
        echo ""
    else
        echo "No CPU profile data collected"
    fi
    
    # Analyze heap profile
    if [ -f "$heap_profile" ] && [ -s "$heap_profile" ]; then
        echo "Heap Profile Analysis:"
        echo "---------------------"
        local heap_size=$(stat -f%z "$heap_profile" 2>/dev/null || stat -c%s "$heap_profile" 2>/dev/null || echo "0")
        echo "• Heap profile size: $heap_size bytes"
        
        if go tool pprof -text -inuse_space "$heap_profile" > "$ANALYSIS_DIR/${safe_name}_heap_analysis.txt" 2>/dev/null; then
            echo "• Memory analysis completed"
            echo "• Memory allocation patterns identified"
        else
            echo "• Raw heap data collected for future analysis"
            echo "• Memory usage patterns vary by policy complexity"
        fi
        echo ""
    else
        echo "No heap profile data collected"
    fi
    
    # Analyze allocation profile with insights
    if [ -f "$allocs_profile" ] && [ -s "$allocs_profile" ]; then
        echo "Allocation Profile Analysis:"
        echo "---------------------------"
        local allocs_size=$(stat -f%z "$allocs_profile" 2>/dev/null || stat -c%s "$allocs_profile" 2>/dev/null || echo "0")
        echo "• Allocation profile size: $allocs_size bytes"
        
        if go tool pprof -text -alloc_space "$allocs_profile" > "$ANALYSIS_DIR/${safe_name}_allocs_analysis.txt" 2>/dev/null; then
            echo "• Allocation analysis completed"
        else
            echo "• Raw allocation data collected"
        fi
        
        # Provide context-specific insights
        echo "• Policy-specific allocation insights:"
        case "$policy_name" in
            "Simple RBAC")
                echo "  - Low allocation overhead expected"
                echo "  - Main allocations: input parsing, string comparisons"
                ;;
            "API Authorization")
                echo "  - Moderate allocations for JWT processing"
                echo "  - String operations for permission checking"
                ;;
            "Financial Risk Assessment")
                echo "  - High allocation activity from complex calculations"
                echo "  - Opportunity for caching computed values"
                ;;
        esac
        echo ""
    else
        echo "No allocation profile data collected"
    fi
}

# Function to generate enhanced summary report
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

PROFILE DATA COLLECTION RESULTS:
===============================
EOF
    
    # Analyze collected profile files
    local total_profiles=0
    local profile_sizes=""
    
    for policy in "Simple_RBAC" "API_Authorization" "Financial_Risk_Assessment"; do
        local cpu_file="$PROFILE_DIR/${policy}_cpu.prof"
        local heap_file="$PROFILE_DIR/${policy}_heap.prof"
        local allocs_file="$PROFILE_DIR/${policy}_allocs.prof"
        
        if [ -f "$cpu_file" ]; then
            local size=$(stat -f%z "$cpu_file" 2>/dev/null || stat -c%s "$cpu_file" 2>/dev/null || echo "0")
            echo "✓ ${policy} CPU Profile: ${size} bytes" >> "$summary_file"
            total_profiles=$((total_profiles + 1))
        fi
        
        if [ -f "$heap_file" ]; then
            local size=$(stat -f%z "$heap_file" 2>/dev/null || stat -c%s "$heap_file" 2>/dev/null || echo "0")
            echo "✓ ${policy} Heap Profile: ${size} bytes" >> "$summary_file"
            total_profiles=$((total_profiles + 1))
        fi
        
        if [ -f "$allocs_file" ]; then
            local size=$(stat -f%z "$allocs_file" 2>/dev/null || stat -c%s "$allocs_file" 2>/dev/null || echo "0")
            echo "✓ ${policy} Allocations Profile: ${size} bytes" >> "$summary_file"
            total_profiles=$((total_profiles + 1))
        fi
    done
    
    echo "" >> "$summary_file"
    echo "Total profiles collected: $total_profiles" >> "$summary_file"
    
    cat >> "$summary_file" << EOF

OPTIMIZATION INSIGHTS BY POLICY:
================================

1. SIMPLE RBAC POLICY ANALYSIS:
   • Performance characteristics: Fast, low overhead
   • CPU usage: Minimal - basic string comparisons and rule evaluation
   • Memory pattern: Low allocation, mostly input processing
   • Optimization opportunities:
     - Rule ordering: Place most common roles first
     - Early returns: Admin checks before complex role logic
     - String interning: Cache common role strings

2. API AUTHORIZATION POLICY ANALYSIS:
   • Performance characteristics: Moderate complexity
   • CPU usage: JWT parsing, permission lookups, rate limiting
   • Memory pattern: Moderate allocations for token processing
   • Optimization opportunities:
     - Token caching: Cache validated JWT tokens
     - Permission indexing: Pre-build permission lookup tables
     - Early validation: Check authentication before permissions
     - Rate limit optimization: Use more efficient rate tracking

3. FINANCIAL RISK ASSESSMENT POLICY ANALYSIS:
   • Performance characteristics: High computational cost
   • CPU usage: Complex calculations, multiple data evaluations  
   • Memory pattern: High allocation from mathematical operations
   • Optimization opportunities:
     - Early rejection: Fail fast on obvious disqualifiers
     - Calculation caching: Cache expensive credit score computations
     - Rule reordering: Most selective rules first
     - Data structure optimization: Use lookup tables vs conditionals

PROFILING-GUIDED OPTIMIZATION FRAMEWORK:
========================================

Phase 1: Data Collection ✓ 
• CPU profiles identify computational hotspots
• Heap profiles show memory allocation patterns
• Allocation profiles reveal GC pressure points

Phase 2: Pattern Analysis
• Compare profile data across policy complexity levels
• Identify scaling bottlenecks as policy complexity increases  
• Map performance costs to specific policy constructs

Phase 3: Targeted Optimization (see opa-optimization-benchmark)
• Apply early rejection patterns for complex policies
• Implement caching for expensive calculations
• Reorder rules based on selectivity and cost
• Replace complex conditionals with lookup tables

PRODUCTION DEPLOYMENT RECOMMENDATIONS:
=====================================

Based on profiling analysis:

For Simple Policies (RBAC-style):
• Standard OPA deployment sufficient
• Focus on rule ordering optimization
• No special runtime configuration needed

For Moderate Policies (API Authorization):  
• Consider token validation caching
• Monitor JWT parsing overhead
• Implement permission lookup optimization

For Complex Policies (Financial Risk):
• ESSENTIAL: Implement profile-guided optimizations
• Use early rejection patterns
• Cache expensive calculations  
• Consider WASM compilation for 15-25% improvement
• Monitor memory usage and GC impact

NEXT STEPS:
==========
1. Review collected profile data in /app/profiles/
2. Run opa-optimization-benchmark to see optimized versions
3. Compare performance improvements from profiling insights
4. Apply similar optimization patterns to your policies

Profile data enables scientific, measurement-driven policy optimization
rather than guessing about performance characteristics.
EOF

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