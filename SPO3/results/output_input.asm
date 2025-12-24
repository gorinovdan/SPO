; SPO3 linear code listing
; VM: stack-based, memory banks: code, constants, data, stack

.const
k0: .int 3
k1: .int 1
k2: .string "Resilt of math op. is "
k3: .int 0
k4: .int 225
k5: .int 2
k6: .int 5
k7: .int 100
k8: .int 50
k9: .int 1000

.data
v_calc_a: .word 0
v_calc_b: .word 0
v_calc_c: .word 0
v_calc_x: .word 0
v_calc_y: .word 0
v_calc_res: .word 0
v_condition_a: .word 0
v_condition_b: .word 0
v_condition_result: .word 0
v_function_call_a: .word 0
v_function_call_b: .word 0
v_function_call_myArr: .space 256
v_function_call_res: .word 0
v_function_call_arr2: .word 0
v_blockTest_a: .word 0
v_blockTest_b: .word 0
v_blockTest_counter: .word 0
v_inline_func_arr: .space 28
v_inline_func_counter: .word 0
v_callTest_tmp: .space 8
v_callTest_x: .word 0
v_loopTest_a: .word 0
v_loopTest_b: .word 0
v_repeatTest_a: .word 0
v_main_tmp: .space 8

.code
calc:
  STORE v_calc_c
  STORE v_calc_b
  STORE v_calc_a
  ENTER 24
  JMP calc_B2

calc_B2:
  LOAD v_calc_a
  LOAD v_calc_b
  PUSH_CONST k0
  MUL
  LOAD v_calc_a
  LOAD v_calc_a
  PUSH_CONST k1
  ADD
  REM
  PUSH_CONST k1
  ADD
  DIV
  SUB
  STORE v_calc_x
  JMP calc_B3

calc_B3:
  PUSH_CONST k2
  STORE v_calc_y
  JMP calc_B4

calc_B4:
  LOAD v_calc_x
  LOAD v_calc_y
  ADD
  STORE v_calc_res
  JMP calc_exit

calc_exit:
  PUSH_CONST k3
  LEAVE
  RET

condition:
  STORE v_condition_b
  STORE v_condition_a
  ENTER 12
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
  PUSH_CONST k4
  POP
  JMP condition_B6

condition_B4:
  PUSH_CONST k4
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
  LOAD v_condition_result
  LEAVE
  RET

function_call:
  ENTER 272
  JMP function_call_B2

function_call_B2:
  PUSH_CONST k5
  STORE v_function_call_a
  JMP function_call_B3

function_call_B3:
  PUSH_CONST k0
  STORE v_function_call_b
  JMP function_call_B4

function_call_B4:
  PUSH_ADDR v_function_call_myArr
  POP
  JMP function_call_B5

function_call_B5:
  PUSH_ADDR v_function_call_myArr
  PUSH_CONST k3
  INDEX
  PUSH_CONST k3
  STORE_IND
  JMP function_call_B6

function_call_B6:
  PUSH_ADDR v_function_call_myArr
  PUSH_CONST k1
  INDEX
  PUSH_CONST k1
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
  PUSH_CONST k5
  PUSH_CONST k6
  RANGE
  INDEX
  LOAD_IND
  STORE v_function_call_arr2
  JMP function_call_exit

function_call_exit:
  PUSH_CONST k3
  LEAVE
  RET

blockTest:
  ENTER 12
  JMP blockTest_B2

blockTest_B2:
  PUSH_CONST k5
  STORE v_blockTest_a
  JMP blockTest_B3

blockTest_B3:
  PUSH_CONST k5
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

blockTest_B8:
  LOAD v_blockTest_a
  LOAD v_blockTest_b
  LT
  JZ blockTest_B7
  JMP blockTest_B9

blockTest_B9:
  LOAD v_blockTest_b
  NEG
  PUSH_CONST k5
  ADD
  POP
  JMP blockTest_B8

blockTest_B7:
  JMP blockTest_B10

blockTest_B10:
  PUSH_CONST k3
  STORE v_blockTest_counter
  JMP blockTest_B11

blockTest_B11:
  CALL inline_func, 0
  POP
  JMP blockTest_exit

blockTest_exit:
  PUSH_CONST k3
  LEAVE
  RET

inline_func:
  ENTER 32
  JMP inline_func_B2

inline_func_B2:
  PUSH_ADDR v_inline_func_arr
  PUSH_CONST k1
  INDEX
  PUSH_CONST k0
  INDEX
  PUSH_CONST k5
  INDEX
  LOAD_IND
  PUSH_CONST k6
  LT
  JZ inline_func_B3
  JMP inline_func_B4

