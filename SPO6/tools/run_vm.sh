#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_FILE="${1:-${ROOT_DIR}/tests/spo3_demo.txt}"
ASM_FILE="${2:-${ROOT_DIR}/results/output.asm}"
BIN_FILE="${3:-${ROOT_DIR}/results/output.bin}"
SPEC_FILE="${ROOT_DIR}/vm/spec.json"

mkdir -p "$(dirname "${ASM_FILE}")"

"${ROOT_DIR}/app" -o "${ASM_FILE}" "${INPUT_FILE}"
python3 "${ROOT_DIR}/tools/asm.py" -s "${SPEC_FILE}" -i "${ASM_FILE}" -o "${BIN_FILE}"
python3 "${ROOT_DIR}/tools/vm.py" -s "${SPEC_FILE}" -i "${BIN_FILE}"
