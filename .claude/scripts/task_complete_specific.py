#!/usr/bin/env python3
"""Mark a specific task as done or blocked, identified by its description text.

This is the parallel-safe counterpart to task_complete.py. Instead of marking
the first incomplete task, it finds a specific task by matching the first line
of its description text (after the checkbox marker).

Uses file locking to prevent race conditions when multiple agents write
to the same file concurrently.

Usage:
    task_complete_specific.py <filename> --task "task description text"
    task_complete_specific.py <filename> --task "task description text" --blocked
    task_complete_specific.py <filename> --task "task description text" --done
"""

import sys
import os
import re
import argparse
import fcntl


def normalize(text):
    """Normalize whitespace for comparison."""
    return " ".join(text.split()).strip()


def mark_specific_task(filename, task_text, mark_type):
    try:
        if not os.path.exists(filename):
            print("No tasks found (file doesn't exist)", file=sys.stderr)
            sys.exit(1)

        normalized_target = normalize(task_text)

        with open(filename, "r+") as file:
            # Acquire exclusive lock
            fcntl.flock(file.fileno(), fcntl.LOCK_EX)

            lines = file.readlines()
            modified = False
            task_lines = []

            for i, line in enumerate(lines):
                # Match tasks that are in-progress [>] or incomplete [ ]
                match = re.match(r"^- \[[> ]\] (.+)", line)
                if match:
                    line_task_text = normalize(match.group(1))
                    if line_task_text == normalized_target:
                        # Found the task - mark it
                        if mark_type == "blocked":
                            lines[i] = re.sub(r"^- \[[> ]\]", "- [!]", line)
                        else:
                            lines[i] = re.sub(r"^- \[[> ]\]", "- [x]", line)

                        task_lines.append(lines[i])

                        # Collect continuation lines
                        j = i + 1
                        while j < len(lines):
                            next_line = lines[j]
                            if re.match(r"^[\s\t]+", next_line) and next_line.strip():
                                task_lines.append(next_line)
                            elif re.match(r"^- \[", next_line):
                                break
                            elif re.match(r"^#", next_line):
                                break
                            elif next_line.strip() == "":
                                task_lines.append(next_line)
                            else:
                                break
                            j += 1

                        modified = True
                        break

            if modified:
                file.seek(0)
                file.truncate()
                file.writelines(lines)

                # Trim trailing blank lines from output
                while task_lines and task_lines[-1].strip() == "":
                    task_lines.pop()

                print("".join(task_lines), end="")
            else:
                print(
                    f"Warning: Could not find task matching: {task_text}",
                    file=sys.stderr,
                )
                sys.exit(1)

            fcntl.flock(file.fileno(), fcntl.LOCK_UN)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Mark a specific task as done or blocked by matching its description"
    )
    parser.add_argument("filename", help="File containing tasks")
    parser.add_argument(
        "--task",
        required=True,
        help="The task description text to match (first line after the checkbox)",
    )
    parser.add_argument(
        "--blocked",
        action="store_true",
        help="Mark as blocked [!] instead of done [x]",
    )
    parser.add_argument(
        "--done", action="store_true", help="Mark as done [x] (default)"
    )

    args = parser.parse_args()

    if args.blocked:
        mark_type = "blocked"
    else:
        mark_type = "done"

    mark_specific_task(args.filename, args.task, mark_type)
