#!/usr/bin/env python3
from pathlib import Path
import sys


EXPECTED = """SPO7 SQLMR
MODE SYNC-NB GROUP-WAIT
Q1 R=1 P=5 W=1
Q2 R=0 P=5 W=1
Q3 R=5004 P=4 W=1
Q4 R=40 P=6 W=2
Q5 R=85 P=7 W=2
Q6 R=0 P=8 W=2
Q7 R=0 P=5 W=1
IRQ=48 GW=10
OK
"""


def main() -> int:
    if len(sys.argv) == 3 and sys.argv[1] == "--write-expected":
        Path(sys.argv[2]).write_text(EXPECTED, encoding="ascii")
        print(f"wrote expected SQL pipeline output to {sys.argv[2]}")
        return 0

    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} [--write-expected] <stdout.txt>", file=sys.stderr)
        return 2

    actual = Path(sys.argv[1]).read_text(encoding="ascii").replace("\r\n", "\n").rstrip("\n") + "\n"
    if actual != EXPECTED:
        print("SQL pipeline output mismatch", file=sys.stderr)
        print("--- expected ---", file=sys.stderr)
        print(EXPECTED, file=sys.stderr)
        print("--- actual ---", file=sys.stderr)
        print(actual, file=sys.stderr)
        return 1

    print("SQL pipeline output OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
