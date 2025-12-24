SPO3 Report

Part 3. Data structures
- CFG_Subprogram (cfg/cfg.h): name, signature, params (name/type/size), CFG graph.
- LC_Program (codegen/linear_code.h): constants, data items, code blocks.
- LC_DataItem: data element name, kind (const/var), literal value or size.
- LC_Instruction: mnemonic + operand list.
- LC_CodeBlock: named block with ordered instruction list.

Part 4. Linear code module
Interface
- lc_generate_program(const CFG_Analysis*): builds LC_Program from CFG analysis.
- lc_write_assembly(const LC_Program*, const char*): emits .const/.data/.code sections.

Implementation notes
- CFG traversal uses SCC-based topological order to respect cycles while starting from entry.
- Each subprogram stores parameters (reverse order), then emits ENTER/LEAVE/RET prologue/epilogue.
- ENTER uses total local byte size; LEAVE cleans the operand stack and preserves the return value.
- Return value is loaded from `result` (or function name) when present, otherwise 0.
- Array parameters are treated as references and passed as addresses.
- Array sizes are inferred from indexed accesses; non-constant indices reserve a default of 64 elements.
- Jumps target block labels built from subprogram names and CFG node ids.

Part 5. Examples
Source program
- tests/spo3_demo.txt
- tests/array_demo.txt

Generated assembly listing
- results/output.asm (produced by ./tools/run_vm.sh)
- results/array_demo.asm (produced by ./tools/run_vm.sh)

VM execution output
- Running ./tools/run_vm_tests.sh prints: OK
- Running ./tools/run_vm.sh ./tests/array_demo.txt prints:
```
5
4
```

Source example (array_demo.txt)
```
def main()
    a = 2;
    b = 3;
    arr[a + b] = 5;
    arr[1, 3, 2] = 4;
    x = arr[a + b];
    y = arr[1, 3, 2];
    print(x);
    print(y);
end
```

Assembly excerpt (array_demo.asm)
```
main:
  ENTER 272
  ...
  PUSH_ADDR v_main_arr
  LOAD v_main_a
  LOAD v_main_b
  ADD
  INDEX
  PUSH_CONST k2
  STORE_IND
```

Additional artifacts
- VM description: vm/spec.md, vm/spec.json
- Instruction coverage listing: tests/vm_instructions.asm
