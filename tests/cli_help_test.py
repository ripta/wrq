#!/usr/bin/env python3

import pathlib
import subprocess
import sys


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    binary = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else root / "wrk")
    if not binary.is_absolute():
        binary = root / binary

    for option in ("-h", "--help"):
        result = subprocess.run(
            [str(binary), option],
            cwd=str(root),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
        )
        if result.returncode != 0:
            sys.stderr.write("{} exited with status {}\n".format(option, result.returncode))
            sys.stderr.write(result.stderr)
            return 1
        if not result.stdout.startswith("Usage: wrk "):
            sys.stderr.write("{} did not print usage to stdout\n".format(option))
            return 1
        if "-h, --help" not in result.stdout:
            sys.stderr.write("{} output did not document the help flags\n".format(option))
            return 1
        if result.stderr:
            sys.stderr.write("{} unexpectedly wrote to stderr:\n".format(option))
            sys.stderr.write(result.stderr)
            return 1

    for option in ("-v", "--version"):
        result = subprocess.run(
            [str(binary), option],
            cwd=str(root),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
        )
        if result.returncode != 0:
            sys.stderr.write("{} exited with status {}\n".format(option, result.returncode))
            sys.stderr.write(result.stderr)
            return 1
        if not result.stdout.startswith("wrk 4.1.0 ["):
            sys.stderr.write("{} did not print the version banner\n".format(option))
            return 1
        if not result.stdout.endswith("] Copyright (C) 2012 Will Glozer\n"):
            sys.stderr.write("{} printed an unexpected version banner\n".format(option))
            return 1
        if len(result.stdout.splitlines()) != 1:
            sys.stderr.write("{} printed more than the version banner\n".format(option))
            return 1
        if result.stderr:
            sys.stderr.write("{} unexpectedly wrote to stderr:\n".format(option))
            sys.stderr.write(result.stderr)
            return 1

    print("CLI help and version flags print their output and exit successfully")
    return 0


if __name__ == "__main__":
    sys.exit(main())
