; VM instruction coverage test

.const
k0: .int 0
k1: .int 1
k2: .int 2
k3: .int 3
k4: .int 4
k5: .int 5
kneg4: .int -4
kstr: .string "OK\n"
kfail: .string "FAIL\n"
kport_out: .int 1
kport_in: .int 0

.data
v_x: .word 0
v_y: .word 0
v_arr: .space 16
v_msg: .word 0

.code
main:
  ENTER 28
  NOP
  PUSH_CONST k2
  PUSH_CONST k3
  ADD
  STORE v_x

  LOAD v_x
  PUSH_CONST k1
  SUB
  STORE v_y

  LOAD v_x
  LOAD v_y
  MUL
  POP

  PUSH_CONST k5
  PUSH_CONST k2
  DIV
  POP

  PUSH_CONST k5
  PUSH_CONST k2
  REM
  POP

  PUSH_CONST k2
  NEG
  POP

  PUSH_CONST k1
  PUSH_CONST k0
  AND
  POP

  PUSH_CONST k1
  PUSH_CONST k0
  OR
  POP

  PUSH_CONST k1
  PUSH_CONST k2
  LT
  POP

  PUSH_CONST k2
  PUSH_CONST k1
  GT
  POP

  PUSH_CONST k2
  PUSH_CONST k2
  LE
  POP

  PUSH_CONST k2
  PUSH_CONST k2
  GE
  POP

  PUSH_CONST k2
  PUSH_CONST k2
  EQ
  POP

  PUSH_CONST k2
  PUSH_CONST k3
  NE
  POP

  PUSH_ADDR v_arr
  PUSH_CONST k1
  INDEX
  PUSH_CONST k3
  STORE_IND

  PUSH_ADDR v_arr
  PUSH_CONST k1
  PUSH_CONST k3
  RANGE
  INDEX
  LOAD_IND
  POP

  PUSH_CONST kport_out
  SET_PORT
  PUSH_CONST kstr
  STORE v_msg
  LOAD v_msg
  OUT

  PUSH_CONST kport_in
  SET_PORT
  IN
  POP

  PUSH_CONST k4
  CALL foo, 1
  PUSH_CONST kneg4
  EQ
  JZ fail

  JMP end_main

dead_code:
  PUSH_CONST k0
  POP

end_main:
  LEAVE
  RET

foo:
  STORE v_x
  ENTER 4
  LOAD v_x
  PUSH_CONST k2
  GT
  JZ foo_done
  LOAD v_x
  NEG
  STORE v_x
foo_done:
  LOAD v_x
  LEAVE
  RET

fail:
  PUSH_CONST kport_out
  SET_PORT
  PUSH_CONST kfail
  STORE v_msg
  LOAD v_msg
  OUT
  JMP end_main
