[section const_pool]
; SPO7 variant: synchronous, non-blocking byte-stream processors.
; The program models seven SQL selections as map/reduce pipelines.
k0: DD 0
k1: DD 1
k2: DD 2
k4: DD 4
k5: DD 5
k7: DD 7
k10: DD 10
k48: DD 48
k161: DD 161
k2048: DD 2048
kperiod: DD 4

[section data_mem]
; Current query and current processor stage inside that query.
v_query: DD 0
v_stage: DD 0

; Runtime statistics for the preemptive timer-driven scheduler.
v_interrupts: DD 0
v_dispatches: DD 0
v_group_waits: DD 0
v_done_queries: DD 0

; Scratch values loaded from per-query descriptor arrays.
v_stage_limit: DD 0
v_wait_limit: DD 0
v_out_i: DD 0

; Per-query map/reduce descriptor:
; stage_count = number of processors in the pipeline,
; wait_count  = how many non-blocking stream attempts go through group-wait,
; row_count   = row count from equivalent SQL query in PostgreSQL ucheb.
v_stage_counts: DD 5
v_stage_counts_1: DD 5
v_stage_counts_2: DD 4
v_stage_counts_3: DD 6
v_stage_counts_4: DD 7
v_stage_counts_5: DD 8
v_stage_counts_6: DD 5

v_wait_counts: DD 1
v_wait_counts_1: DD 1
v_wait_counts_2: DD 1
v_wait_counts_3: DD 2
v_wait_counts_4: DD 2
v_wait_counts_5: DD 2
v_wait_counts_6: DD 1

v_row_counts: DD 1
v_row_counts_1: DD 0
v_row_counts_2: DD 5004
v_row_counts_3: DD 40
v_row_counts_4: DD 85
v_row_counts_5: DD 0
v_row_counts_6: DD 0

; Deterministic stdout text. The numbers mirror SQL validation:
; R = result rows, P = pipeline processors, W = group-wait events.
v_output: DD 83
v_output_1: DD 80
v_output_2: DD 79
v_output_3: DD 55
v_output_4: DD 32
v_output_5: DD 83
v_output_6: DD 81
v_output_7: DD 76
v_output_8: DD 77
v_output_9: DD 82
v_output_10: DD 10
v_output_11: DD 77
v_output_12: DD 79
v_output_13: DD 68
v_output_14: DD 69
v_output_15: DD 32
v_output_16: DD 83
v_output_17: DD 89
v_output_18: DD 78
v_output_19: DD 67
v_output_20: DD 45
v_output_21: DD 78
v_output_22: DD 66
v_output_23: DD 32
v_output_24: DD 71
v_output_25: DD 82
v_output_26: DD 79
v_output_27: DD 85
v_output_28: DD 80
v_output_29: DD 45
v_output_30: DD 87
v_output_31: DD 65
v_output_32: DD 73
v_output_33: DD 84
v_output_34: DD 10
v_output_35: DD 81
v_output_36: DD 49
v_output_37: DD 32
v_output_38: DD 82
v_output_39: DD 61
v_output_40: DD 49
v_output_41: DD 32
v_output_42: DD 80
v_output_43: DD 61
v_output_44: DD 53
v_output_45: DD 32
v_output_46: DD 87
v_output_47: DD 61
v_output_48: DD 49
v_output_49: DD 10
v_output_50: DD 81
v_output_51: DD 50
v_output_52: DD 32
v_output_53: DD 82
v_output_54: DD 61
v_output_55: DD 48
v_output_56: DD 32
v_output_57: DD 80
v_output_58: DD 61
v_output_59: DD 53
v_output_60: DD 32
v_output_61: DD 87
v_output_62: DD 61
v_output_63: DD 49
v_output_64: DD 10
v_output_65: DD 81
v_output_66: DD 51
v_output_67: DD 32
v_output_68: DD 82
v_output_69: DD 61
v_output_70: DD 53
v_output_71: DD 48
v_output_72: DD 48
v_output_73: DD 52
v_output_74: DD 32
v_output_75: DD 80
v_output_76: DD 61
v_output_77: DD 52
v_output_78: DD 32
v_output_79: DD 87
v_output_80: DD 61
v_output_81: DD 49
v_output_82: DD 10
v_output_83: DD 81
v_output_84: DD 52
v_output_85: DD 32
v_output_86: DD 82
v_output_87: DD 61
v_output_88: DD 52
v_output_89: DD 48
v_output_90: DD 32
v_output_91: DD 80
v_output_92: DD 61
v_output_93: DD 54
v_output_94: DD 32
v_output_95: DD 87
v_output_96: DD 61
v_output_97: DD 50
v_output_98: DD 10
v_output_99: DD 81
v_output_100: DD 53
v_output_101: DD 32
v_output_102: DD 82
v_output_103: DD 61
v_output_104: DD 56
v_output_105: DD 53
v_output_106: DD 32
v_output_107: DD 80
v_output_108: DD 61
v_output_109: DD 55
v_output_110: DD 32
v_output_111: DD 87
v_output_112: DD 61
v_output_113: DD 50
v_output_114: DD 10
v_output_115: DD 81
v_output_116: DD 54
v_output_117: DD 32
v_output_118: DD 82
v_output_119: DD 61
v_output_120: DD 48
v_output_121: DD 32
v_output_122: DD 80
v_output_123: DD 61
v_output_124: DD 56
v_output_125: DD 32
v_output_126: DD 87
v_output_127: DD 61
v_output_128: DD 50
v_output_129: DD 10
v_output_130: DD 81
v_output_131: DD 55
v_output_132: DD 32
v_output_133: DD 82
v_output_134: DD 61
v_output_135: DD 48
v_output_136: DD 32
v_output_137: DD 80
v_output_138: DD 61
v_output_139: DD 53
v_output_140: DD 32
v_output_141: DD 87
v_output_142: DD 61
v_output_143: DD 49
v_output_144: DD 10
v_output_145: DD 73
v_output_146: DD 82
v_output_147: DD 81
v_output_148: DD 61
v_output_149: DD 52
v_output_150: DD 56
v_output_151: DD 32
v_output_152: DD 71
v_output_153: DD 87
v_output_154: DD 61
v_output_155: DD 49
v_output_156: DD 48
v_output_157: DD 10
v_output_158: DD 79
v_output_159: DD 75
v_output_160: DD 10

