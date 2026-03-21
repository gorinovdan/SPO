; SPO5 linear code listing

[section const_pool]
k0: DD 0
k1: DD 10
k2: DD 13
k3: DD 48
k4: DD 1
k5: DD 43
k6: DD 45
k7: DD 42
k8: DD 47
k9: DD 37
__builtin_zero: DD 0
__builtin_one: DD 1

[section data_mem]
v_read_number_acc: DD 0
v_read_number_ch: DD 0
v_read_number_result: DD 0
v_read_operator_ch: DD 0
v_read_operator_result: DD 0
v_print_number_n: DD 0
v_print_number_cnt: DD 0
v_print_number_tmp: DD 0
v_print_number_digits: RESB 256
v_main_a: DD 0
v_main_op: DD 0
v_main_b: DD 0
v_main_res: DD 0

[section data_meta]
__spo5_meta_magic: DB "SPO5META"
__spo5_meta_json: DB "{\"types\":[],\"subprograms\":[{\"name\":\"read_number\",\"symbols\":[]},{\"name\":\"read_operator\",\"symbols\":[]},{\"name\":\"print_number\",\"symbols\":[{\"name\":\"n\",\"label\":\"v_print_number_n\",\"type\":\"int\",\"isParam\":true}]},{\"name\":\"main\",\"symbols\":[]}]}"

[section code]
read_number:
  ENTER 12
  JMP read_number_B2

read_number_B2:
  PUSH_CONST k0
  STORE v_read_number_acc
  JMP read_number_B3

read_number_B3:
  CALL read, 0
  STORE v_read_number_ch
  JMP read_number_B4

read_number_B4:
  LOAD v_read_number_ch
  PUSH_CONST k1
  EQ
  LOAD v_read_number_ch
  PUSH_CONST k2
  EQ
  OR_OP
  JZ read_number_B5
  JMP read_number_B6

read_number_B6:
  CALL read, 0
  STORE v_read_number_ch
  JMP read_number_B4

read_number_B5:
  JMP read_number_B7

read_number_B7:
  LOAD v_read_number_ch
  PUSH_CONST k1
  NE
  LOAD v_read_number_ch
  PUSH_CONST k2
  NE
  AND_OP
  JZ read_number_B8
  JMP read_number_B9

read_number_B9:
  LOAD v_read_number_acc
  PUSH_CONST k1
  MUL
  LOAD v_read_number_ch
  PUSH_CONST k3
  SUB
  ADD
  STORE v_read_number_acc
  JMP read_number_B10

read_number_B10:
  CALL read, 0
  STORE v_read_number_ch
  JMP read_number_B7

read_number_B8:
  JMP read_number_B11

read_number_B11:
  LOAD v_read_number_acc
  STORE v_read_number_result
  JMP read_number_exit

read_number_exit:
  LOAD v_read_number_result
  LEAVE
  RETF

read_operator:
  ENTER 8
  JMP read_operator_B2

read_operator_B2:
  CALL read, 0
  STORE v_read_operator_ch
  JMP read_operator_B3

read_operator_B3:
  LOAD v_read_operator_ch
  PUSH_CONST k1
  EQ
  LOAD v_read_operator_ch
  PUSH_CONST k2
  EQ
  OR_OP
  JZ read_operator_B4
  JMP read_operator_B5

read_operator_B5:
  CALL read, 0
  STORE v_read_operator_ch
  JMP read_operator_B3

read_operator_B4:
  JMP read_operator_B6

read_operator_B6:
  LOAD v_read_operator_ch
  STORE v_read_operator_result
  JMP read_operator_exit

read_operator_exit:
  LOAD v_read_operator_result
  LEAVE
  RETF

print_number:
  STORE v_print_number_n
  ENTER 268
  JMP print_number_B2

print_number_B2:
  LOAD v_print_number_n
  PUSH_CONST k0
  EQ
  JZ print_number_B4
  JMP print_number_B3

print_number_B4:
  PUSH_CONST k0
  STORE v_print_number_cnt
  JMP print_number_B5

print_number_B5:
  LOAD v_print_number_n
  STORE v_print_number_tmp
  JMP print_number_B6

