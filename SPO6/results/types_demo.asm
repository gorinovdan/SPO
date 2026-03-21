; SPO5 linear code listing

[section const_pool]
k0: DD 1
k1: DD 2
k2: DD 5
k3: DD 7
k4: DD 4
k5: DD 100
k6: DD 10000
k7: DD 0
__builtin_zero: DD 0
__builtin_one: DD 1

[section data_mem]
v_use_shape_shape: DD 0
v_use_shape_result: DD 0
v_use_printer_item: DD 0
v_use_printer_result: DD 0
v_main_base: DD 0
o_main_base: RESB 8
v_main_fancy: DD 0
o_main_fancy: RESB 12
v_main_view: DD 0
o_main_view: RESB 8
v_main_iface: DD 0
v_main_a: DD 0
v_main_b: DD 0
v_main_c: DD 0
v_Shape__describe_self: DD 0
v_Shape__describe_result: DD 0
v_FancyShape__describe_self: DD 0
v_FancyShape__describe_result: DD 0
v___dispatch_Printer_describe_self: DD 0
v___dispatch_Shape_describe_self: DD 0
v___dispatch_FancyShape_describe_self: DD 0

[section data_meta]
__spo5_meta_magic: DB "SPO5META"
__spo5_meta_json: DB "{\"types\":[{\"name\":\"Printer\",\"isInterface\":true,\"typeId\":0,\"base\":\"\",\"fields\":[]},{\"name\":\"Shape\",\"isInterface\":false,\"typeId\":1,\"base\":\"\",\"fields\":[{\"name\":\"value\",\"type\":\"int\",\"slot\":1}]},{\"name\":\"FancyShape\",\"isInterface\":false,\"typeId\":2,\"base\":\"Shape\",\"fields\":[{\"name\":\"value\",\"type\":\"int\",\"slot\":1},{\"name\":\"extra\",\"type\":\"int\",\"slot\":2}]}],\"subprograms\":[{\"name\":\"use_shape\",\"symbols\":[{\"name\":\"shape\",\"label\":\"v_use_shape_shape\",\"type\":\"Shape\",\"isParam\":true}]},{\"name\":\"use_printer\",\"symbols\":[{\"name\":\"item\",\"label\":\"v_use_printer_item\",\"type\":\"Printer\",\"isParam\":true}]},{\"name\":\"main\",\"symbols\":[{\"name\":\"base\",\"label\":\"v_main_base\",\"type\":\"Shape\",\"isParam\":false},{\"name\":\"fancy\",\"label\":\"v_main_fancy\",\"type\":\"FancyShape\",\"isParam\":false},{\"name\":\"view\",\"label\":\"v_main_view\",\"type\":\"Shape\",\"isParam\":false},{\"name\":\"iface\",\"label\":\"v_main_iface\",\"type\":\"Printer\",\"isParam\":false}]},{\"name\":\"Shape__describe\",\"symbols\":[{\"name\":\"self\",\"label\":\"v_Shape__describe_self\",\"type\":\"Shape\",\"isParam\":true}]},{\"name\":\"FancyShape__describe\",\"symbols\":[{\"name\":\"self\",\"label\":\"v_FancyShape__describe_self\",\"type\":\"FancyShape\",\"isParam\":true}]}]}"

[section code]
main:
  ENTER 56
  PUSH_ADDR o_main_base
  STORE v_main_base
  PUSH_ADDR o_main_base
  PUSH_CONST k0
  STORE_IND
  PUSH_ADDR o_main_fancy
  STORE v_main_fancy
  PUSH_ADDR o_main_fancy
  PUSH_CONST k1
  STORE_IND
  PUSH_ADDR o_main_view
  STORE v_main_view
  PUSH_ADDR o_main_view
  PUSH_CONST k0
  STORE_IND
  JMP main_B2

main_B2:
  JMP main_B3

main_B3:
  JMP main_B4

main_B4:
  JMP main_B5

main_B5:
  JMP main_B6

main_B6:
  LOAD v_main_base
  PUSH_CONST k0
  INDEX
  PUSH_CONST k2
  STORE_IND
  JMP main_B7

main_B7:
  LOAD v_main_fancy
  PUSH_CONST k0
  INDEX
  PUSH_CONST k3
  STORE_IND
  JMP main_B8

main_B8:
  LOAD v_main_fancy
  PUSH_CONST k1
  INDEX
  PUSH_CONST k4
  STORE_IND
  JMP main_B9

main_B9:
  LOAD v_main_fancy
  STORE v_main_view
  JMP main_B10

main_B10:
  LOAD v_main_fancy
  STORE v_main_iface
  JMP main_B11

