#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASM_FILE="${ROOT_DIR}/tests/vm_instructions.asm"
BIN_FILE="${ROOT_DIR}/results/vm_instructions.bin"
SPEC_FILE="${ROOT_DIR}/vm/spec.json"

mkdir -p "${ROOT_DIR}/results"
python3 "${ROOT_DIR}/tools/asm.py" -s "${SPEC_FILE}" -i "${ASM_FILE}" -o "${BIN_FILE}"
python3 "${ROOT_DIR}/tools/vm.py" -s "${SPEC_FILE}" -i "${BIN_FILE}"
