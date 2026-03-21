[section const_pool]
czero: DD 0
cone: DD 1
c64: DD 64

[section data_mem]

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

  PUSH_CONST cone
  POP_SYS 4
  PUSH_CODE handler
  POP_SYS 2
  PUSH_CONST cone
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
  IRET

worker:
  NOP
  JMP worker

handler:
  PUSH_CONST cone
  SET_PORT
  PUSH_CONST cone
  OUT
  PUSH_CODE halt
  POP_SYS 5
  PUSH_CONST czero
  POP_SYS 6
  PUSH_CONST czero
  POP_SYS 7
  PUSH_CONST czero
  POP_SYS 8
  PUSH_CONST czero
  POP_SYS 9
  IRET

halt:
  DI
  RET
