; SPO5 linear code listing

[section const_pool]
k0: DD 2
k1: DD 3
k2: DD 0
k3: DD 1
__builtin_zero: DD 0
__builtin_one: DD 1

[section data_mem]
v_sum_a: DD 0
v_sum_b: DD 0
v_sum_result: DD 0
v_main_x: DD 0
v_main_y: DD 0

[section data_meta]
__spo5_meta_magic: DB "SPO5META"
__spo5_meta_json: DB "{\"types\":[],\"subprograms\":[{\"name\":\"sum\",\"symbols\":[{\"name\":\"a\",\"label\":\"v_sum_a\",\"type\":\"int\",\"isParam\":true},{\"name\":\"b\",\"label\":\"v_sum_b\",\"type\":\"int\",\"isParam\":true}]},{\"name\":\"main\",\"symbols\":[]}]}"

[section code]
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
  RETF

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

