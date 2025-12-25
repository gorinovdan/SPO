SPO3 VM (stack-based)

Overview
- Word size: 4 bytes
- Memory banks: code, constants, data_mem, stack_mem
- Registers: IP (instruction pointer), SP (stack pointer), BP (base pointer), IO (hidden IO port)

Memory model
- code: linear array of bytecode instructions
- constants: typed constant pool (int/char/bool/string)
- data_mem: mutable memory for variables and arrays (per-call frame)
- stack_mem: evaluation stack for operands and temporary values (SP/BP tracked)

Calling convention
- Arguments are pushed by the caller (left-to-right order).
- The callee prologue stores arguments to parameter variables using STORE (reverse order).
- ENTER sets BP after arguments are removed; each CALL creates a fresh data frame.
- LEAVE cleans the operand stack back to BP and preserves the return value.
- RET returns to the last CALL site and leaves the top-of-stack value as the result (0 if none).

IO model
- IO is a hidden register storing the current port number.
- SET_PORT pops a value from the stack and writes it to IO.
- OUT pops a value and writes it to the current IO port.
- IN reads a value from the current IO port and pushes it on the stack.

Instruction summary (mnemonics)
Data movement and constants
- PUSH_CONST const_label
- PUSH_ADDR data_label
- LOAD data_label
- STORE data_label
- LOAD_IND
- STORE_IND
- POP

Arithmetic and logic
- ADD, SUB, MUL, DIV, REM, NEG
- LT, GT, LE, GE, EQ, NE
- AND_OP, OR_OP

Control flow
- JMP label
- JZ label
- CALL label, argc
- ENTER nlocals (bytes)
- LEAVE
- RET

Indexing
- RANGE_OP (start, end -> start)
- INDEX (base, index -> address)

IO
- SET_PORT
- IN
- OUT

Notes
- RANGE_OP is simplified to keep only the start index; INDEX uses word-sized elements (4 bytes).
- LOAD/STORE operate on declared data item sizes; LOAD_IND/STORE_IND operate on word size.
- Data frames are initialized from the program data template on each call.
- Addresses produced by PUSH_ADDR are frame-relative and are preserved across calls.
- Array parameters are passed by reference (address values stored in data slots).
