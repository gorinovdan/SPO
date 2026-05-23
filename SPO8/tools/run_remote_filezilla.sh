#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

ADAPTER_BIN="$PROJECT_DIR/results/ftp_data_adapter"
ADAPTER_LOG="$PROJECT_DIR/results/ftp_data_adapter.log"
FTP_CONTROL_PORT="${SPO8_FTP_CONTROL_PORT:-2121}"
VM_CONTROL_PORT="${SPO8_VM_CONTROL_PORT:-3121}"
FTP_DATA_PORT="${SPO8_FTP_DATA_PORT:-2020}"
VM_DATA_PORT="${SPO8_VM_DATA_PORT:-3020}"

mkdir -p "$PROJECT_DIR/results"
cd "$PROJECT_DIR"

if [ "$#" -eq 0 ]; then
    "${MAKE:-make}" asm
fi

cc -O2 -Wall -Wextra -pthread -o "$ADAPTER_BIN" "$SCRIPT_DIR/ftp_data_adapter.c"
rm -f "$ADAPTER_LOG"

"$ADAPTER_BIN" "$FTP_CONTROL_PORT" "$VM_CONTROL_PORT" "$FTP_DATA_PORT" "$VM_DATA_PORT" >"$ADAPTER_LOG" 2>&1 &
ADAPTER_PID=$!

cleanup() {
    if kill -0 "$ADAPTER_PID" 2>/dev/null; then
        kill "$ADAPTER_PID" 2>/dev/null || true
        sleep 1
        kill -9 "$ADAPTER_PID" 2>/dev/null || true
        wait "$ADAPTER_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

echo "ftp-адаптер=$ADAPTER_PID" >&2
echo "лог-ftp-адаптера=$ADAPTER_LOG" >&2
echo "FileZilla: хост 127.0.0.1, порт $FTP_CONTROL_PORT, обычный FTP без TLS, пассивный режим. PASV-порт данных: $FTP_DATA_PORT." >&2
echo "Адаптер принимает повторные control-подключения FileZilla и последовательно передаёт команды в FTP-сервер VM." >&2
echo "Пассивный data-поток идёт через второй SimplePipe и транспортный мост; Btrfs-данные читает только VM." >&2
echo "Для больших файлов поставьте timeout FileZilla не меньше 120 секунд." >&2

RT_DEVICES_FILE="$PROJECT_DIR/devices_filezilla.xml" \
"$SCRIPT_DIR/run_remote_interactive.sh" \
    "${1:-$PROJECT_DIR/results/btrfs_ftp_demo.asm}" \
    "${2:-$PROJECT_DIR/results/btrfs_ftp_demo.ptptb}"