main_B11:
  LOAD v_main_base
  CALL __dispatch_Shape_describe, 1
  STORE v_main_a
  JMP main_B12

main_B12:
  LOAD v_main_view
  CALL use_shape, 1
  STORE v_main_b
  JMP main_B13

main_B13:
  LOAD v_main_iface
  CALL use_printer, 1
  STORE v_main_c
  JMP main_B14

main_B14:
  LOAD v_main_a
  LOAD v_main_b
  PUSH_CONST k5
  MUL
  ADD
  LOAD v_main_c
  PUSH_CONST k6
  MUL
  ADD
  CALL print, 1
  POP
  JMP main_exit

main_exit:
  PUSH_CONST k7
  LEAVE
  RET

use_shape:
  STORE v_use_shape_shape
  ENTER 8
  JMP use_shape_B2

use_shape_B2:
  LOAD v_use_shape_shape
  CALL __dispatch_Shape_describe, 1
  STORE v_use_shape_result
  JMP use_shape_exit

use_shape_exit:
  LOAD v_use_shape_result
  LEAVE
  RETF

use_printer:
  STORE v_use_printer_item
  ENTER 8
  JMP use_printer_B2

use_printer_B2:
  LOAD v_use_printer_item
  CALL __dispatch_Printer_describe, 1
  STORE v_use_printer_result
  JMP use_printer_exit

use_printer_exit:
  LOAD v_use_printer_result
  LEAVE
  RETF

Shape__describe:
  STORE v_Shape__describe_self
  ENTER 8
  JMP Shape__describe_B2

Shape__describe_B2:
  LOAD v_Shape__describe_self
  PUSH_CONST k0
  INDEX
  LOAD_IND
  STORE v_Shape__describe_result
  JMP Shape__describe_exit

Shape__describe_exit:
  LOAD v_Shape__describe_result
  LEAVE
  RETF

FancyShape__describe:
  STORE v_FancyShape__describe_self
  ENTER 8
  JMP FancyShape__describe_B2

FancyShape__describe_B2:
  LOAD v_FancyShape__describe_self
  PUSH_CONST k0
  INDEX
  LOAD_IND
  LOAD v_FancyShape__describe_self
  PUSH_CONST k1
  INDEX
  LOAD_IND
  ADD
  STORE v_FancyShape__describe_result
  JMP FancyShape__describe_exit

FancyShape__describe_exit:
  LOAD v_FancyShape__describe_result
  LEAVE
  RETF

__dispatch_Printer_describe:
  STORE v___dispatch_Printer_describe_self
  ENTER 4
  LOAD v___dispatch_Printer_describe_self
  PUSH_CONST k7
  INDEX
  LOAD_IND
  PUSH_CONST k1
  EQ
  JZ __dispatch_Printer_describe_default
  LOAD v___dispatch_Printer_describe_self
  CALL FancyShape__describe, 1
  LEAVE
  RETF

__dispatch_Printer_describe_default:
  PUSH_CONST k7
  LEAVE
  RETF

__dispatch_Shape_describe:
  STORE v___dispatch_Shape_describe_self
  ENTER 4
  LOAD v___dispatch_Shape_describe_self
  PUSH_CONST k7
  INDEX
  LOAD_IND
  PUSH_CONST k0
  EQ
  JZ __dispatch_Shape_describe_check_1
  LOAD v___dispatch_Shape_describe_self
  CALL Shape__describe, 1
  LEAVE
  RETF

__dispatch_Shape_describe_check_1:
  LOAD v___dispatch_Shape_describe_self
  PUSH_CONST k7
  INDEX
  LOAD_IND
  PUSH_CONST k1
  EQ
  JZ __dispatch_Shape_describe_default
  LOAD v___dispatch_Shape_describe_self
  CALL FancyShape__describe, 1
  LEAVE
  RETF

__dispatch_Shape_describe_default:
  PUSH_CONST k7
  LEAVE
  RETF

__dispatch_FancyShape_describe:
  STORE v___dispatch_FancyShape_describe_self
  ENTER 4
  LOAD v___dispatch_FancyShape_describe_self
  PUSH_CONST k7
  INDEX
  LOAD_IND
  PUSH_CONST k1
  EQ
  JZ __dispatch_FancyShape_describe_default
  LOAD v___dispatch_FancyShape_describe_self
  CALL FancyShape__describe, 1
  LEAVE
  RETF

__dispatch_FancyShape_describe_default:
  PUSH_CONST k7
  LEAVE
  RETF

print:
  PUSH_CONST __builtin_one
  SET_PORT
  OUT
  PUSH_CONST __builtin_zero
  RETF