print_number_B6:
  LOAD v_print_number_tmp
  PUSH_CONST k0
  GT
  JZ print_number_B7
  JMP print_number_B8

print_number_B8:
  PUSH_ADDR v_print_number_digits
  LOAD v_print_number_cnt
  INDEX
  LOAD v_print_number_tmp
  PUSH_CONST k1
  REM
  STORE_IND
  JMP print_number_B9

print_number_B9:
  LOAD v_print_number_cnt
  PUSH_CONST k4
  ADD
  STORE v_print_number_cnt
  JMP print_number_B10

print_number_B10:
  LOAD v_print_number_tmp
  PUSH_CONST k1
  DIV
  STORE v_print_number_tmp
  JMP print_number_B6

print_number_B7:
  JMP print_number_B11

print_number_B11:
  LOAD v_print_number_cnt
  PUSH_CONST k0
  GT
  JZ print_number_B12
  JMP print_number_B13

print_number_B13:
  LOAD v_print_number_cnt
  PUSH_CONST k4
  SUB
  STORE v_print_number_cnt
  JMP print_number_B14

print_number_B14:
  PUSH_ADDR v_print_number_digits
  LOAD v_print_number_cnt
  INDEX
  LOAD_IND
  PUSH_CONST k3
  ADD
  CALL print, 1
  POP
  JMP print_number_B11

print_number_B12:
  JMP print_number_B15

print_number_B3:
  PUSH_CONST k3
  CALL print, 1
  POP
  JMP print_number_B15

print_number_B15:
  JMP print_number_B16

print_number_B16:
  PUSH_CONST k1
  CALL print, 1
  POP
  JMP print_number_exit

print_number_exit:
  PUSH_CONST k0
  LEAVE
  RETF

main:
  ENTER 16
  JMP main_B2

main_B2:
  CALL read_number, 0
  STORE v_main_a
  JMP main_B3

main_B3:
  CALL read_operator, 0
  STORE v_main_op
  JMP main_B4

main_B4:
  CALL read_number, 0
  STORE v_main_b
  JMP main_B5

main_B5:
  LOAD v_main_op
  PUSH_CONST k5
  EQ
  JZ main_B7
  JMP main_B6

main_B7:
  LOAD v_main_op
  PUSH_CONST k6
  EQ
  JZ main_B9
  JMP main_B8

main_B9:
  LOAD v_main_op
  PUSH_CONST k7
  EQ
  JZ main_B11
  JMP main_B10

main_B11:
  LOAD v_main_op
  PUSH_CONST k8
  EQ
  JZ main_B13
  JMP main_B12

main_B13:
  LOAD v_main_op
  PUSH_CONST k9
  EQ
  JZ main_B15
  JMP main_B14

main_B15:
  PUSH_CONST k0
  STORE v_main_res
  JMP main_B16

main_B14:
  LOAD v_main_a
  LOAD v_main_b
  REM
  STORE v_main_res
  JMP main_B16

main_B16:
  JMP main_B17

main_B12:
  LOAD v_main_a
  LOAD v_main_b
  DIV
  STORE v_main_res
  JMP main_B17

main_B17:
  JMP main_B18

main_B10:
  LOAD v_main_a
  LOAD v_main_b
  MUL
  STORE v_main_res
  JMP main_B18

main_B18:
  JMP main_B19

main_B8:
  LOAD v_main_a
  LOAD v_main_b
  SUB
  STORE v_main_res
  JMP main_B19

main_B19:
  JMP main_B20

main_B6:
  LOAD v_main_a
  LOAD v_main_b
  ADD
  STORE v_main_res
  JMP main_B20

main_B20:
  JMP main_B21

main_B21:
  LOAD v_main_res
  CALL print_number, 1
  POP
  JMP main_exit

main_exit:
  PUSH_CONST k0
  LEAVE
  RET

print:
  PUSH_CONST __builtin_one
  SET_PORT
  OUT
  PUSH_CONST __builtin_zero
  RETF

read:
  PUSH_CONST __builtin_zero
  SET_PORT
  IN
  RETF

