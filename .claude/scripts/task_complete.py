#!/usr/bin/env python3

import sys
import os
import re
import argparse


def mark_first_task(filename, mark_type):
    try:
        if not os.path.exists(filename):
            print(f"No tasks found (file doesn't exist)", file=sys.stderr)
            sys.exit(1)

        with open(filename, "r") as file:
            lines = file.readlines()

        modified = False
        task_lines = []

        for i, line in enumerate(lines):
            if re.match(r"^- \[ \]", line):
                if mark_type == "progress":
                    lines[i] = re.sub(r"^- \[ \]", "- [>]", line)
                elif mark_type == "blocked":
                    lines[i] = re.sub(r"^- \[ \]", "- [!]", line)
                else:
                    lines[i] = re.sub(r"^- \[ \]", "- [x]", line)

                task_lines.append(lines[i])
                modified = True

                j = i + 1
                while j < len(lines):
                    next_line = lines[j]
                    if re.match(r"^[\s\t]+", next_line) and next_line.strip():
                        task_lines.append(next_line)
                    elif re.match(r"^- \[[x>\s]\]", next_line):
                        break
                    elif re.match(r"^#", next_line):
                        break
                    elif next_line.strip() == "":
                        task_lines.append(next_line)
                    else:
                        break
                    j += 1
                break

        if modified:
            with open(filename, "w") as file:
                file.writelines(lines)

            while task_lines and task_lines[-1].strip() == "":
                task_lines.pop()

            print("".join(task_lines), end="")
        else:
            print("No incomplete tasks found", file=sys.stderr)
            sys.exit(1)

    except FileNotFoundError:
        print(f"Error: File '{filename}' not found", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Mark first incomplete task as done, in-progress, or blocked"
    )
    parser.add_argument("filename", help="File containing tasks")
    parser.add_argument(
        "--progress",
        action="store_true",
        help="Mark as in-progress [>] instead of done [x]",
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

    if sum([args.progress, args.blocked, args.done]) > 1:
        print("Error: Cannot specify multiple mark types", file=sys.stderr)
        sys.exit(1)

    if args.progress:
        mark_type = "progress"
    elif args.blocked:
        mark_type = "blocked"
    else:
        mark_type = "done"

    mark_first_task(args.filename, mark_type)
