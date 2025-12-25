; SPO3 linear code listing
; VM: stack-based, memory banks: code, const_pool, data_mem, stack_mem

[section const_pool]
k0: DD 3
k1: DB "Resilt of math op. is "
k2: DD 225
k3: DD 2
k4: DD 0
k5: DD 1
k6: DD 5
k7: DD 100
k8: DD 50
k9: DD 1000

[section data_mem]
v_calc_x: DD 0
v_calc_a: DD 0
v_calc_b: DD 0
v_calc_y: DD 0
v_calc_res: DD 0
v_condition_a: DD 0
v_condition_b: DD 0
v_condition_result: DD 0
v_function_call_a: DD 0
v_function_call_b: DD 0
v_function_call_myArr: DD 0
v_function_call_res: DD 0
v_function_call_arr2: DD 0
v_blockTest_a: DD 0
v_blockTest_b: DD 0
v_blockTest_counter: DD 0
v_inline_func_arr: DD 0
v_inline_func_counter: DD 0
v_callTest_x: DD 0
v_loopTest_a: DD 0
v_loopTest_b: DD 0
v_repeatTest_a: DD 0

[section code]
calc:
  ENTER 5
  JMP calc_B2

calc_B2:
  LOAD v_calc_a
  LOAD v_calc_b
  PUSH_CONST k0
  MUL
  LOAD v_calc_a
  LOAD v_calc_a
  REM
  DIV
  SUB
  STORE v_calc_x
  JMP calc_B3

calc_B3:
  PUSH_CONST k1
  STORE v_calc_y
  JMP calc_B4

calc_B4:
  LOAD v_calc_x
  LOAD v_calc_y
  ADD
  STORE v_calc_res
  JMP calc_exit

calc_exit:
  LEAVE
  RET

condition:
  ENTER 3
  JMP condition_B2

condition_B2:
  LOAD v_condition_a
  LOAD v_condition_b
  GE
  JZ condition_B7
  JMP condition_B3

condition_B3:
  LOAD v_condition_a
  LOAD v_condition_b
  GT
  JZ condition_B5
  JMP condition_B4

condition_B5:
  PUSH_CONST k2
  POP
  JMP condition_B6

condition_B4:
  PUSH_CONST k2
  NEG
  POP
  JMP condition_B6

condition_B6:
  JMP condition_B7

condition_B7:
  JMP condition_B8

condition_B8:
  LOAD v_condition_result
  POP
  JMP condition_exit

condition_exit:
  LEAVE
  RET

function_call:
  ENTER 5
  JMP function_call_B2

function_call_B2:
  PUSH_CONST k3
  STORE v_function_call_a
  JMP function_call_B3

function_call_B3:
  PUSH_CONST k0
  STORE v_function_call_b
  JMP function_call_B4

function_call_B4:
  LOAD v_function_call_myArr
  POP
  JMP function_call_B5

function_call_B5:
  PUSH_ADDR v_function_call_myArr
  PUSH_CONST k4
  INDEX
  PUSH_CONST k4
  STORE_IND
  JMP function_call_B6

function_call_B6:
  PUSH_ADDR v_function_call_myArr
  PUSH_CONST k5
  INDEX
  PUSH_CONST k5
  STORE_IND
  JMP function_call_B7

function_call_B7:
  PUSH_ADDR v_function_call_myArr
  LOAD v_function_call_a
  LOAD v_function_call_b
  ADD
  INDEX
  PUSH_CONST k6
  STORE_IND
  JMP function_call_B8

function_call_B8:
  PUSH_CONST k7
  PUSH_ADDR v_function_call_myArr
  LOAD v_function_call_a
  LOAD v_function_call_b
  ADD
  INDEX
  LOAD_IND
  LOAD v_function_call_a
  LOAD v_function_call_b
  ADD
  MUL
  ADD
  STORE v_function_call_res
  JMP function_call_B9

function_call_B9:
  PUSH_ADDR v_function_call_myArr
  PUSH_CONST k3
  PUSH_CONST k6
  RANGE_OP
  INDEX
  LOAD_IND
  STORE v_function_call_arr2
  JMP function_call_exit

function_call_exit:
  LEAVE
  RET

blockTest:
  ENTER 3
  JMP blockTest_B2

