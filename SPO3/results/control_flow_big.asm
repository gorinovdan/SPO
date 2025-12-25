; SPO3 linear code listing
; VM: stack-based, memory banks: code, const_pool, data_mem, stack_mem

[section const_pool]
k0: DD 0
k1: DB "z\\n"
k2: DB "1"
k3: DD 1
k4: DB "2"
k5: DD 2
k6: DB "3"
k7: DD 3
k8: DB "5"
k9: DD 5
k10: DB "break\\n"
k11: DB "7"
k12: DB "8"
k13: DD 9
k14: DB "11"
k15: DD 11
k16: DD 12
k17: DB "continue\\n"
k18: DB "13"
k19: DB "12"
k20: DB "goto labb\\n"
k21: DD 10
k22: DD 6
k23: DB "6"
k24: DD 4
k25: DB "labb:\\n"
k26: DB "4"
k27: DB "14"
k28: DB "2\\n"
k29: DB "goto lab\\n"
k30: DB "1\\n"
k31: DB "22\\n"
k32: DB "222\\n"
k33: DB "3\\n"
k34: DB "Hello!\\n"
__builtin_zero: DD 0
__builtin_one: DD 1

[section data_mem]
v_x_a: DD 0
v_x_b: DD 0
v_main_argc: DD 0
v_main_argv: DD 0
v_main_a: DD 0
v_main_b: DD 0
v_main_i: DD 0

[section code]
main:
  STORE v_main_argv
  STORE v_main_argc
  ENTER 20
  JMP main_B2

main_B2:
  PUSH_CONST k0
  STORE v_main_a
  JMP main_B3

main_B3:
  PUSH_CONST k0
  STORE v_main_b
  JMP main_B4

main_B4:
  PUSH_CONST k0
  STORE v_main_i
  JMP main_B5

main_B5:
  PUSH_CONST k2
  CALL printf, 1
  POP
  JMP main_B6

main_B6:
  PUSH_CONST k3
  JZ main_B7
  JMP main_B8

main_B8:
  PUSH_CONST k4
  CALL printf, 1
  POP
  JMP main_B9

main_B9:
  PUSH_CONST k5
  JZ main_B10
  JMP main_B11

main_B11:
  PUSH_CONST k6
  CALL printf, 1
  POP
  JMP main_B12

main_B12:
  PUSH_CONST k7
  JZ main_B14
  JMP main_B13

main_B13:
  JMP main_B10

main_B10:
  JMP main_B20

main_B20:
  PUSH_CONST k8
  CALL printf, 1
  POP
  JMP main_B21

main_B21:
  PUSH_CONST k9
  JZ main_B23
  JMP main_B22

main_B22:
  PUSH_CONST k10
  CALL printf, 1
  POP
  JMP main_B27

main_B27:
  JMP main_B28

main_B28:
  PUSH_CONST k11
  CALL printf, 1
  POP
  JMP main_B31

main_B31:
  PUSH_CONST k12
  CALL printf, 1
  POP
  JMP main_B32

main_B32:
  PUSH_CONST k13
  JZ main_B34
  JMP main_B33

main_B33:
  JMP main_B29

main_B29:
  JMP main_B35

main_B35:
  PUSH_CONST k14
  CALL printf, 1
  POP
  JMP main_B36

main_B36:
  PUSH_CONST k15
  JZ main_B38
  JMP main_B37

main_B38:
  PUSH_CONST k16
  JZ main_B40
  JMP main_B39

main_B39:
  PUSH_CONST k17
  CALL printf, 1
  POP
  JMP main_B42

main_B42:
  JMP main_B43

main_B43:
  JMP main_B44

main_B44:
  PUSH_CONST k18
  CALL printf, 1
  POP
  JMP main_B6

main_B40:
  PUSH_CONST k19
  CALL printf, 1
  POP
  JMP main_B41

main_B41:
  PUSH_CONST k20
  CALL printf, 1
  POP
  JMP main_B42

main_B34:
  JMP main_B30

main_B30:
  PUSH_CONST k21
  JZ main_B29
  JMP main_B31

main_B23:
  PUSH_CONST k22
  JZ main_B25
  JMP main_B24

main_B24:
  PUSH_CONST k17
  CALL printf, 1
  POP
  JMP main_B26

main_B26:
  JMP main_B27

main_B25:
  PUSH_CONST k23
  CALL printf, 1
  POP
  JMP main_B26

main_B14:
  PUSH_CONST k24
  JZ main_B16
  JMP main_B15

main_B15:
  PUSH_CONST k17
  CALL printf, 1
  POP
  JMP main_B18

