#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ROOT_DIR=$(CDPATH= cd -- "$PROJECT_DIR/.." && pwd)

EXE="$ROOT_DIR/tools/Portable.RemoteTasks.Manager.exe"
TARGET_FILE="$PROJECT_DIR/spo7.target.pdsl"
DEVICES_FILE="$PROJECT_DIR/devices.xml"
ARCH="${RT_ARCH:-vm32}"
LOGIN="${RT_LOGIN:-338960}"
PASSWORD="${RT_PASSWORD:-550fdf73-65b4-4e66-a0b6-6579cb1336a4}"
export Portable_RemoteTasks_Manager_Login="$LOGIN"
export Portable_RemoteTasks_Manager_Password="$PASSWORD"

if ! command -v mono >/dev/null 2>&1; then
    echo "mono not found; install Mono to run Portable.RemoteTasks.Manager.exe" >&2
    exit 1
fi

if [ ! -f "$EXE" ]; then
    echo "RemoteTasks executable not found: $EXE" >&2
    exit 1
fi

ASM_FILE=${1:-"$PROJECT_DIR/results/sql_pipeline_demo.asm"}
INPUT_FILE=${2:-"$ROOT_DIR/tools/vm_input.txt"}
RUN_MODE=${3:-exec}
BIN_FILE=${4:-"$PROJECT_DIR/results/sql_pipeline_demo.ptptb"}
STDOUT_FILE=${5:-"$PROJECT_DIR/results/sql_pipeline_demo.stdout.txt"}
TRACE_FILE=${6:-"$PROJECT_DIR/results/sql_pipeline_demo.trace.txt"}

mkdir -p "$(dirname -- "$BIN_FILE")"
mkdir -p "$(dirname -- "$STDOUT_FILE")"
mkdir -p "$(dirname -- "$TRACE_FILE")"

if [ ! -f "$INPUT_FILE" ]; then
    printf '0\n' > "$INPUT_FILE"
fi

ASM_OUTPUT=$(
    mono "$EXE" -ws -wsslib -id -w -s Assemble \
        definitionFile "$TARGET_FILE" \
        archName "$ARCH" \
        asmListing "$ASM_FILE"
) || {
    printf '%s\n' "$ASM_OUTPUT" >&2
    exit 1
}
ASM_ID=$(printf '%s' "$ASM_OUTPUT" | grep -Eo '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' | head -n 1)

if [ -z "$ASM_ID" ]; then
    echo "Assemble task failed" >&2
    exit 1
fi

mono "$EXE" -ws -wsslib -g "$ASM_ID" -r out.ptptb -o "$BIN_FILE"

if [ "$RUN_MODE" = "exec" ]; then
    RUN_OUTPUT=$(
        mono "$EXE" -ws -wsslib -id -w -s ExecuteBinaryWithIo \
            stdinRegStName rin_s \
            stdoutRegStName rout_s \
            inputFile "$INPUT_FILE" \
            definitionFile "$TARGET_FILE" \
            archName "$ARCH" \
            binaryFileToRun "$BIN_FILE" \
            codeRamBankName code \
            ipRegStorageName ip_s \
            finishMnemonicName ret \
            devices.xml "$DEVICES_FILE"
    ) || {
        printf '%s\n' "$RUN_OUTPUT" >&2
        exit 1
    }
else
    RUN_OUTPUT=$(
        mono "$EXE" -ws -wsslib -id -w -s MachineDebugBinary \
            definitionFile "$TARGET_FILE" \
            archName "$ARCH" \
            binaryFileToRun "$BIN_FILE" \
            codeRamBankName code \
            ipRegStorageName ip_s \
            finishMnemonicName ret \
            devices.xml "$DEVICES_FILE"
    ) || {
        printf '%s\n' "$RUN_OUTPUT" >&2
        exit 1
    }
fi
RUN_ID=$(printf '%s' "$RUN_OUTPUT" | grep -Eo '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' | head -n 1)

if [ -z "$RUN_ID" ]; then
    echo "Execute task failed" >&2
    exit 1
fi

if [ "$RUN_MODE" = "exec" ]; then
    TRACE_TMP="${TRACE_FILE}.tmp"
    rm -f "$TRACE_TMP"
    if mono "$EXE" -ws -wsslib -g "$RUN_ID" -r trace.txt -o "$TRACE_TMP" >/dev/null 2>&1 && [ -s "$TRACE_TMP" ]; then
        mv "$TRACE_TMP" "$TRACE_FILE"
    else
        rm -f "$TRACE_TMP"
    fi
fi
mono "$EXE" -ws -wsslib -g "$RUN_ID" -r stdout.txt -o "$STDOUT_FILE" >/dev/null 2>&1 || : > "$STDOUT_FILE"

printf 'assemble=%s\nrun=%s\n' "$ASM_ID" "$RUN_ID"
