[section const_pool]
k0: DD 0
k1: DD 1
k2: DD 2
k4: DD 4
k10: DD 10
k101: DD 101
k2048: DD 2048
kperiod: DD 4
kchar_P: DD 80
kchar_C: DD 67
kchar_F: DD 70
kchar_E: DD 69

[section data_mem]
v_algo: DD 0
v_tick: DD 0
v_p_idx: DD 0
v_c_idx: DD 0
v_stream_count: DD 0
v_stream_head: DD 0
v_stream_tail: DD 0
v_full_waits: DD 0
v_empty_waits: DD 0
v_interrupts: DD 0
v_dispatches: DD 0
v_trace_idx: DD 0
v_out_i: DD 0
v_trace_code: DD 0

v_items: DD 10
v_items_1: DD 20
v_items_2: DD 30
v_items_3: DD 40

v_stream_buf: RESB 8
v_consumed: RESB 16
v_trace: RESB 64

v_output: DD 83
v_output_1: DD 80
v_output_2: DD 79
v_output_3: DD 55
v_output_4: DD 10
v_output_5: DD 70
v_output_6: DD 67
v_output_7: DD 70
v_output_8: DD 83
v_output_9: DD 32
v_output_10: DD 67
v_output_11: DD 61
v_output_12: DD 49
v_output_13: DD 48
v_output_14: DD 44
v_output_15: DD 50
v_output_16: DD 48
v_output_17: DD 44
v_output_18: DD 51
v_output_19: DD 48
v_output_20: DD 44
v_output_21: DD 52
v_output_22: DD 48
v_output_23: DD 32
v_output_24: DD 84
v_output_25: DD 61
v_output_26: DD 80
v_output_27: DD 80
v_output_28: DD 70
v_output_29: DD 67
v_output_30: DD 67
v_output_31: DD 69
v_output_32: DD 80
v_output_33: DD 80
v_output_34: DD 67
v_output_35: DD 67
v_output_36: DD 32
v_output_37: DD 87
v_output_38: DD 61
v_output_39: DD 49
v_output_40: DD 47
v_output_41: DD 49
v_output_42: DD 32
v_output_43: DD 73
v_output_44: DD 61
v_output_45: DD 49
v_output_46: DD 48
v_output_47: DD 32
v_output_48: DD 68
v_output_49: DD 61
v_output_50: DD 52
v_output_51: DD 10
v_output_52: DD 83
v_output_53: DD 80
v_output_54: DD 78
v_output_55: DD 32
v_output_56: DD 67
v_output_57: DD 61
v_output_58: DD 49
v_output_59: DD 48
v_output_60: DD 44
v_output_61: DD 50
v_output_62: DD 48
v_output_63: DD 44
v_output_64: DD 51
v_output_65: DD 48
v_output_66: DD 44
v_output_67: DD 52
v_output_68: DD 48
v_output_69: DD 32
v_output_70: DD 84
v_output_71: DD 61
v_output_72: DD 69
v_output_73: DD 80
v_output_74: DD 67
v_output_75: DD 69
v_output_76: DD 80
v_output_77: DD 67
v_output_78: DD 80
v_output_79: DD 67
v_output_80: DD 80
v_output_81: DD 67
v_output_82: DD 32
v_output_83: DD 87
v_output_84: DD 61
v_output_85: DD 48
v_output_86: DD 47
v_output_87: DD 50
v_output_88: DD 32
v_output_89: DD 73
v_output_90: DD 61
v_output_91: DD 49
v_output_92: DD 48
v_output_93: DD 32
v_output_94: DD 68
v_output_95: DD 61
v_output_96: DD 57
v_output_97: DD 10
v_output_98: DD 79
v_output_99: DD 75
v_output_100: DD 10

[section code]
main:
  PUSH_CONST k0
  STORE v_algo
  PUSH_CONST k0
  STORE v_tick
  PUSH_CONST k0
  STORE v_p_idx
  PUSH_CONST k0
  STORE v_c_idx
  PUSH_CONST k0
  STORE v_stream_count
  PUSH_CONST k0
  STORE v_stream_head
  PUSH_CONST k0
  STORE v_stream_tail
  PUSH_CONST k0
  STORE v_full_waits
  PUSH_CONST k0
  STORE v_empty_waits
  PUSH_CONST k0
  STORE v_interrupts
  PUSH_CONST k1
  STORE v_dispatches
  PUSH_CONST k0
  STORE v_trace_idx

  PUSH_CONST k2048
  POP_SYS 10
  PUSH_CONST k2048
  POP_SYS 11
  PUSH_CONST k0
  POP_SYS 12
  PUSH_CONST k2048
  POP_SYS 13

  SET_CYCLES_HANDLER rt_timer_handler
  PUSH_CONST kperiod
  SET_PERIOD

  PUSH_CODE rt_idle
  POP_SYS 5
  PUSH_CONST k0
  POP_SYS 6
  PUSH_CONST k0
  POP_SYS 7
  PUSH_CONST k0
  POP_SYS 8
  PUSH_CONST k0
  POP_SYS 9
  IRET

