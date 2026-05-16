#!/usr/bin/env python3
from pathlib import Path
import re
import sys


EXPECTED_PREFIX = """SPO8 BTRFS FTP
FS OK magic=_BHRfS_M root_dir=6 nodesize=4096
220 SPO8 Btrfs image ready
> SYST
215 UNIX Type: L8
> NOOP
200 NOOP ok
> HELP
214-Supported commands:
214 PASV PWD LIST CWD RETR COPY SYST NOOP HELP TYPE QUIT
> PASV
227 Entering Passive Mode (0,0,0,0,0,1)
> TYPE I
200 Type set
> PWD
257 "/"
> LIST
150 directory stream follows
d 258 0 docs
d 260 0 pictures
f 257 19 readme.txt
226 transfer complete
> CWD docs
250 CWD ok
> PWD
257 "/docs"
> LIST
150 directory stream follows
f 259 19 info.txt
f 261 12 help.txt
226 transfer complete
> RETR info.txt
150 inode=259 size=19 extent=inline
BTRFS TREE WALK OK
226 transfer complete
> RETR help.txt
150 inode=261 size=12 extent=inline
RETR works.
226 transfer complete
> CWD ..
250 CWD ok
> PWD
257 "/"
> COPY docs
150 recursive directory copy follows
COPY file info.txt
150 inode=259 size=19 extent=inline
BTRFS TREE WALK OK
226 transfer complete
COPY file help.txt
150 inode=261 size=12 extent=inline
RETR works.
226 transfer complete
226 copy complete
> CWD pictures
250 CWD ok
> LIST
150 directory stream follows
f 262 17 notes.txt
226 transfer complete
> RETR notes.txt
150 inode=262 size=17 extent=inline
subtree readable
226 transfer complete
> CWD /
250 CWD ok
> RETR readme.txt
150 inode=257 size=19 extent=inline
Hello from SPO8 FS
226 transfer complete
> COPY readme.txt
150 inode=257 size=19 extent=inline
Hello from SPO8 FS
226 transfer complete
> RETR missing.txt
550 not found
> CWD ghost
550 not found
> QUIT
221 bye
"""

EXPECTED = EXPECTED_PREFIX + """STATS cmd=24 lookup=15 stream=1518 gw=218
OK
"""


def normalize(text: str) -> str:
    return text.replace("\r\n", "\n").rstrip("\n") + "\n"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} <stdout.txt>", file=sys.stderr)
        return 2

    actual = normalize(Path(sys.argv[1]).read_text(encoding="ascii"))
    if not actual.startswith(EXPECTED_PREFIX):
        print("Btrfs FTP output prefix mismatch", file=sys.stderr)
        print("--- expected prefix ---", file=sys.stderr)
        print(EXPECTED_PREFIX, file=sys.stderr)
        print("--- actual ---", file=sys.stderr)
        print(actual, file=sys.stderr)
        return 1

    stats = actual[len(EXPECTED_PREFIX):]
    match = re.fullmatch(r"STATS cmd=24 lookup=15 stream=(\d+) gw=(\d+)\nOK\n", stats)
    if not match:
        print("Btrfs FTP stats mismatch", file=sys.stderr)
        print("--- actual stats ---", file=sys.stderr)
        print(stats, file=sys.stderr)
        return 1

    stream_bytes = int(match.group(1))
    group_waits = int(match.group(2))
    if stream_bytes <= 0 or group_waits <= 0:
        print("Btrfs FTP counters must be positive", file=sys.stderr)
        return 1

    print("Btrfs FTP output OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