main_B18:
  JMP main_B19

main_B19:
  JMP main_B9

main_B16:
  PUSH_CONST k25
  CALL printf, 1
  POP
  JMP main_B17

main_B17:
  PUSH_CONST k26
  CALL printf, 1
  POP
  JMP main_B18

main_B37:
  JMP main_B7

main_B7:
  JMP main_B45

main_B45:
  PUSH_CONST k27
  CALL printf, 1
  POP
  JMP main_B46

main_B46:
  LOAD v_main_a
  PUSH_CONST k7
  GT
  JZ main_B48
  JMP main_B47

main_B48:
  PUSH_CONST k28
  CALL printf, 1
  POP
  JMP main_B49

main_B49:
  PUSH_CONST k29
  CALL printf, 1
  POP
  JMP main_B50

main_B47:
  PUSH_CONST k30
  CALL printf, 1
  POP
  JMP main_B50

main_B50:
  JMP main_B51

main_B51:
  LOAD v_main_i
  PUSH_CONST k21
  LT
  JZ main_B52
  JMP main_B53

main_B53:
  LOAD v_main_a
  LOAD v_main_b
  GT
  JZ main_B55
  JMP main_B54

main_B54:
  LOAD v_main_i
  PUSH_CONST k5
  ADD
  STORE v_main_i
  JMP main_B61

main_B61:
  JMP main_B51

main_B55:
  PUSH_CONST k5
  PUSH_CONST k7
  MUL
  JZ main_B58
  JMP main_B56

main_B58:
  PUSH_CONST k17
  CALL printf, 1
  POP
  JMP main_B59

main_B59:
  LOAD v_main_i
  PUSH_CONST k3
  ADD
  STORE v_main_i
  JMP main_B60

main_B60:
  JMP main_B61

main_B56:
  PUSH_CONST k10
  CALL printf, 1
  POP
  JMP main_B57

main_B57:
  JMP main_B52

main_B52:
  JMP main_B62

main_B62:
  PUSH_CONST k3
  JZ main_B70
  JMP main_B63

main_B63:
  PUSH_CONST k5
  JZ main_B68
  JMP main_B64

main_B68:
  CALL z, 0
  POP
  JMP main_B69

main_B64:
  PUSH_CONST k7
  JZ main_B66
  JMP main_B65

main_B66:
  CALL y, 0
  POP
  JMP main_B67

main_B65:
  CALL x, 0
  POP
  JMP main_B67

main_B67:
  JMP main_B69

main_B69:
  JMP main_B70

main_B70:
  JMP main_B71

main_B71:
  LOAD v_main_a
  PUSH_CONST k7
  GT
  JZ main_B73
  JMP main_B72

main_B73:
  PUSH_CONST k28
  CALL printf, 1
  POP
  JMP main_B74

main_B74:
  PUSH_CONST k31
  CALL printf, 1
  POP
  JMP main_B75

main_B75:
  PUSH_CONST k32
  CALL printf, 1
  POP
  JMP main_B76

main_B72:
  PUSH_CONST k30
  CALL printf, 1
  POP
  JMP main_B76

main_B76:
  JMP main_B77

main_B77:
  LOAD v_main_a
  PUSH_CONST k7
  LT
  JZ main_B78
  JMP main_B79

main_B79:
  PUSH_CONST k33
  CALL printf, 1
  POP
  JMP main_B80

main_B80:
  LOAD v_main_a
  PUSH_CONST k3
  ADD
  STORE v_main_a
  JMP main_B77

main_B78:
  JMP main_B81

main_B81:
  PUSH_CONST k34
  CALL printf, 1
  POP
  JMP main_exit

main_exit:
  PUSH_CONST k0
  LEAVE
  RET

x:
  ENTER 8
  JMP x_B2

x_B2:
  PUSH_CONST k0
  STORE v_x_a
  JMP x_B3

x_B3:
  PUSH_CONST k0
  STORE v_x_b
  JMP x_exit

x_exit:
  PUSH_CONST k0
  LEAVE
  RETF

y:
  ENTER 0
  JMP y_exit

y_exit:
  PUSH_CONST k0
  LEAVE
  RETF

z:
  ENTER 0
  JMP z_B2

z_B2:
  PUSH_CONST k1
  CALL printf, 1
  POP
  JMP z_exit

z_exit:
  PUSH_CONST k0
  LEAVE
  RETF

; builtins
printf:
  PUSH_CONST __builtin_one
  SET_PORT
  OUT
  PUSH_CONST __builtin_zero
  RETF

