[section const_pool]
czero: DD 0
cone: DD 1
c64: DD 64
cperiod: DD 8
cascii1: DD 49
cnewline: DD 10

[section data_mem]

[section code]
main:
  ; Контекст ядра, используемый после отправки прерывания часов через SimplePic.
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
  PUSH_CONST cone
  SET_PORT
  PUSH_CONST cascii1
  OUT
  PUSH_CONST cnewline
  OUT

  ; Отключаем SimpleClock перед возвратом к остановке.
  PUSH_CONST czero
  SET_PERIOD
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
