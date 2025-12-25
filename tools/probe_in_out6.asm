[section const_pool]
czero: DD 0
cone: DD 1

[section data_mem]

[section code]
main:
  PUSH_CONST czero
  SET_PORT
  IN
  IN
  IN
  IN
  IN
  IN
  PUSH_CONST cone
  SET_PORT
  OUT
  OUT
  OUT
  OUT
  OUT
  OUT
  RET
