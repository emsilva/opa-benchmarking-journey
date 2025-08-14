#!/bin/bash

# OPA Benchmark Utilities
# Shared functions for performance measurement and analysis

# Function to calculate percentiles from a file of latencies (one per line)
# Usage: calculate_percentiles <latencies_file> <total_count>
# Outputs: P50, P95, P99 in milliseconds
calculate_percentiles() {
    local latencies_file="$1"
    local total_count="$2"
    
    if [[ ! -f "$latencies_file" ]]; then
        echo "ERROR: Latencies file not found: $latencies_file" >&2
        return 1
    fi
    
    if [[ $total_count -eq 0 ]]; then
        echo "ERROR: Total count cannot be zero" >&2
        return 1
    fi
    
    # Sort latencies in ascending order
    sort -n "$latencies_file" > "${latencies_file}.sorted"
    
    # Calculate percentile positions (using nearest-rank method)
    local p50_pos=$(echo "scale=0; ($total_count * 50) / 100" | bc)
    local p95_pos=$(echo "scale=0; ($total_count * 95) / 100" | bc)
    local p99_pos=$(echo "scale=0; ($total_count * 99) / 100" | bc)
    
    # Ensure positions are at least 1
    if [[ $p50_pos -lt 1 ]]; then p50_pos=1; fi
    if [[ $p95_pos -lt 1 ]]; then p95_pos=1; fi
    if [[ $p99_pos -lt 1 ]]; then p99_pos=1; fi
    
    # Extract percentile values
    local p50=$(sed -n "${p50_pos}p" "${latencies_file}.sorted")
    local p95=$(sed -n "${p95_pos}p" "${latencies_file}.sorted")
    local p99=$(sed -n "${p99_pos}p" "${latencies_file}.sorted")
    
    # Clean up temporary file
    rm -f "${latencies_file}.sorted"
    
    # Output results (space-separated for easy parsing)
    echo "$p50 $p95 $p99"
}

# Function to measure individual request latency
# Usage: measure_latency <command_to_execute>
# Returns: latency in milliseconds
measure_latency() {
    local command="$@"
    
    local start_time=$(date +%s.%N)
    eval "$command" >/dev/null 2>&1 || true
    local end_time=$(date +%s.%N)
    
    # Calculate latency in milliseconds
    local latency_ms=$(echo "scale=3; ($end_time - $start_time) * 1000" | bc -l)
    echo "$latency_ms"
}

# Function to format percentile output for display
# Usage: format_percentiles <p50> <p95> <p99>
format_percentiles() {
    local p50="$1"
    local p95="$2"
    local p99="$3"
    
    printf "  Latency percentiles:\n"
    printf "    P50 (median): %6.2f ms\n" "$p50"
    printf "    P95:          %6.2f ms\n" "$p95"
    printf "    P99:          %6.2f ms\n" "$p99"
}

# Function to create temporary file for latencies
# Usage: create_latency_temp_file
# Returns: path to temporary file
create_latency_temp_file() {
    local temp_file="/tmp/opa-benchmark-latencies-$$-$(date +%s)"
    touch "$temp_file"
    echo "$temp_file"
}

# Function to calculate basic statistics from latencies file
# Usage: calculate_basic_stats <latencies_file>
# Returns: count, sum, mean, min, max (space-separated)
calculate_basic_stats() {
    local latencies_file="$1"
    
    if [[ ! -f "$latencies_file" ]]; then
        echo "ERROR: Latencies file not found: $latencies_file" >&2
        return 1
    fi
    
    # Use awk for efficient statistics calculation
    awk '
    BEGIN { 
        count = 0; sum = 0; min = ""; max = 0; 
    }
    {
        count++; 
        sum += $1;
        if (min == "" || $1 < min) min = $1;
        if ($1 > max) max = $1;
    }
    END { 
        if (count > 0) {
            mean = sum / count;
            printf "%.0f %.3f %.3f %.3f %.3f\n", count, sum, mean, min, max;
        } else {
            print "0 0 0 0 0";
        }
    }' "$latencies_file"
}

# Test function to validate percentile calculations
# Usage: test_percentiles
test_percentiles() {
    echo "Testing percentile calculations..."
    
    # Create test data: 1, 2, 3, ..., 100
    local test_file="/tmp/test-percentiles-$$"
    for i in $(seq 1 100); do
        echo "$i" >> "$test_file"
    done
    
    # Calculate percentiles
    local percentiles=$(calculate_percentiles "$test_file" 100)
    local p50=$(echo $percentiles | cut -d' ' -f1)
    local p95=$(echo $percentiles | cut -d' ' -f2)  
    local p99=$(echo $percentiles | cut -d' ' -f3)
    
    echo "Test data: 1-100"
    echo "P50: $p50 (expected: 50)"
    echo "P95: $p95 (expected: 95)" 
    echo "P99: $p99 (expected: 99)"
    
    # Verify results
    if [[ "$p50" == "50" && "$p95" == "95" && "$p99" == "99" ]]; then
        echo "✓ Percentile calculations are correct"
    else
        echo "✗ Percentile calculations failed validation"
    fi
    
    # Clean up
    rm -f "$test_file"
}

# Functions are available when this script is sourced