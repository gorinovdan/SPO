[section const_pool]
czero: DD 0
cone: DD 1

[section data_mem]

[section code]
main:
  PUSH_CONST czero
  SET_PORT
  IN
  PUSH_CONST cone
  SET_PORT
  OUT
  RET
