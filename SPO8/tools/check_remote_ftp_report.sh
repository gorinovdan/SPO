#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

HOST="${SPO8_FTP_HOST:-127.0.0.1}"
CONTROL_PORT="${SPO8_FTP_CONTROL_PORT:-2121}"
VM_CONTROL_PORT="${SPO8_VM_CONTROL_PORT:-3121}"
DATA_PORT="${SPO8_FTP_DATA_PORT:-2020}"
VM_DATA_PORT="${SPO8_VM_DATA_PORT:-3020}"
TIMEOUT="${SPO8_FTP_REPORT_TIMEOUT:-180}"

SERVER_LOG="$PROJECT_DIR/results/remote_filezilla_report_server.log"
REPORT_OUT="$PROJECT_DIR/results/remote_filezilla_report.md"
PID_FILE="$PROJECT_DIR/results/remote_filezilla_report_server.pid"

mkdir -p "$PROJECT_DIR/results"
rm -f "$SERVER_LOG" "$REPORT_OUT" "$PID_FILE"

cleanup() {
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            sleep 1
            kill -9 "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    fi
    if command -v lsof >/dev/null 2>&1; then
        pids=$(lsof -tiTCP:"$CONTROL_PORT" -tiTCP:"$VM_CONTROL_PORT" -tiTCP:"$DATA_PORT" -tiTCP:"$VM_DATA_PORT" 2>/dev/null | sort -u | tr '\n' ' ')
        if [ -n "$pids" ]; then
            kill $pids 2>/dev/null || true
            sleep 1
            kill -9 $pids 2>/dev/null || true
        fi
    fi
}
trap cleanup EXIT INT TERM

wait_listen() {
    port=$1
    waited=0
    while [ "$waited" -lt "$TIMEOUT" ]; do
        if command -v lsof >/dev/null 2>&1 &&
            lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
            return 0
        fi
        if ! kill -0 "$SERVER_PID" 2>/dev/null; then
            echo "Сервер RemoteTasks завершился до открытия порта $port" >&2
            cat "$SERVER_LOG" >&2 || true
            return 1
        fi
        sleep 1
        waited=$((waited + 1))
    done
    echo "Истёк таймаут ожидания LISTEN на $HOST:$port" >&2
    cat "$SERVER_LOG" >&2 || true
    return 1
}

RT_TASK_ID_DELAY="${RT_TASK_ID_DELAY:-5}" \
"$SCRIPT_DIR/run_remote_filezilla.sh" \
    "$PROJECT_DIR/results/btrfs_ftp_demo.asm" \
    "$PROJECT_DIR/results/btrfs_ftp_demo.ptptb" \
    >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!
echo "$SERVER_PID" > "$PID_FILE"

wait_listen "$CONTROL_PORT"
wait_listen "$DATA_PORT"

curl --fail --show-error --silent --disable-epsv \
    --retry 3 --retry-delay 1 --retry-connrefused \
    --max-time "$TIMEOUT" \
    --user anonymous:anonymous \
    "ftp://$HOST:$CONTROL_PORT/SPO8/report.md" \
    -o "$REPORT_OUT"

if ! grep -q "SPO8: Btrfs через RemoteTasks" "$REPORT_OUT"; then
    echo "FTP RETR /SPO8/report.md вернул неожиданные данные" >&2
    head -20 "$REPORT_OUT" >&2 || true
    exit 1
fi

echo "Проверка RETR /SPO8/report.md через RemoteTasks пройдена"
echo "control=$HOST:$CONTROL_PORT data=$HOST:$DATA_PORT"
echo "report=$REPORT_OUT"
wc -c "$REPORT_OUT"
