; SPO3 linear code listing
; VM: stack-based, memory banks: code, constants, data_mem, stack_mem

.const
k0: .int 2
k1: .int 3
k2: .int 0
k3: .int 1

.data
v_sum_a: .word 0
v_sum_b: .word 0
v_sum_result: .word 0
v_main_x: .word 0
v_main_y: .word 0

.code
sum:
  STORE v_sum_b
  STORE v_sum_a
  ENTER 12
  JMP sum_B2

sum_B2:
  LOAD v_sum_a
  LOAD v_sum_b
  ADD
  STORE v_sum_result
  JMP sum_exit

sum_exit:
  LOAD v_sum_result
  LEAVE
  RET

main:
  ENTER 8
  JMP main_B2

main_B2:
  PUSH_CONST k0
  PUSH_CONST k1
  CALL sum, 2
  STORE v_main_x
  JMP main_B3

main_B3:
  PUSH_CONST k2
  STORE v_main_y
  JMP main_B4

main_B4:
  LOAD v_main_y
  PUSH_CONST k0
  LT
  JZ main_B5
  JMP main_B6

main_B6:
  LOAD v_main_y
  PUSH_CONST k3
  ADD
  STORE v_main_y
  JMP main_B4

main_B5:
  JMP main_B7

main_B7:
  LOAD v_main_x
  LOAD v_main_y
  GT
  JZ main_B9
  JMP main_B8

main_B8:
  LOAD v_main_x
  PUSH_CONST k3
  ADD
  STORE v_main_x
  JMP main_B9

main_B9:
  JMP main_exit

main_exit:
  PUSH_CONST k2
  LEAVE
  RET

