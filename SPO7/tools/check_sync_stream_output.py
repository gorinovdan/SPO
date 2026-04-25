#!/usr/bin/env python3
from pathlib import Path
import sys


EXPECTED = """SPO7
FCFS C=10,20,30,40 T=PPFCCEPPCC W=1/1 I=10 D=4
SPN C=10,20,30,40 T=EPCEPCPCPC W=0/2 I=10 D=9
OK
"""


def main() -> int:
    if len(sys.argv) == 3 and sys.argv[1] == "--write-expected":
        Path(sys.argv[2]).write_text(EXPECTED, encoding="ascii")
        print(f"wrote expected sync-stream output to {sys.argv[2]}")
        return 0

    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} [--write-expected] <stdout.txt>", file=sys.stderr)
        return 2

    actual = Path(sys.argv[1]).read_text(encoding="ascii").replace("\r\n", "\n").rstrip("\n") + "\n"
    if actual != EXPECTED:
        print("sync-stream output mismatch", file=sys.stderr)
        print("--- expected ---", file=sys.stderr)
        print(EXPECTED, file=sys.stderr)
        print("--- actual ---", file=sys.stderr)
        print(actual, file=sys.stderr)
        return 1

    print("sync-stream output OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
