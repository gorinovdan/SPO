#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ROOT_DIR=$(CDPATH= cd -- "$PROJECT_DIR/.." && pwd)

EXE="$ROOT_DIR/tools/Portable.RemoteTasks.Manager.exe"
TARGET_FILE="$PROJECT_DIR/spo8.target.pdsl"
DEVICES_FILE="${RT_DEVICES_FILE:-$PROJECT_DIR/devices.xml}"
ARCH="${RT_ARCH:-vm32}"
LOGIN="${RT_LOGIN:-338960}"
PASSWORD="${RT_PASSWORD:-550fdf73-65b4-4e66-a0b6-6579cb1336a4}"
RT_TIMEOUT="${RT_TIMEOUT:-120}"
RT_HOST="${RT_HOST:-5.19.208.160}"
RT_PORT="${RT_PORT:-10001}"
RT_REMOTE_FLAGS="${RT_REMOTE_FLAGS:--sh $RT_HOST -sp $RT_PORT -okssl}"
RT_TASK_LIST_RANGE="${RT_TASK_LIST_RANGE:-0..5}"
RT_TASK_ID_DELAY="${RT_TASK_ID_DELAY:-3}"
export Portable_RemoteTasks_Manager_Login="$LOGIN"
export Portable_RemoteTasks_Manager_Password="$PASSWORD"

if ! command -v mono >/dev/null 2>&1; then
    echo "mono не найден; установите Mono для запуска Portable.RemoteTasks.Manager.exe" >&2
    exit 1
fi

if [ ! -f "$EXE" ]; then
    echo "Исполняемый файл RemoteTasks не найден: $EXE" >&2
    exit 1
fi

rt_manager() {
    # RT_REMOTE_FLAGS намеренно разбивается shell на слова: так можно передать
    # несколько ключей CLI, например "-ws -wsslib" или "-sh host -sp 10001 -okssl".
    mono "$EXE" $RT_REMOTE_FLAGS "$@"
}

run_with_timeout() {
    out_file=$1
    shift
    rm -f "$out_file"
    "$@" >"$out_file" 2>&1 &
    pid=$!
    elapsed=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$elapsed" -ge "$RT_TIMEOUT" ]; then
            kill "$pid" 2>/dev/null || true
            sleep 1
            kill -9 "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            echo "Команда RemoteTasks превысила лимит ${RT_TIMEOUT} с: $*" >&2
            if [ -s "$out_file" ]; then
                cat "$out_file" >&2
            fi
            return 124
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    wait "$pid"
}

print_recent_interactive_task() {
    rt_manager -l "$RT_TASK_LIST_RANGE" | awk '
        BEGIN { keep = 0; printed = 0 }
        /^[0-9]+: task ExecuteBinaryWithIo id / && printed == 0 {
            keep = 1
            printed = 1
            print
            next
        }
        keep == 1 && /^$/ {
            print
            keep = 0
            next
        }
        keep == 1 {
            print
        }
    '
}

if [ "${1:-}" = "--list" ]; then
    print_recent_interactive_task
    exit 0
fi

ASM_FILE=${1:-"$PROJECT_DIR/results/btrfs_ftp_demo.asm"}
BIN_FILE=${2:-"$PROJECT_DIR/results/btrfs_ftp_demo.ptptb"}

mkdir -p "$(dirname -- "$BIN_FILE")"

REMOTE_TMP_DIR="${TMPDIR:-/tmp}"
ASM_OUTPUT_FILE="$REMOTE_TMP_DIR/spo8_remote_interactive_asm_$$.txt"
GET_OUTPUT_FILE="$REMOTE_TMP_DIR/spo8_remote_interactive_get_$$.txt"
trap 'rm -f "$ASM_OUTPUT_FILE" "$GET_OUTPUT_FILE"' EXIT

run_with_timeout "$ASM_OUTPUT_FILE" \
    rt_manager -id -w -s Assemble \
    definitionFile "$TARGET_FILE" \
    archName "$ARCH" \
    asmListing "$ASM_FILE" || {
    cat "$ASM_OUTPUT_FILE" >&2
    exit 1
}
ASM_OUTPUT=$(cat "$ASM_OUTPUT_FILE")
ASM_ID=$(printf '%s' "$ASM_OUTPUT" | grep -Eo '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' | head -n 1)

if [ -z "$ASM_ID" ]; then
    echo "Задача Assemble завершилась с ошибкой" >&2
    exit 1
fi

run_with_timeout "$GET_OUTPUT_FILE" \
    rt_manager -g "$ASM_ID" -r out.ptptb -o "$BIN_FILE" || {
    cat "$GET_OUTPUT_FILE" >&2
    exit 1
}

echo "assemble=$ASM_ID" >&2
echo "binary=$BIN_FILE" >&2
echo "devices=$DEVICES_FILE" >&2
echo "Задача RemoteTasks ExecuteBinaryWithIo с pipe будет показана ниже после запуска." >&2
echo "Дождитесь строки 'Запись задачи RemoteTasks', если нужно показать id задачи." >&2
if [ "$(basename -- "$DEVICES_FILE")" = "devices_filezilla.xml" ]; then
    echo "Подключите FTP-клиент к 127.0.0.1:2121: обычный FTP без TLS, пассивный режим. PASV-порт данных: 2020." >&2
    echo "Управляющий SimplePipe VM подключён к внутреннему порту адаптера 3121; повторные control-сеансы FileZilla принимает адаптер." >&2
    echo "Для больших файлов задайте timeout FileZilla не меньше 120 секунд." >&2
else
    echo "Затем вводите FTP-команды через SimplePipe: USER anonymous, PASS x, PWD, LIST, CWD docs, RETR info.txt, COPY docs, QUIT." >&2
fi
echo >&2

(
    sleep "$RT_TASK_ID_DELAY"
    echo >&2
    echo "Запись задачи RemoteTasks:" >&2
    print_recent_interactive_task >&2 || true
    echo "Для обновления id/состояния задачи выполните 'make remote-tasks' в другом терминале." >&2
    echo >&2
) &
TASK_LIST_PID=$!

rt_manager -ip -s ExecuteBinaryWithIo \
    stdinRegStName rin_s \
    stdoutRegStName rout_s \
    definitionFile "$TARGET_FILE" \
    archName "$ARCH" \
    binaryFileToRun "$BIN_FILE" \
    codeRamBankName code \
    ipRegStorageName ip_s \
    finishMnemonicName ret \
    devices.xml "$DEVICES_FILE"
RUN_STATUS=$?

wait "$TASK_LIST_PID" 2>/dev/null || true
exit "$RUN_STATUS"
