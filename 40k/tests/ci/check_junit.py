#!/usr/bin/env python3
"""Fail-closed check of GUT JUnit results against a known-failure allowlist.

Usage (from 40k/):
    python3 tests/ci/check_junit.py --xml unit_test_results.xml --dir tests/unit \
        [--allowlist tests/ci/gut_known_failures.txt]

Exit 0 only when ALL of these hold:
  * the XML exists, parses and reports at least one test;
  * every test_*.gd file under --dir appears as a <testsuite> (GUT silently
    skips a file that fails to parse — that used to read as green);
  * every failing testcase is allowlisted (``suite::testcase`` or ``suite::*``);
  * no allowlisted entry for this directory now passes or no longer exists
    (the list may only shrink — a fixed test must be delisted).

Allowlist format: one entry per line, ``res-relative/suite.gd::test_name``
(or ``::*`` for a whole file), optional trailing ``# reason``. Blank lines and
``#`` comments are ignored. Entries outside --dir are ignored, so one list can
serve the unit, integration and network runs. A leading ``?`` marks a
documented intermittent failure (e.g. the multi-peer Formations re-entry race):
it may pass or fail without failing the check, but must still exist.
"""
import argparse
import glob
import os
import sys
import xml.etree.ElementTree as ET


def load_allowlist(path):
    entries = {}
    if not path or not os.path.exists(path):
        return entries
    with open(path, encoding="utf-8") as f:
        for n, raw in enumerate(f, 1):
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            if "::" not in line:
                print(f"::error::{path}:{n}: malformed entry {raw.strip()!r} (want suite.gd::test)")
                sys.exit(2)
            reason = raw.split("#", 1)[1].strip() if "#" in raw else ""
            flaky = line.startswith("?")
            entries[line.lstrip("?").strip()] = {"reason": reason, "flaky": flaky}
    return entries


def is_gut_test(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if line.startswith("extends"):
                return "GutTest" in line or "addons/gut/test.gd" in line
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--xml", required=True)
    ap.add_argument("--dir", required=True, help="test directory the run covered, e.g. tests/unit")
    ap.add_argument("--allowlist", default="tests/ci/gut_known_failures.txt")
    ap.add_argument("--exclude-prefix", action="append", default=[],
                    help="basename prefix of GUT files this run deliberately did not include")
    ap.add_argument("--include-prefix", action="append", default=[],
                    help="only consider GUT files whose basename starts with this prefix")
    args = ap.parse_args()

    errors = []
    if not os.path.exists(args.xml):
        print(f"::error::JUnit file {args.xml} is missing (GUT crashed, hung or never ran)")
        return 1
    try:
        root = ET.parse(args.xml).getroot()
    except ET.ParseError as e:
        print(f"::error::JUnit file {args.xml} does not parse: {e}")
        return 1

    prefix = args.dir.rstrip("/") + "/"

    def in_scope(path):
        base = os.path.basename(path)
        if any(base.startswith(x) for x in args.exclude_prefix):
            return False
        return not args.include_prefix or any(base.startswith(x) for x in args.include_prefix)

    allow = {k: v for k, v in load_allowlist(args.allowlist).items()
             if k.startswith(prefix) and in_scope(k.split("::", 1)[0])}

    suites = {}
    total = failed = 0
    for suite in root.iter("testsuite"):
        name = suite.get("name", "")
        if not in_scope(name):
            continue
        cases = {}
        for case in suite.iter("testcase"):
            total += 1
            is_fail = case.find("failure") is not None or case.find("error") is not None
            failed += int(is_fail)
            cases[case.get("name", "")] = is_fail
        suites[name] = cases

    if total == 0:
        errors.append(f"{args.xml} reports 0 tests")

    # Only GUT tests belong in the JUnit results; `extends SceneTree` scripts in
    # the same directories are direct `godot -s` tests, not run by GUT.
    on_disk = sorted(os.path.relpath(p) for p in glob.glob(os.path.join(args.dir, "**", "test_*.gd"), recursive=True)
                     if is_gut_test(p) and in_scope(p))
    for path in on_disk:
        if path not in suites and f"{path}::*" not in allow:
            errors.append(f"{path}: not in the JUnit results — GUT skipped it (parse/compile error?)")

    unexpected = []
    for sname, cases in suites.items():
        for cname, is_fail in cases.items():
            key = f"{sname}::{cname}"
            if is_fail and key not in allow and f"{sname}::*" not in allow:
                unexpected.append(key)
    for key in unexpected:
        errors.append(f"{key}: FAILED (not in the known-failure allowlist)")

    for key in sorted(allow):
        sname, cname = key.split("::", 1)
        if cname == "*":
            if sname in suites and not any(suites[sname].values()):
                errors.append(f"{key}: allowlisted file now runs green — delist it")
            continue
        if sname not in suites or cname not in suites[sname]:
            errors.append(f"{key}: allowlisted but not found in results — delist or fix the name")
        elif not suites[sname][cname] and not allow[key]["flaky"]:
            errors.append(f"{key}: allowlisted but now PASSES — delist it")

    print(f"{args.xml}: {total} tests, {failed} failing, {len(allow)} allowlisted for {prefix}")
    for e in errors:
        print(f"::error::{e}")
    if errors:
        print(f"FAIL: {len(errors)} problem(s)")
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