blockTest_B2:
  PUSH_CONST k3
  STORE v_blockTest_a
  JMP blockTest_B3

blockTest_B3:
  PUSH_CONST k0
  STORE v_blockTest_b
  JMP blockTest_B4

blockTest_B4:
  LOAD v_blockTest_a
  LOAD v_blockTest_b
  EQ
  JZ blockTest_B6
  JMP blockTest_B5

blockTest_B5:
  PUSH_CONST k7
  PUSH_CONST k8
  ADD
  POP
  JMP blockTest_B6

blockTest_B6:
  JMP blockTest_B9

blockTest_B9:
  LOAD v_blockTest_b
  NEG
  PUSH_CONST k3
  ADD
  POP
  JMP blockTest_B8

blockTest_B8:
  LOAD v_blockTest_a
  LOAD v_blockTest_b
  LT
  JZ blockTest_B7
  JMP blockTest_B9

blockTest_B7:
  JMP blockTest_B10

blockTest_B10:
  PUSH_CONST k4
  STORE v_blockTest_counter
  JMP blockTest_B11

blockTest_B11:
  CALL inline_func, 0
  POP
  JMP blockTest_exit

blockTest_exit:
  LEAVE
  RET

inline_func:
  ENTER 2
  JMP inline_func_B2

inline_func_B2:
  PUSH_ADDR v_inline_func_arr
  PUSH_CONST k5
  INDEX
  PUSH_CONST k0
  INDEX
  PUSH_CONST k3
  INDEX
  LOAD_IND
  PUSH_CONST k6
  LT
  JZ inline_func_B3
  JMP inline_func_B4

inline_func_B3:
  JMP inline_func_exit

inline_func_exit:
  LEAVE
  RET

inline_func_B4:
  LOAD v_inline_func_counter
  PUSH_CONST k5
  ADD
  STORE v_inline_func_counter
  JMP inline_func_B5

inline_func_B5:
  PUSH_ADDR v_inline_func_arr
  PUSH_CONST k5
  INDEX
  PUSH_CONST k0
  INDEX
  PUSH_CONST k3
  INDEX
  PUSH_ADDR v_inline_func_arr
  PUSH_CONST k5
  INDEX
  PUSH_CONST k0
  INDEX
  PUSH_CONST k3
  INDEX
  LOAD_IND
  PUSH_CONST k5
  ADD
  STORE_IND
  JMP inline_func_B2

callTest:
  ENTER 1
  JMP callTest_B2

callTest_B2:
  PUSH_CONST k5
  PUSH_CONST k3
  PUSH_CONST k0
  CALL calc, 3
  STORE v_callTest_x
  JMP callTest_exit

callTest_exit:
  LEAVE
  RET

loopTest:
  ENTER 2
  JMP loopTest_B2

loopTest_B2:
  LOAD v_loopTest_a
  LOAD v_loopTest_b
  LT
  JZ loopTest_B3
  JMP loopTest_B4

loopTest_B3:
  JMP loopTest_B5

loopTest_B5:
  LOAD v_loopTest_a
  LOAD v_loopTest_b
  LT
  JZ loopTest_B7
  JMP loopTest_B6

loopTest_B7:
  LOAD v_loopTest_a
  PUSH_CONST k5
  ADD
  STORE v_loopTest_a
  JMP loopTest_B5

loopTest_B6:
  JMP loopTest_exit

loopTest_exit:
  LEAVE
  RET

loopTest_B4:
  LOAD v_loopTest_a
  PUSH_CONST k5
  ADD
  STORE v_loopTest_a
  JMP loopTest_B2

repeatTest:
  ENTER 1
  JMP repeatTest_B2

repeatTest_B2:
  PUSH_CONST k4
  STORE v_repeatTest_a
  JMP repeatTest_B5

repeatTest_B5:
  LOAD v_repeatTest_a
  PUSH_CONST k5
  ADD
  STORE v_repeatTest_a
  JMP repeatTest_B4

repeatTest_B4:
  LOAD v_repeatTest_a
  PUSH_CONST k9
  EQ
  JZ repeatTest_B5
  JMP repeatTest_B3

repeatTest_B3:
  JMP repeatTest_exit

repeatTest_exit:
  LEAVE
  RET