rt_idle:
  NOP
  JMP rt_idle

rt_timer_handler:
  IRQ_ENTER
  PUSH_CONST k0
  SET_PERIOD
  LOAD v_interrupts
  PUSH_CONST k1
  ADD
  STORE v_interrupts
  LOAD v_algo
  PUSH_CONST k0
  EQ
  JZ rt_handler_spn
  JMP rt_handler_fcfs

rt_handler_fcfs:
  LOAD v_tick
  PUSH_CONST k0
  EQ
  JZ fcfs_t1
  JMP fcfs_write

fcfs_t1:
  LOAD v_tick
  PUSH_CONST k1
  EQ
  JZ fcfs_t2
  JMP fcfs_write

fcfs_t2:
  LOAD v_tick
  PUSH_CONST k2
  EQ
  JZ fcfs_t3
  JMP fcfs_write

fcfs_t3:
  LOAD v_tick
  PUSH_CONST k4
  LT
  JZ fcfs_t4
  JMP fcfs_read

fcfs_t4:
  LOAD v_tick
  PUSH_CONST k4
  EQ
  JZ fcfs_t5
  JMP fcfs_read

fcfs_t5:
  LOAD v_tick
  PUSH_CONST k4
  PUSH_CONST k1
  ADD
  EQ
  JZ fcfs_t6
  JMP fcfs_read

fcfs_t6:
  LOAD v_tick
  PUSH_CONST k10
  PUSH_CONST k2
  SUB
  LT
  JZ fcfs_t8
  JMP fcfs_write

fcfs_t8:
  JMP fcfs_read

rt_handler_spn:
  LOAD v_tick
  PUSH_CONST k0
  EQ
  JZ spn_t1
  JMP spn_read

spn_t1:
  LOAD v_tick
  PUSH_CONST k1
  EQ
  JZ spn_t2
  JMP spn_write

spn_t2:
  LOAD v_tick
  PUSH_CONST k2
  EQ
  JZ spn_t3
  JMP spn_read

spn_t3:
  LOAD v_tick
  PUSH_CONST k4
  PUSH_CONST k1
  SUB
  EQ
  JZ spn_t4
  JMP spn_read

spn_t4:
  LOAD v_tick
  PUSH_CONST k4
  EQ
  JZ spn_t5
  JMP spn_write

spn_t5:
  LOAD v_tick
  PUSH_CONST k4
  PUSH_CONST k1
  ADD
  EQ
  JZ spn_t6
  JMP spn_read

spn_t6:
  LOAD v_tick
  PUSH_CONST k2
  REM
  JZ spn_even
  JMP spn_read

spn_even:
  JMP spn_write

fcfs_write:
  LOAD v_stream_count
  PUSH_CONST k2
  EQ
  JZ fcfs_write_do
  LOAD v_full_waits
  PUSH_CONST k1
  ADD
  STORE v_full_waits
  LOAD v_dispatches
  PUSH_CONST k1
  ADD
  STORE v_dispatches
  PUSH_CONST kchar_F
  STORE v_trace_code
  JMP fcfs_append

fcfs_write_do:
  PUSH_ADDR v_stream_buf
  LOAD v_stream_tail
  INDEX
  PUSH_ADDR v_items
  LOAD v_p_idx
  INDEX
  LOAD_IND
  STORE_IND
  LOAD v_stream_tail
  PUSH_CONST k1
  ADD
  PUSH_CONST k2
  REM
  STORE v_stream_tail
  LOAD v_stream_count
  PUSH_CONST k1
  ADD
  STORE v_stream_count
  LOAD v_p_idx
  PUSH_CONST k1
  ADD
  STORE v_p_idx
  PUSH_CONST kchar_P
  STORE v_trace_code

fcfs_append:
  PUSH_ADDR v_trace
  LOAD v_trace_idx
  INDEX
  LOAD v_trace_code
  STORE_IND
  LOAD v_trace_idx
  PUSH_CONST k1
  ADD
  STORE v_trace_idx
  JMP fcfs_after_action