inline_func_B4:
  LOAD v_inline_func_counter
  PUSH_CONST k1
  ADD
  STORE v_inline_func_counter
  JMP inline_func_B5

inline_func_B5:
  PUSH_ADDR v_inline_func_arr
  PUSH_CONST k1
  INDEX
  PUSH_CONST k0
  INDEX
  PUSH_CONST k5
  INDEX
  PUSH_ADDR v_inline_func_arr
  PUSH_CONST k1
  INDEX
  PUSH_CONST k0
  INDEX
  PUSH_CONST k5
  INDEX
  LOAD_IND
  PUSH_CONST k1
  ADD
  STORE_IND
  JMP inline_func_B2

inline_func_B3:
  JMP inline_func_exit

inline_func_exit:
  PUSH_CONST k3
  LEAVE
  RET

callTest:
  ENTER 12
  JMP callTest_B2

callTest_B2:
  PUSH_ADDR v_callTest_tmp
  PUSH_CONST k3
  INDEX
  PUSH_CONST k3
  STORE_IND
  JMP callTest_B3

callTest_B3:
  PUSH_ADDR v_callTest_tmp
  PUSH_CONST k1
  INDEX
  PUSH_CONST k1
  STORE_IND
  JMP callTest_B4

callTest_B4:
  PUSH_CONST k1
  PUSH_CONST k5
  PUSH_ADDR v_callTest_tmp
  CALL calc, 3
  STORE v_callTest_x
  JMP callTest_exit

callTest_exit:
  PUSH_CONST k3
  LEAVE
  RET

loopTest:
  ENTER 8
  JMP loopTest_B2

loopTest_B2:
  PUSH_CONST k3
  STORE v_loopTest_a
  JMP loopTest_B3

loopTest_B3:
  PUSH_CONST k5
  STORE v_loopTest_b
  JMP loopTest_B4

loopTest_B4:
  LOAD v_loopTest_a
  LOAD v_loopTest_b
  LT
  JZ loopTest_B5
  JMP loopTest_B6

loopTest_B6:
  LOAD v_loopTest_a
  PUSH_CONST k1
  ADD
  STORE v_loopTest_a
  JMP loopTest_B4

loopTest_B5:
  JMP loopTest_B7

loopTest_B7:
  PUSH_CONST k3
  STORE v_loopTest_a
  JMP loopTest_B8

loopTest_B8:
  LOAD v_loopTest_a
  LOAD v_loopTest_b
  GE
  JZ loopTest_B10
  JMP loopTest_B9

loopTest_B10:
  LOAD v_loopTest_a
  PUSH_CONST k1
  ADD
  STORE v_loopTest_a
  JMP loopTest_B8

loopTest_B9:
  JMP loopTest_exit

loopTest_exit:
  PUSH_CONST k3
  LEAVE
  RET

repeatTest:
  ENTER 4
  JMP repeatTest_B2

repeatTest_B2:
  PUSH_CONST k3
  STORE v_repeatTest_a
  JMP repeatTest_B5

repeatTest_B4:
  LOAD v_repeatTest_a
  PUSH_CONST k9
  EQ
  JZ repeatTest_B5
  JMP repeatTest_B3

repeatTest_B5:
  LOAD v_repeatTest_a
  PUSH_CONST k1
  ADD
  STORE v_repeatTest_a
  JMP repeatTest_B4

repeatTest_B3:
  JMP repeatTest_exit

repeatTest_exit:
  PUSH_CONST k3
  LEAVE
  RET

main:
  ENTER 8
  JMP main_B2

main_B2:
  PUSH_ADDR v_main_tmp
  PUSH_CONST k3
  INDEX
  PUSH_CONST k3
  STORE_IND
  JMP main_B3

main_B3:
  PUSH_ADDR v_main_tmp
  PUSH_CONST k1
  INDEX
  PUSH_CONST k1
  STORE_IND
  JMP main_B4

main_B4:
  PUSH_CONST k1
  PUSH_CONST k5
  PUSH_ADDR v_main_tmp
  CALL calc, 3
  POP
  JMP main_B5

main_B5:
  PUSH_CONST k1
  PUSH_CONST k5
  CALL condition, 2
  POP
  JMP main_B6

main_B6:
  CALL function_call, 0
  POP
  JMP main_B7

main_B7:
  CALL blockTest, 0
  POP
  JMP main_B8

main_B8:
  CALL callTest, 0
  POP
  JMP main_B9

main_B9:
  CALL loopTest, 0
  POP
  JMP main_B10

main_B10:
  CALL repeatTest, 0
  POP
  JMP main_exit

main_exit:
  PUSH_CONST k3
  LEAVE
  RET

