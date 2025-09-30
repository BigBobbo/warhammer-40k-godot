#!/usr/bin/env python3
"""
Parse GUT test results and generate validation report
Usage: python3 parse_test_results.py test_results/*.log > VALIDATION_REPORT.md
"""

import sys
import re
from pathlib import Path
from datetime import datetime


def parse_log_file(log_path):
    """Parse a single test log file and extract results."""
    with open(log_path, 'r') as f:
        content = f.read()

    results = {
        'category': log_path.stem.replace('_results', ''),
        'total': 0,
        'passed': 0,
        'failed': 0,
        'errors': [],
        'test_files': [],
        'compilation_errors': []
    }

    # Extract test counts
    total_match = re.search(r'Total:\s*(\d+)', content)
    passed_match = re.search(r'Passed:\s*(\d+)', content)
    failed_match = re.search(r'Failed:\s*(\d+)', content)

    if total_match:
        results['total'] = int(total_match.group(1))
    if passed_match:
        results['passed'] = int(passed_match.group(1))
    if failed_match:
        results['failed'] = int(failed_match.group(1))

    # Extract test file names
    test_file_pattern = r'Running tests in:\s*(res://tests/[\w/]+\.gd)'
    results['test_files'] = re.findall(test_file_pattern, content)

    # Extract compilation errors
    error_pattern = r'SCRIPT ERROR:\s*(.+?)(?=\n(?:SCRIPT ERROR:|Running tests|$))'
    results['compilation_errors'] = re.findall(error_pattern, content, re.DOTALL)

    return results


def generate_report(all_results):
    """Generate markdown validation report from parsed results."""
    print("# Test Validation Report")
    print(f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    # Overall summary
    total_tests = sum(r['total'] for r in all_results)
    total_passed = sum(r['passed'] for r in all_results)
    total_failed = sum(r['failed'] for r in all_results)

    print("## Overall Summary")
    print()
    print(f"- **Total Tests**: {total_tests}")
    print(f"- **Passed**: {total_passed} ({total_passed/total_tests*100:.1f}%)" if total_tests > 0 else "- **Passed**: 0")
    print(f"- **Failed**: {total_failed} ({total_failed/total_tests*100:.1f}%)" if total_tests > 0 else "- **Failed**: 0")
    print()

    # Category breakdown
    print("## Results by Category")
    print()

    for result in all_results:
        category = result['category'].replace('_', ' ').title()
        status_emoji = "✅" if result['failed'] == 0 and result['total'] > 0 else "❌"

        print(f"### {status_emoji} {category}")
        print()
        print(f"- **Total**: {result['total']}")
        print(f"- **Passed**: {result['passed']}")
        print(f"- **Failed**: {result['failed']}")
        print()

        if result['test_files']:
            print(f"**Test Files** ({len(result['test_files'])}):")
            for test_file in result['test_files']:
                print(f"- `{test_file}`")
            print()

        if result['compilation_errors']:
            print("**Compilation Errors:**")
            for i, error in enumerate(result['compilation_errors'][:5], 1):  # Limit to 5
                error_clean = error.strip().replace('\n', ' ')[:200]  # Truncate long errors
                print(f"{i}. {error_clean}...")
            if len(result['compilation_errors']) > 5:
                print(f"... and {len(result['compilation_errors']) - 5} more errors")
            print()

    # Recommendations
    print("## Recommendations")
    print()

    if total_failed > 0:
        print("### Critical Issues")
        print()
        for result in all_results:
            if result['failed'] > 0:
                print(f"- Fix {result['failed']} failing tests in **{result['category']}**")
        print()

    if any(r['compilation_errors'] for r in all_results):
        print("### Compilation Errors")
        print()
        print("The following categories have compilation errors that prevent tests from running:")
        for result in all_results:
            if result['compilation_errors']:
                print(f"- **{result['category']}**: {len(result['compilation_errors'])} errors")
        print()

    print("### Next Steps")
    print()
    print("1. Fix all compilation errors")
    print("2. Investigate and fix failing tests")
    print("3. Run validation again to verify fixes")
    print("4. Update test coverage for missing areas")


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 parse_test_results.py <log_file1> [log_file2] ...", file=sys.stderr)
        sys.exit(1)

    all_results = []
    for log_path_str in sys.argv[1:]:
        log_path = Path(log_path_str)
        if log_path.exists():
            results = parse_log_file(log_path)
            all_results.append(results)
        else:
            print(f"Warning: {log_path} not found", file=sys.stderr)

    if not all_results:
        print("Error: No valid log files found", file=sys.stderr)
        sys.exit(1)

    generate_report(all_results)


if __name__ == '__main__':
    main()