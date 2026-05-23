#!/usr/bin/env python3
"""Проверка негативного сценария SPO8: файловая система не поддерживается."""
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
            f"использование: {Path(sys.argv[0]).name} <stdout.txt>",
            file=sys.stderr,
        )
        return 2

    actual = normalize(Path(sys.argv[1]).read_text(encoding="ascii"))
    if actual != EXPECTED:
        print("Вывод проверки неподдерживаемой ФС не совпал с ожидаемым", file=sys.stderr)
        print("--- ожидается ---", file=sys.stderr)
        print(EXPECTED, file=sys.stderr)
        print("--- получено ---", file=sys.stderr)
        print(actual, file=sys.stderr)
        return 1

    print("Btrfs unsupported-FS output OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
