#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export tool="${RT_TOOL:-mono ${repo_root}/tools/Portable.RemoteTasks.Manager.exe}"
export Portable_RemoteTasks_Manager_Login=338960
export Portable_RemoteTasks_Manager_Password=550fdf73-65b4-4e66-a0b6-6579cb1336a4

listing=$1
binary=$2
devices="${RT_DEVICES:-${repo_root}/SPO6/devices.xml}"
targetDef="${RT_TARGET:-${repo_root}/SPO6/spo6.target.pdsl}"
targetArch="${RT_ARCH:-vm32}"

rm -f "$binary"

ASM_OUTPUT=$($tool -ws -wsslib -id -w -s Assemble definitionFile "$targetDef" archName "$targetArch" asmListing "$listing" 2>&1) || {
    printf '%s\n' "$ASM_OUTPUT" >&2
    exit 1
}
ASM_ID=$(printf '%s' "$ASM_OUTPUT" | grep -Eo '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -n1 || true)
if [ -z "$ASM_ID" ]; then
    printf '%s\n' "$ASM_OUTPUT" >&2
    exit 1
fi

$tool -ws -wsslib -g "$ASM_ID" -r stdout.txt

$tool -ws -wsslib -g "$ASM_ID" -r stderr.txt

$tool -ws -wsslib -g "$ASM_ID" -r out.ptptb -o "$binary"

$tool -ws -wsslib -il -s DebugBinaryWithIo stdinRegStName rin_s stdoutRegStName rout_s definitionFile "$targetDef" archName "$targetArch" binaryFileToRun "$binary" codeRamBankName code ipRegStorageName ip_s finishMnemonicName ret devices.xml "$devices"
