[section const_pool]
czero: DD 0
cone: DD 1
cthree: DD 3
c64: DD 64
cascii0: DD 48
cnewline: DD 10

[section data_mem]
v_count: DD 0

[section code]
main:
  PUSH_CONST c64
  POP_SYS 10
  PUSH_CONST c64
  POP_SYS 11
  PUSH_CONST czero
  POP_SYS 12
  PUSH_CONST czero
  POP_SYS 13

  PUSH_CODE handler
  POP_SYS 2
  PUSH_CONST cthree
  POP_SYS 1

  PUSH_CODE worker
  POP_SYS 5
  PUSH_CONST czero
  POP_SYS 6
  PUSH_CONST czero
  POP_SYS 7
  PUSH_CONST czero
  POP_SYS 8
  PUSH_CONST czero
  POP_SYS 9

  PUSH_CONST cone
  POP_SYS 4
  IRET

worker:
  NOP
  JMP worker

handler:
  LOAD v_count
  PUSH_CONST cone
  ADD
  STORE v_count

  PUSH_CONST cone
  SET_PORT

  LOAD v_count
  PUSH_CONST cascii0
  ADD
  OUT

  PUSH_CONST cnewline
  OUT

  LOAD v_count
  PUSH_CONST cthree
  EQ
  JZ handler_continue
  PUSH_CODE halt
  POP_SYS 5

handler_continue:
  IRET

halt:
  DI
  RET
