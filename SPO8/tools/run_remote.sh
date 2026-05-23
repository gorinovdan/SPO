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
RT_EXEC_TASK="${RT_EXEC_TASK:-ExecuteBinaryWithIo}"
RT_HOST="${RT_HOST:-5.19.208.160}"
RT_PORT="${RT_PORT:-10001}"
RT_REMOTE_FLAGS="${RT_REMOTE_FLAGS:--sh $RT_HOST -sp $RT_PORT -okssl}"
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

run_with_timeout_stdin() {
    out_file=$1
    in_file=$2
    shift 2
    rm -f "$out_file"
    "$@" <"$in_file" >"$out_file" 2>&1 &
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

rt_manager() {
    # RT_REMOTE_FLAGS намеренно разбивается shell на слова: так можно передать
    # несколько ключей CLI, например "-ws -wsslib" или "-sh host -sp 10001 -okssl".
    mono "$EXE" $RT_REMOTE_FLAGS "$@"
}

ASM_FILE=${1:-"$PROJECT_DIR/results/btrfs_ftp_demo.asm"}
INPUT_FILE=${2:-"$ROOT_DIR/tools/vm_input.txt"}
RUN_MODE=${3:-exec}
BIN_FILE=${4:-"$PROJECT_DIR/results/btrfs_ftp_demo.ptptb"}
STDOUT_FILE=${5:-"$PROJECT_DIR/results/btrfs_ftp_demo.stdout.txt"}
TRACE_FILE=${6:-"$PROJECT_DIR/results/btrfs_ftp_demo.trace.txt"}

mkdir -p "$(dirname -- "$BIN_FILE")"
mkdir -p "$(dirname -- "$STDOUT_FILE")"
mkdir -p "$(dirname -- "$TRACE_FILE")"

REMOTE_TMP_DIR="${TMPDIR:-/tmp}"
ASM_OUTPUT_FILE="$REMOTE_TMP_DIR/spo8_remote_asm_$$.txt"
RUN_OUTPUT_FILE="$REMOTE_TMP_DIR/spo8_remote_run_$$.txt"
GET_OUTPUT_FILE="$REMOTE_TMP_DIR/spo8_remote_get_$$.txt"
trap 'rm -f "$ASM_OUTPUT_FILE" "$RUN_OUTPUT_FILE" "$GET_OUTPUT_FILE" "${TRACE_FILE}.tmp"' EXIT

if [ ! -f "$INPUT_FILE" ]; then
    printf '0\n' > "$INPUT_FILE"
fi

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

if [ "$RUN_MODE" = "exec" ]; then
    if [ "$RT_EXEC_TASK" = "ExecuteBinaryWithIo" ]; then
        # SimplePipe с PipeSpec=stdio требует интерактивного канала. В этом режиме
        # RemoteTasks печатает поток VM напрямую; stdout.txt не является артефактом
        # задачи, поэтому проверяемым stdout становится вывод менеджера.
        run_with_timeout_stdin "$STDOUT_FILE" "$INPUT_FILE" \
            rt_manager -ip -s "$RT_EXEC_TASK" \
            stdinRegStName rin_s \
            stdoutRegStName rout_s \
            definitionFile "$TARGET_FILE" \
            archName "$ARCH" \
            binaryFileToRun "$BIN_FILE" \
            codeRamBankName code \
            ipRegStorageName ip_s \
            finishMnemonicName ret \
            devices.xml "$DEVICES_FILE" || {
            cat "$STDOUT_FILE" >&2
            exit 1
        }
        RUN_ID="interactive-pipe"
        printf 'assemble=%s\nrun=%s\n' "$ASM_ID" "$RUN_ID"
        exit 0
    else
        run_with_timeout "$RUN_OUTPUT_FILE" \
            rt_manager -id -w -s "$RT_EXEC_TASK" \
            stdinRegStName rin_s \
            stdoutRegStName rout_s \
            inputFile "$INPUT_FILE" \
            definitionFile "$TARGET_FILE" \
            archName "$ARCH" \
            binaryFileToRun "$BIN_FILE" \
            codeRamBankName code \
            ipRegStorageName ip_s \
            finishMnemonicName ret \
            devices.xml "$DEVICES_FILE" || {
            cat "$RUN_OUTPUT_FILE" >&2
            exit 1
        }
    fi
else
    run_with_timeout "$RUN_OUTPUT_FILE" \
        rt_manager -id -w -s MachineDebugBinary \
        definitionFile "$TARGET_FILE" \
        archName "$ARCH" \
        binaryFileToRun "$BIN_FILE" \
        codeRamBankName code \
        ipRegStorageName ip_s \
        finishMnemonicName ret \
        devices.xml "$DEVICES_FILE" || {
        cat "$RUN_OUTPUT_FILE" >&2
        exit 1
    }
fi
RUN_OUTPUT=$(cat "$RUN_OUTPUT_FILE")
RUN_ID=$(printf '%s' "$RUN_OUTPUT" | grep -Eo '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' | head -n 1)

if [ -z "$RUN_ID" ]; then
    echo "Задача Execute завершилась с ошибкой" >&2
    exit 1
fi

if [ "$RUN_MODE" = "exec" ]; then
    TRACE_TMP="${TRACE_FILE}.tmp"
    rm -f "$TRACE_TMP"
    if run_with_timeout "$GET_OUTPUT_FILE" \
        rt_manager -g "$RUN_ID" -r trace.txt -o "$TRACE_TMP" && [ -s "$TRACE_TMP" ]; then
        mv "$TRACE_TMP" "$TRACE_FILE"
    else
        rm -f "$TRACE_TMP"
    fi
fi
run_with_timeout "$GET_OUTPUT_FILE" \
    rt_manager -g "$RUN_ID" -r stdout.txt -o "$STDOUT_FILE" || {
    cat "$GET_OUTPUT_FILE" >&2
    exit 1
}

if [ ! -s "$STDOUT_FILE" ]; then
    echo "RemoteTasks did not return stdout.txt for run $RUN_ID" >&2
    exit 1
fi

printf 'assemble=%s\nrun=%s\n' "$ASM_ID" "$RUN_ID"
