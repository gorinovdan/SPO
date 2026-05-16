#!/usr/bin/env python3
"""Validator for the SPO8 negative-path demo (unsupported filesystem)."""
from pathlib import Path
import sys


EXPECTED = """SPO8 BTRFS FTP
500 unsupported filesystem
OK_NEG
"""


def normalize(text: str) -> str:
    return text.replace("\r\n", "\n").rstrip("\n") + "\n"


def main() -> int:
    if len(sys.argv) != 2:
        print(
            f"usage: {Path(sys.argv[0]).name} <stdout.txt>",
            file=sys.stderr,
        )
        return 2

    actual = normalize(Path(sys.argv[1]).read_text(encoding="ascii"))
    if actual != EXPECTED:
        print("Btrfs unsupported-FS output mismatch", file=sys.stderr)
        print("--- expected ---", file=sys.stderr)
        print(EXPECTED, file=sys.stderr)
        print("--- actual ---", file=sys.stderr)
        print(actual, file=sys.stderr)
        return 1

    print("Btrfs unsupported-FS output OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
