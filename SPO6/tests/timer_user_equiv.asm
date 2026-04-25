[section const_pool]
czero: DD 0
cone: DD 1
cthree: DD 3
c64: DD 64
cperiod: DD 8
cascii0: DD 48
cnewline: DD 10

[section data_mem]
v_count: DD 0

[section code]
main:
  ; Kernel context used after SimplePic dispatches the clock interrupt.
  PUSH_CONST c64
  POP_SYS 10
  PUSH_CONST c64
  POP_SYS 11
  PUSH_CONST czero
  POP_SYS 12
  PUSH_CONST czero
  POP_SYS 13

  SET_CYCLES_HANDLER handler
  PUSH_CONST cperiod
  SET_PERIOD

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
  IRQ_ENTER
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
  PUSH_CONST czero
  SET_PERIOD
  PUSH_CODE halt
  POP_SYS 5

handler_continue:
  IRET

halt:
  DI
  RET
