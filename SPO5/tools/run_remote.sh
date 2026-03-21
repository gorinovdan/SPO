#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ROOT_DIR=$(CDPATH= cd -- "$PROJECT_DIR/.." && pwd)

EXE="$ROOT_DIR/tools/Portable.RemoteTasks.Manager.exe"
TARGET_FILE="$PROJECT_DIR/spo5.target.pdsl"
ARCH="${RT_ARCH:-vm32}"
LOGIN="${RT_LOGIN:-338960}"
PASSWORD="${RT_PASSWORD:-550fdf73-65b4-4e66-a0b6-6579cb1336a4}"

if ! command -v mono >/dev/null 2>&1; then
    echo "mono not found; install Mono to run Portable.RemoteTasks.Manager.exe" >&2
    exit 1
fi

if [ ! -f "$EXE" ]; then
    echo "RemoteTasks executable not found: $EXE" >&2
    exit 1
fi

ASM_FILE=${1:-"$PROJECT_DIR/results/types_demo.asm"}
INPUT_FILE=${2:-"$ROOT_DIR/tools/vm_input.txt"}
RUN_MODE=${3:-exec}
BIN_FILE=${4:-"$PROJECT_DIR/results/types_demo.remote.ptptb"}
STDOUT_FILE=${5:-"$PROJECT_DIR/results/types_demo.remote.stdout.txt"}
TRACE_FILE=${6:-"$PROJECT_DIR/results/types_demo.remote.trace.txt"}

mkdir -p "$(dirname -- "$BIN_FILE")"
mkdir -p "$(dirname -- "$STDOUT_FILE")"
mkdir -p "$(dirname -- "$TRACE_FILE")"

if [ ! -f "$INPUT_FILE" ]; then
    printf '0\n' > "$INPUT_FILE"
fi

ASM_ID=$(
    mono "$EXE" -ul "$LOGIN" -up "$PASSWORD" -s Assemble -id -w \
        definitionFile "$TARGET_FILE" \
        archName "$ARCH" \
        asmListing "$ASM_FILE"
)
ASM_ID=$(printf '%s' "$ASM_ID" | grep -Eo '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' | head -n 1)

if [ -z "$ASM_ID" ]; then
    echo "Assemble task failed" >&2
    exit 1
fi

mono "$EXE" -ul "$LOGIN" -up "$PASSWORD" -g "$ASM_ID" -r out.ptptb -o "$BIN_FILE"

if [ "$RUN_MODE" = "exec" ]; then
    RUN_ID=$(
        mono "$EXE" -ul "$LOGIN" -up "$PASSWORD" -s ExecuteBinaryWithInput -id -w \
            stdinRegStName rin_s \
            stdoutRegStName rout_s \
            inputFile "$INPUT_FILE" \
            definitionFile "$TARGET_FILE" \
            archName "$ARCH" \
            binaryFileToRun "$BIN_FILE" \
            codeRamBankName code \
            ipRegStorageName ip_s \
            finishMnemonicName ret
    )
else
    RUN_ID=$(
        mono "$EXE" -ul "$LOGIN" -up "$PASSWORD" -s MachineDebugBinary -id -w \
            definitionFile "$TARGET_FILE" \
            archName "$ARCH" \
            binaryFileToRun "$BIN_FILE" \
            codeRamBankName code \
            ipRegStorageName ip_s \
            finishMnemonicName ret
    )
fi
RUN_ID=$(printf '%s' "$RUN_ID" | grep -Eo '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' | head -n 1)

if [ -z "$RUN_ID" ]; then
    echo "Execute task failed" >&2
    exit 1
fi

if [ "$RUN_MODE" = "exec" ]; then
    mono "$EXE" -ul "$LOGIN" -up "$PASSWORD" -g "$RUN_ID" -r trace.txt -o "$TRACE_FILE"
fi
mono "$EXE" -ul "$LOGIN" -up "$PASSWORD" -g "$RUN_ID" -r stdout.txt -o "$STDOUT_FILE"

printf 'assemble=%s\nrun=%s\n' "$ASM_ID" "$RUN_ID"
