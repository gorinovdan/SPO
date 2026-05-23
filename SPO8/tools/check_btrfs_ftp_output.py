#!/usr/bin/env python3
from pathlib import Path
import re
import sys


def normalize(text: str) -> str:
    return text.replace("\r\n", "\n").rstrip("\n") + "\n"


def require_all(actual: str, fragments: list[str], group: str) -> bool:
    missing = [fragment for fragment in fragments if fragment not in actual]
    if not missing:
        return True
    print(f"В выводе нет ожидаемых фрагментов: {group}", file=sys.stderr)
    for fragment in missing:
        print(f"  - {fragment!r}", file=sys.stderr)
    return False


def validate_stats(actual: str) -> bool:
    match = re.search(r"STATS cmd=(\d+) lookup=(\d+) stream=(\d+) gw=(\d+)\nOK(?:\n|$)", actual)
    if not match:
        print("Не найдена итоговая строка STATS/OK", file=sys.stderr)
        return False

    cmd_count, lookup_count, stream_bytes, group_waits = map(int, match.groups())
    if cmd_count < 20 or lookup_count < 10 or stream_bytes <= 0 or group_waits <= 0:
        print("Счётчики STATS выглядят некорректно", file=sys.stderr)
        print(match.group(0), file=sys.stderr)
        return False
    return True


def main() -> int:
    if len(sys.argv) != 2:
        print(f"использование: {Path(sys.argv[0]).name} <stdout.txt>", file=sys.stderr)
        return 2

    actual = normalize(Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace"))

    control_fragments = [
        "220 SPO8 Btrfs image ready",
        "215 UNIX Type: L8",
        "214 USER PASS FEAT OPTS PASV EPSV PWD LIST NLST CWD CDUP RETR SIZE MDTM COPY SYST NOOP HELP TYPE QUIT",
        "227 Entering Passive Mode (127,0,0,1,7,228)",
        '257 "/"',
        "250 CWD ok",
        '257 "/SPO8"',
        "150 directory stream follows",
        "150 inode=",
        " extent=btrfs",
        "213 ",
        "150 recursive directory copy follows",
        "226 copy complete",
        "550 not found",
        "221 bye",
    ]
    if not require_all(actual, control_fragments, "управляющий FTP-протокол"):
        print("--- получено ---", file=sys.stderr)
        print(actual, file=sys.stderr)
        return 1

    if "drwxr-xr-x" in actual or "-rw-r--r--" in actual:
        data_fragments = [
            "SPO8",
            "Makefile",
            "README.md",
            "demo",
            "docs",
            "tools",
            "tests",
            "small.txt",
            "SPO8 Btrfs FTP demo file.",
            "run_vm_tests.sh",
            "COPY file small.txt",
        ]
        if not require_all(actual, data_fragments, "пассивный поток данных"):
            print("--- получено ---", file=sys.stderr)
            print(actual, file=sys.stderr)
            return 1

    if not validate_stats(actual):
        print("--- получено ---", file=sys.stderr)
        print(actual, file=sys.stderr)
        return 1

    print("Btrfs FTP output OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