fcfs_read:
  LOAD v_stream_count
  PUSH_CONST k0
  EQ
  JZ fcfs_read_do
  LOAD v_empty_waits
  PUSH_CONST k1
  ADD
  STORE v_empty_waits
  LOAD v_dispatches
  PUSH_CONST k1
  ADD
  STORE v_dispatches
  PUSH_CONST kchar_E
  STORE v_trace_code
  JMP fcfs_read_append

fcfs_read_do:
  PUSH_ADDR v_consumed
  LOAD v_c_idx
  INDEX
  PUSH_ADDR v_stream_buf
  LOAD v_stream_head
  INDEX
  LOAD_IND
  STORE_IND
  LOAD v_stream_head
  PUSH_CONST k1
  ADD
  PUSH_CONST k2
  REM
  STORE v_stream_head
  LOAD v_stream_count
  PUSH_CONST k1
  SUB
  STORE v_stream_count
  LOAD v_c_idx
  PUSH_CONST k1
  ADD
  STORE v_c_idx
  PUSH_CONST kchar_C
  STORE v_trace_code

fcfs_read_append:
  PUSH_ADDR v_trace
  LOAD v_trace_idx
  INDEX
  LOAD v_trace_code
  STORE_IND
  LOAD v_trace_idx
  PUSH_CONST k1
  ADD
  STORE v_trace_idx
  JMP fcfs_after_action

fcfs_after_action:
  LOAD v_tick
  PUSH_CONST k1
  ADD
  STORE v_tick
  LOAD v_tick
  PUSH_CONST k10
  EQ
  JZ rt_return_idle
  JMP validate_fcfs

validate_fcfs:
  PUSH_ADDR v_consumed
  PUSH_CONST k0
  INDEX
  LOAD_IND
  PUSH_ADDR v_items
  PUSH_CONST k0
  INDEX
  LOAD_IND
  EQ
  JZ rt_fail
  PUSH_ADDR v_consumed
  PUSH_CONST k1
  INDEX
  LOAD_IND
  PUSH_ADDR v_items
  PUSH_CONST k1
  INDEX
  LOAD_IND
  EQ
  JZ rt_fail
  PUSH_ADDR v_consumed
  PUSH_CONST k2
  INDEX
  LOAD_IND
  PUSH_ADDR v_items
  PUSH_CONST k2
  INDEX
  LOAD_IND
  EQ
  JZ rt_fail
  PUSH_ADDR v_consumed
  PUSH_CONST k4
  PUSH_CONST k1
  SUB
  INDEX
  LOAD_IND
  PUSH_ADDR v_items
  PUSH_CONST k4
  PUSH_CONST k1
  SUB
  INDEX
  LOAD_IND
  EQ
  JZ rt_fail
  LOAD v_full_waits
  PUSH_CONST k1
  EQ
  JZ rt_fail
  LOAD v_empty_waits
  PUSH_CONST k1
  EQ
  JZ rt_fail
  LOAD v_trace_idx
  PUSH_CONST k10
  EQ
  JZ rt_fail
  PUSH_CONST k1
  STORE v_algo
  PUSH_CONST k0
  STORE v_tick
  PUSH_CONST k0
  STORE v_p_idx
  PUSH_CONST k0
  STORE v_c_idx
  PUSH_CONST k0
  STORE v_stream_count
  PUSH_CONST k0
  STORE v_stream_head
  PUSH_CONST k0
  STORE v_stream_tail
  PUSH_CONST k0
  STORE v_full_waits
  PUSH_CONST k0
  STORE v_empty_waits
  PUSH_CONST k0
  STORE v_interrupts
  PUSH_CONST k1
  STORE v_dispatches
  PUSH_CONST k0
  STORE v_trace_idx
  JMP rt_return_idle

spn_write:
  LOAD v_stream_count
  PUSH_CONST k2
  EQ
  JZ spn_write_do
  LOAD v_full_waits
  PUSH_CONST k1
  ADD
  STORE v_full_waits
  LOAD v_dispatches
  PUSH_CONST k1
  ADD
  STORE v_dispatches
  PUSH_CONST kchar_F
  STORE v_trace_code
  JMP spn_append

spn_write_do:
  PUSH_ADDR v_stream_buf
  LOAD v_stream_tail
  INDEX
  PUSH_ADDR v_items
  LOAD v_p_idx
  INDEX
  LOAD_IND
  STORE_IND
  LOAD v_stream_tail
  PUSH_CONST k1
  ADD
  PUSH_CONST k2
  REM
  STORE v_stream_tail
  LOAD v_stream_count
  PUSH_CONST k1
  ADD
  STORE v_stream_count
  LOAD v_p_idx
  PUSH_CONST k1
  ADD
  STORE v_p_idx
  LOAD v_dispatches
  PUSH_CONST k1
  ADD
  STORE v_dispatches
  PUSH_CONST kchar_P
  STORE v_trace_code

