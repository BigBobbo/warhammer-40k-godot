#!/usr/bin/env python3
"""Extract up to N incomplete tasks and mark them all as in-progress.

Returns the tasks as numbered entries so the caller can dispatch them
to parallel agents. Each task is separated by a blank line.

Usage:
    task_get_batch.py <filename> <count>

Example output:
    === TASK 1 ===
    - [>] Fix the battle logic for melee phase
      Details about the task...
    === TASK 2 ===
    - [>] Add unit tests for deployment
"""

import sys
import os
import re
import fcntl


def extract_batch(filename, count):
    try:
        if not os.path.exists(filename):
            print("No tasks found (file doesn't exist)", file=sys.stderr)
            sys.exit(1)

        # Use file locking to prevent race conditions
        with open(filename, "r+") as file:
            fcntl.flock(file.fileno(), fcntl.LOCK_EX)

            lines = file.readlines()
            tasks = []
            task_start_indices = []

            # Find all incomplete tasks
            i = 0
            while i < len(lines) and len(tasks) < count:
                if re.match(r"^- \[ \]", lines[i]):
                    task_lines = [i]  # Store line indices
                    j = i + 1
                    while j < len(lines):
                        next_line = lines[j]
                        if re.match(r"^[\s\t]+", next_line) and next_line.strip():
                            task_lines.append(j)
                        elif re.match(r"^- \[[x>!]\]", next_line):
                            break
                        elif re.match(r"^- \[ \]", next_line):
                            break
                        elif re.match(r"^#", next_line):
                            break
                        elif next_line.strip() == "":
                            task_lines.append(j)
                        else:
                            break
                        j += 1

                    # Trim trailing blank lines from task
                    while task_lines and lines[task_lines[-1]].strip() == "":
                        task_lines.pop()

                    tasks.append(task_lines)
                    task_start_indices.append(i)
                    i = j
                else:
                    i += 1

            if not tasks:
                print("No incomplete tasks found", file=sys.stderr)
                sys.exit(1)

            # Mark all found tasks as in-progress
            for task_line_indices in tasks:
                first_idx = task_line_indices[0]
                lines[first_idx] = re.sub(r"^- \[ \]", "- [>]", lines[first_idx])

            # Write back
            file.seek(0)
            file.truncate()
            file.writelines(lines)

            fcntl.flock(file.fileno(), fcntl.LOCK_UN)

        # Output the tasks in a parseable format
        for task_num, task_line_indices in enumerate(tasks, 1):
            print(f"=== TASK {task_num} ===")
            for idx in task_line_indices:
                print(lines[idx], end="")
            print()

        print(f"Total: {len(tasks)} tasks extracted", file=sys.stderr)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: task_get_batch.py <filename> <count>", file=sys.stderr)
        sys.exit(1)

    try:
        count = int(sys.argv[2])
        if count < 1:
            raise ValueError
    except ValueError:
        print("Error: count must be a positive integer", file=sys.stderr)
        sys.exit(1)

    extract_batch(sys.argv[1], count)
