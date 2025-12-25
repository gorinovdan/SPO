; SPO3 calculator demo (byte-based input, decimal output)
; Input example:
; 234
; %
; 10
; Output: 4

[section const_pool]
k0: DD 0
k1: DD 1
k10: DD 10
k13: DD 13
k37: DD 37
k42: DD 42
k43: DD 43
k45: DD 45
k47: DD 47
k48: DD 48

[section data_mem]
v_a: DD 0
v_b: DD 0
v_op: DD 0
v_res: DD 0
v_acc: DD 0
v_tmp: DD 0
v_cnt: DD 0

[section code]
main:
  ; input port
  PUSH_CONST k0
  SET_PORT

  ; read first integer -> v_a
  PUSH_CONST k0
  STORE v_acc
read_a_skip:
  IN
  STORE v_tmp
  LOAD v_tmp
  PUSH_CONST k10
  EQ
  JZ read_a_check_cr
  JMP read_a_skip
read_a_check_cr:
  LOAD v_tmp
  PUSH_CONST k13
  EQ
  JZ read_a_digit_loop
  JMP read_a_skip
read_a_digit_loop:
  LOAD v_tmp
  PUSH_CONST k10
  EQ
  JZ read_a_check_cr2
  JMP read_a_done
read_a_check_cr2:
  LOAD v_tmp
  PUSH_CONST k13
  EQ
  JZ read_a_digit_calc
  JMP read_a_done
read_a_digit_calc:
  LOAD v_acc
  PUSH_CONST k10
  MUL
  LOAD v_tmp
  PUSH_CONST k48
  SUB
  ADD
  STORE v_acc
  IN
  STORE v_tmp
  JMP read_a_digit_loop
read_a_done:
  LOAD v_acc
  STORE v_a

  ; read operator -> v_op (skip CR/LF)
read_op_skip:
  IN
  STORE v_tmp
  LOAD v_tmp
  PUSH_CONST k10
  EQ
  JZ read_op_check_cr
  JMP read_op_skip
read_op_check_cr:
  LOAD v_tmp
  PUSH_CONST k13
  EQ
  JZ read_op_store
  JMP read_op_skip
read_op_store:
  LOAD v_tmp
  STORE v_op

  ; read second integer -> v_b
  PUSH_CONST k0
  STORE v_acc
read_b_skip:
  IN
  STORE v_tmp
  LOAD v_tmp
  PUSH_CONST k10
  EQ
  JZ read_b_check_cr
  JMP read_b_skip
read_b_check_cr:
  LOAD v_tmp
  PUSH_CONST k13
  EQ
  JZ read_b_digit_loop
  JMP read_b_skip
read_b_digit_loop:
  LOAD v_tmp
  PUSH_CONST k10
  EQ
  JZ read_b_check_cr2
  JMP read_b_done
read_b_check_cr2:
  LOAD v_tmp
  PUSH_CONST k13
  EQ
  JZ read_b_digit_calc
  JMP read_b_done
read_b_digit_calc:
  LOAD v_acc
  PUSH_CONST k10
  MUL
  LOAD v_tmp
  PUSH_CONST k48
  SUB
  ADD
  STORE v_acc
  IN
  STORE v_tmp
  JMP read_b_digit_loop
read_b_done:
  LOAD v_acc
  STORE v_b

  ; compute result based on operator
  LOAD v_op
  PUSH_CONST k43
  EQ
  JZ op_minus
  LOAD v_a
  LOAD v_b
  ADD
  STORE v_res
  JMP output
op_minus:
  LOAD v_op
  PUSH_CONST k45
  EQ
  JZ op_mul
  LOAD v_a
  LOAD v_b
  SUB
  STORE v_res
  JMP output
op_mul:
  LOAD v_op
  PUSH_CONST k42
  EQ
  JZ op_div
  LOAD v_a
  LOAD v_b
  MUL
  STORE v_res
  JMP output
op_div:
  LOAD v_op
  PUSH_CONST k47
  EQ
  JZ op_rem
  LOAD v_a
  LOAD v_b
  DIV
  STORE v_res
  JMP output
op_rem:
  LOAD v_op
  PUSH_CONST k37
  EQ
  JZ output
  LOAD v_a
  LOAD v_b
  REM
  STORE v_res

output:
  ; output port
  PUSH_CONST k1
  SET_PORT

  ; if result == 0 -> print '0'
  LOAD v_res
  PUSH_CONST k0
  EQ
  JZ output_nonzero
  PUSH_CONST k48
  OUT
  JMP output_newline

output_nonzero:
  PUSH_CONST k0
  STORE v_cnt
  LOAD v_res
  STORE v_tmp
digit_loop:
  LOAD v_tmp
  PUSH_CONST k0
  NE
  JZ output_digits
  LOAD v_tmp
  PUSH_CONST k10
  REM
  PUSH_CONST k48
  ADD
  LOAD v_cnt
  PUSH_CONST k1
  ADD
  STORE v_cnt
  LOAD v_tmp
  PUSH_CONST k10
  DIV
  STORE v_tmp
  JMP digit_loop
output_digits:
  LOAD v_cnt
  PUSH_CONST k0
  NE
  JZ output_newline
  OUT
  LOAD v_cnt
  PUSH_CONST k1
  SUB
  STORE v_cnt
  JMP output_digits
output_newline:
  PUSH_CONST k10
  OUT
  RET