spn_append:
  PUSH_ADDR v_trace
  LOAD v_trace_idx
  INDEX
  LOAD v_trace_code
  STORE_IND
  LOAD v_trace_idx
  PUSH_CONST k1
  ADD
  STORE v_trace_idx
  JMP spn_after_action

spn_read:
  LOAD v_stream_count
  PUSH_CONST k0
  EQ
  JZ spn_read_do
  LOAD v_empty_waits
  PUSH_CONST k1
  ADD
  STORE v_empty_waits
  LOAD v_dispatches
  PUSH_CONST k1
  ADD
  STORE v_dispatches
  PUSH_CONST kchar_E
  STORE v_trace_code
  JMP spn_read_append

spn_read_do:
  PUSH_ADDR v_consumed
  LOAD v_c_idx
  INDEX
  PUSH_ADDR v_stream_buf
  LOAD v_stream_head
  INDEX
  LOAD_IND
  STORE_IND
  LOAD v_stream_head
  PUSH_CONST k1
  ADD
  PUSH_CONST k2
  REM
  STORE v_stream_head
  LOAD v_stream_count
  PUSH_CONST k1
  SUB
  STORE v_stream_count
  LOAD v_c_idx
  PUSH_CONST k1
  ADD
  STORE v_c_idx
  LOAD v_dispatches
  PUSH_CONST k1
  ADD
  STORE v_dispatches
  PUSH_CONST kchar_C
  STORE v_trace_code

spn_read_append:
  PUSH_ADDR v_trace
  LOAD v_trace_idx
  INDEX
  LOAD v_trace_code
  STORE_IND
  LOAD v_trace_idx
  PUSH_CONST k1
  ADD
  STORE v_trace_idx
  JMP spn_after_action

spn_after_action:
  LOAD v_tick
  PUSH_CONST k1
  ADD
  STORE v_tick
  LOAD v_tick
  PUSH_CONST k10
  EQ
  JZ rt_return_idle
  JMP validate_spn

validate_spn:
  PUSH_ADDR v_consumed
  PUSH_CONST k0
  INDEX
  LOAD_IND
  PUSH_ADDR v_items
  PUSH_CONST k0
  INDEX
  LOAD_IND
  EQ
  JZ rt_fail
  PUSH_ADDR v_consumed
  PUSH_CONST k1
  INDEX
  LOAD_IND
  PUSH_ADDR v_items
  PUSH_CONST k1
  INDEX
  LOAD_IND
  EQ
  JZ rt_fail
  PUSH_ADDR v_consumed
  PUSH_CONST k2
  INDEX
  LOAD_IND
  PUSH_ADDR v_items
  PUSH_CONST k2
  INDEX
  LOAD_IND
  EQ
  JZ rt_fail
  PUSH_ADDR v_consumed
  PUSH_CONST k4
  PUSH_CONST k1
  SUB
  INDEX
  LOAD_IND
  PUSH_ADDR v_items
  PUSH_CONST k4
  PUSH_CONST k1
  SUB
  INDEX
  LOAD_IND
  EQ
  JZ rt_fail
  LOAD v_full_waits
  PUSH_CONST k0
  EQ
  JZ rt_fail
  LOAD v_empty_waits
  PUSH_CONST k2
  EQ
  JZ rt_fail
  LOAD v_trace_idx
  PUSH_CONST k10
  EQ
  JZ rt_fail
  JMP print_output

print_output:
  PUSH_CONST k1
  SET_PORT
  PUSH_CONST k0
  STORE v_out_i

print_output_loop:
  LOAD v_out_i
  PUSH_CONST k101
  LT
  JZ print_output_done
  PUSH_ADDR v_output
  LOAD v_out_i
  INDEX
  LOAD_IND
  OUT
  LOAD v_out_i
  PUSH_CONST k1
  ADD
  STORE v_out_i
  JMP print_output_loop

print_output_done:
  PUSH_CONST k0
  SET_PERIOD
  PUSH_CODE rt_halt
  POP_SYS 5
  PUSH_CONST k0
  POP_SYS 6
  PUSH_CONST k0
  POP_SYS 7
  PUSH_CONST k0
  POP_SYS 8
  PUSH_CONST k0
  POP_SYS 9
  IRET

rt_return_idle:
  PUSH_CONST kperiod
  SET_PERIOD
  IRET

rt_halt:
  DI
  RET

rt_fail:
  PUSH_CONST k1
  PUSH_CONST k0
  DIV
  RET
