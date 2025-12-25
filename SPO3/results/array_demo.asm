; SPO3 linear code listing
; VM: stack-based, memory banks: code, constants, data_mem, stack_mem

k0: DD 2
k1: DD 3
k2: DD 5
k3: DD 1
k4: DD 4
k5: DD 0

v_main_a: DD 0
v_main_b: DD 0
v_main_arr: RESB 256
v_main_x: DD 0
v_main_y: DD 0

main:
  ENTER 272
  JMP main_B2

main_B2:
  PUSH_CONST k0
  STORE v_main_a
  JMP main_B3

main_B3:
  PUSH_CONST k1
  STORE v_main_b
  JMP main_B4

main_B4:
  PUSH_ADDR v_main_arr
  LOAD v_main_a
  LOAD v_main_b
  ADD
  INDEX
  PUSH_CONST k2
  STORE_IND
  JMP main_B5

main_B5:
  PUSH_ADDR v_main_arr
  PUSH_CONST k3
  INDEX
  PUSH_CONST k1
  INDEX
  PUSH_CONST k0
  INDEX
  PUSH_CONST k4
  STORE_IND
  JMP main_B6

main_B6:
  PUSH_ADDR v_main_arr
  LOAD v_main_a
  LOAD v_main_b
  ADD
  INDEX
  LOAD_IND
  STORE v_main_x
  JMP main_B7

main_B7:
  PUSH_ADDR v_main_arr
  PUSH_CONST k3
  INDEX
  PUSH_CONST k1
  INDEX
  PUSH_CONST k0
  INDEX
  LOAD_IND
  STORE v_main_y
  JMP main_B8

main_B8:
  LOAD v_main_x
  CALL print, 1
  POP
  JMP main_B9

main_B9:
  LOAD v_main_y
  CALL print, 1
  POP
  JMP main_exit

main_exit:
  PUSH_CONST k5
  LEAVE
  RET

