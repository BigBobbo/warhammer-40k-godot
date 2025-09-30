#!/bin/bash

# Test Validation Script
# Runs all test categories and generates validation reports
# Usage: ./validate_all_tests.sh

set -e

echo "========================================="
echo "  Warhammer 40k Test Validation Suite"
echo "========================================="
echo ""

# Create results directory
mkdir -p test_results

# Set Godot path
export PATH="$HOME/bin:$PATH"

# Test directories
TEST_DIRS=("unit" "phases" "integration" "ui")

# Function to run tests for a directory
run_test_category() {
    local category=$1
    echo "========================================="
    echo "Testing: $category"
    echo "========================================="

    godot --headless --path /Users/robertocallaghan/Documents/claude/godotv2/40k \
        -s addons/gut/gut_cmdln.gd \
        -gdir=res://tests/$category \
        -gprefix=test_ \
        -glog=1 \
        -gexit \
        > test_results/${category}_results.log 2>&1

    # Extract summary
    echo ""
    echo "Results for $category:"
    if grep -q "Total:" test_results/${category}_results.log; then
        grep -E "Total:|Passed:|Failed:" test_results/${category}_results.log | head -3
    else
        echo "  ERROR: Tests did not complete or no results found"
        echo "  Check test_results/${category}_results.log for details"
    fi
    echo "---"
}

# Run tests for each category
for dir in "${TEST_DIRS[@]}"; do
    run_test_category "$dir"
    echo ""
done

# Generate summary report
echo ""
echo "========================================="
echo "  Generating Summary Report"
echo "========================================="

# Use Python parser if available
if command -v python3 &> /dev/null; then
    python3 scripts/parse_test_results.py test_results/*_results.log > test_results/VALIDATION_REPORT.md
    echo "Detailed validation report saved to: test_results/VALIDATION_REPORT.md"
else
    # Fallback to simple summary
    {
        echo "# Test Validation Summary"
        echo "Generated: $(date)"
        echo ""
        echo "## Results by Category"
        echo ""

        for dir in "${TEST_DIRS[@]}"; do
            echo "### $dir Tests"
            if [ -f "test_results/${dir}_results.log" ]; then
                if grep -q "Total:" "test_results/${dir}_results.log"; then
                    grep -E "Total:|Passed:|Failed:" "test_results/${dir}_results.log" | head -3
                else
                    echo "ERROR: No test results found"
                fi
            else
                echo "ERROR: Log file not found"
            fi
            echo ""
        done

        echo "## Detailed Logs"
        echo ""
        echo "Individual test results are available in:"
        for dir in "${TEST_DIRS[@]}"; do
            echo "- test_results/${dir}_results.log"
        done

    } > test_results/SUMMARY.md

    echo "Summary report saved to: test_results/SUMMARY.md"
fi
echo ""
echo "========================================="
echo "  Validation Complete"
echo "========================================="