#!/bin/bash

# Improved Test Validation Script with Timeout Handling
# Runs tests in smaller batches with timeouts to prevent hanging
# Usage: ./validate_tests_with_timeout.sh [category]

set +e  # Don't exit on error - we want to continue even if tests fail

echo "========================================="
echo "  Warhammer 40k Test Validation Suite"
echo "  (With Timeout Protection)"
echo "========================================="
echo ""

# Create results directory
mkdir -p test_results

# Set Godot path
export PATH="$HOME/bin:$PATH"

# Configuration
TIMEOUT_SECONDS=300  # 5 minutes per test file
MAX_RETRIES=1

# Function to run a single test file with timeout
run_single_test() {
    local test_file=$1
    local test_name=$(basename "$test_file" .gd)
    local log_file="test_results/${test_name}.log"

    echo "Testing: $test_name"

    # Run with timeout
    (
        godot --headless --path /Users/robertocallaghan/Documents/claude/godotv2/40k \
            -s addons/gut/gut_cmdln.gd \
            -gtest="$test_file" \
            -glog=1 \
            -gexit \
            > "$log_file" 2>&1
    ) &

    local pid=$!
    local elapsed=0

    # Wait with timeout
    while kill -0 $pid 2>/dev/null; do
        sleep 1
        elapsed=$((elapsed + 1))
        if [ $elapsed -ge $TIMEOUT_SECONDS ]; then
            echo "  ⏱️  TIMEOUT after ${TIMEOUT_SECONDS}s - killing process"
            kill -9 $pid 2>/dev/null
            echo "TIMEOUT: Test exceeded ${TIMEOUT_SECONDS} seconds" >> "$log_file"
            return 2
        fi
    done

    wait $pid
    local exit_code=$?

    # Check results
    if [ $exit_code -eq 0 ]; then
        if grep -q "Total:" "$log_file"; then
            local total=$(grep "Total:" "$log_file" | grep -o "[0-9]*" | head -1)
            local passed=$(grep "Passed:" "$log_file" | grep -o "[0-9]*" | head -1)
            local failed=$(grep "Failed:" "$log_file" | grep -o "[0-9]*" | head -1)
            echo "  ✅ Complete: $passed/$total passed, $failed failed (${elapsed}s)"
            return 0
        else
            echo "  ⚠️  No results found (${elapsed}s)"
            return 1
        fi
    else
        echo "  ❌ Error: exit code $exit_code (${elapsed}s)"
        return 1
    fi
}

# Function to run tests in a category
run_test_category() {
    local category=$1
    echo ""
    echo "========================================="
    echo "Category: $category"
    echo "========================================="

    # Find all test files in category
    local test_files=$(find "/Users/robertocallaghan/Documents/claude/godotv2/40k/tests/$category" -name "test_*.gd" 2>/dev/null)

    if [ -z "$test_files" ]; then
        echo "No test files found in $category"
        return
    fi

    local total_tests=0
    local completed_tests=0
    local timeout_tests=0
    local failed_tests=0

    # Run each test file separately
    while IFS= read -r test_file; do
        total_tests=$((total_tests + 1))
        run_single_test "$test_file"
        result=$?

        if [ $result -eq 0 ]; then
            completed_tests=$((completed_tests + 1))
        elif [ $result -eq 2 ]; then
            timeout_tests=$((timeout_tests + 1))
        else
            failed_tests=$((failed_tests + 1))
        fi
    done <<< "$test_files"

    # Category summary
    echo ""
    echo "Category Summary:"
    echo "  Total test files: $total_tests"
    echo "  Completed: $completed_tests"
    echo "  Timeouts: $timeout_tests"
    echo "  Errors: $failed_tests"

    # Create category summary file
    {
        echo "# $category Test Results"
        echo "Generated: $(date)"
        echo ""
        echo "## Summary"
        echo "- Total test files: $total_tests"
        echo "- Completed: $completed_tests"
        echo "- Timeouts: $timeout_tests"
        echo "- Errors: $failed_tests"
        echo ""
        echo "## Individual Results"
        echo ""

        for log in test_results/test_*.log; do
            if [ -f "$log" ]; then
                local name=$(basename "$log" .log)
                echo "### $name"
                if grep -q "TIMEOUT" "$log"; then
                    echo "**Status:** ⏱️ Timeout"
                elif grep -q "Total:" "$log"; then
                    echo "**Status:** ✅ Complete"
                    grep -E "Total:|Passed:|Failed:" "$log" | head -3
                else
                    echo "**Status:** ⚠️ Error or No Results"
                fi
                echo ""
            fi
        done
    } > "test_results/${category}_category_summary.md"

    echo "Category summary saved to: test_results/${category}_category_summary.md"
}

# Main execution
if [ $# -eq 1 ]; then
    # Single category specified
    run_test_category "$1"
else
    # Run all categories
    for category in unit phases integration ui; do
        run_test_category "$category"
    done

    # Generate overall summary
    echo ""
    echo "========================================="
    echo "  Generating Overall Summary"
    echo "========================================="

    {
        echo "# Overall Test Validation Results"
        echo "Generated: $(date)"
        echo ""
        echo "## Category Summaries"
        echo ""

        for category in unit phases integration ui; do
            if [ -f "test_results/${category}_category_summary.md" ]; then
                echo "### $category"
                grep -A 4 "## Summary" "test_results/${category}_category_summary.md" | tail -4
                echo ""
            fi
        done

        echo "## Detailed Results"
        echo ""
        echo "See individual category summaries:"
        for category in unit phases integration ui; do
            echo "- test_results/${category}_category_summary.md"
        done
    } > test_results/OVERALL_SUMMARY.md

    echo "Overall summary saved to: test_results/OVERALL_SUMMARY.md"
fi

echo ""
echo "========================================="
echo "  Validation Complete"
echo "========================================="
echo ""
echo "Results available in test_results/ directory"