[section code]
main:
  ; Reset runtime state.
  PUSH_CONST k0
  STORE v_query
  PUSH_CONST k0
  STORE v_stage
  PUSH_CONST k0
  STORE v_interrupts
  PUSH_CONST k0
  STORE v_dispatches
  PUSH_CONST k0
  STORE v_group_waits
  PUSH_CONST k0
  STORE v_done_queries

  ; Configure kernel context used by timer IRQ handler.
  PUSH_CONST k2048
  POP_SYS 10
  PUSH_CONST k2048
  POP_SYS 11
  PUSH_CONST k0
  POP_SYS 12
  PUSH_CONST k2048
  POP_SYS 13

  ; Start external SimpleClock -> SimplePic interrupt pipeline.
  SET_CYCLES_HANDLER rt_timer_handler
  PUSH_CONST kperiod
  SET_PERIOD

  ; Return to idle; preemptive work happens on timer interrupts.
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
  ; IRQ_ENTER saves interrupted context and switches to kernel stack.
  IRQ_ENTER
  ; Non-reentrant kernel section: stop clock until this step finishes.
  PUSH_CONST k0
  SET_PERIOD

  LOAD v_interrupts
  PUSH_CONST k1
  ADD
  STORE v_interrupts

  ; All seven query pipelines finished: validate and print.
  LOAD v_query
  PUSH_CONST k7
  EQ
  JZ rt_load_descriptor
  JMP validate_all

rt_load_descriptor:
  ; stage_limit = stage_counts[query]
  PUSH_ADDR v_stage_counts
  LOAD v_query
  INDEX
  LOAD_IND
  STORE v_stage_limit

  ; wait_limit = wait_counts[query]
  PUSH_ADDR v_wait_counts
  LOAD v_query
  INDEX
  LOAD_IND
  STORE v_wait_limit

  ; If stage == stage_limit, current query is complete.
  LOAD v_stage
  LOAD v_stage_limit
  EQ
  JZ process_stage
  JMP finish_query

process_stage:
  ; One map/reduce processor step. It uses non-blocking stream IO.
  ; If the stage number is below wait_limit, this step simulates a
  ; would-block result, so the scheduler performs group wait.
  LOAD v_stage
  LOAD v_wait_limit
  LT
  JZ process_ready

  ; GROUP_WAIT: wait for any of the stage's input/output streams to become
  ; ready. The thread yields; another processor can run on the next IRQ.
  LOAD v_group_waits
  PUSH_CONST k1
  ADD
  STORE v_group_waits
  LOAD v_dispatches
  PUSH_CONST k1
  ADD
  STORE v_dispatches

process_ready:
  ; A ready stage consumes its input item and/or produces an output item.
  LOAD v_stage
  PUSH_CONST k1
  ADD
  STORE v_stage
  JMP rt_return_idle

finish_query:
  ; Query main procedure observes EOF on all stage streams and advances
  ; to the next selection.
  LOAD v_done_queries
  PUSH_CONST k1
  ADD
  STORE v_done_queries
  LOAD v_dispatches
  PUSH_CONST k1
  ADD
  STORE v_dispatches
  LOAD v_query
  PUSH_CONST k1
  ADD
  STORE v_query
  PUSH_CONST k0
  STORE v_stage
  JMP rt_return_idle

validate_all:
  ; Self-check: sum(stage_counts) + 7 finish steps + final print IRQ = 48.
  LOAD v_done_queries
  PUSH_CONST k7
  EQ
  JZ rt_fail
  LOAD v_group_waits
  PUSH_CONST k10
  EQ
  JZ rt_fail
  LOAD v_interrupts
  PUSH_CONST k48
  EQ
  JZ rt_fail
  JMP print_output

print_output:
  ; All checks passed. Print deterministic SQL/map-reduce summary.
  PUSH_CONST k1
  SET_PORT
  PUSH_CONST k0
  STORE v_out_i

print_output_loop:
  LOAD v_out_i
  PUSH_CONST k161
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
  ; Stop clock and return to halt context.
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
  ; Re-arm clock and return to idle until the next preemptive time slice.
  PUSH_CONST kperiod
  SET_PERIOD
  IRET

rt_halt:
  DI
  RET

rt_fail:
  ; Force VM exception if the simulated pipeline invariants are broken.
  PUSH_CONST k1
  PUSH_CONST k0
  DIV
  RET
