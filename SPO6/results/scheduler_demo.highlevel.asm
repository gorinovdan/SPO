; SPO5 linear code listing

[section const_pool]
k0: DD 0
k1: DD 10
k2: DD 32
k3: DD 1
k4: DD 48
k5: DD 70
k6: DD 67
k7: DD 83
k8: DD 80
k9: DD 78
k10: DD 58
k11: DD 6
k12: DD 3
k13: DD 2
k14: DD 9
k15: DD 4
k16: DD 12
k17: DD 5
k18: DD 15
k19: DD 7
k20: DD 100
k21: DD 65
k22: DD 66
k23: DD 84
k24: DD 87
k25: DD 82
k26: DD 73
k27: DD 68
__builtin_zero: DD 0
__builtin_one: DD 1

[section data_mem]
v_putc_ch: DD 0
v_print_number_n: DD 0
v_print_number_cnt: DD 0
v_print_number_tmp: DD 0
v_print_number_digits: RESB 256
v_print_pair_label_a: DD 0
v_print_pair_label_b: DD 0
v_print_vector_values: RESB 256
v_print_vector_count: DD 0
v_print_vector_i: DD 0
v_load_workload_arrival: RESB 24
v_load_workload_burst: RESB 24
v_load_workload_count: DD 0
v_enqueue_fcfs_queue: RESB 256
v_enqueue_fcfs_tail_box: DD 0
v_enqueue_fcfs_task: DD 0
v_pick_fcfs_queue: RESB 256
v_pick_fcfs_head_box: DD 0
v_pick_fcfs_tail_box: DD 0
v_pick_fcfs_result: DD 0
v_select_spn_count: DD 0
v_select_spn_state: RESB 256
v_select_spn_burst: RESB 256
v_select_spn_arrival: RESB 256
v_select_spn_best: DD 0
v_select_spn_i: DD 0
v_select_spn_result: DD 0
v_restore_pc_task: DD 0
v_restore_pc_saved_pc: RESB 256
v_restore_pc_result: DD 0
v_restore_acc_task: DD 0
v_restore_acc_saved_acc: RESB 256
v_restore_acc_result: DD 0
v_save_context_task: DD 0
v_save_context_cpu_pc: DD 0
v_save_context_cpu_acc: DD 0
v_save_context_saved_pc: RESB 256
v_save_context_saved_acc: RESB 256
v_mark_dispatch_task: DD 0
v_mark_dispatch_time: DD 0
v_mark_dispatch_start_time: RESB 256
v_mark_dispatch_state: RESB 256
v_mark_dispatch_dispatches_box: DD 0
v_execute_tick_task: DD 0
v_execute_tick_time: DD 0
v_execute_tick_timeline: RESB 256
v_execute_tick_cpu_pc_box: DD 0
v_execute_tick_cpu_acc_box: DD 0
v_execute_tick_remaining: RESB 256
v_execute_tick_saved_pc: RESB 32
v_execute_tick_saved_acc: RESB 32
v_finish_task_task: DD 0
v_finish_task_time: DD 0
v_finish_task_cpu_acc: DD 0
v_finish_task_finish_time: RESB 256
v_finish_task_checksum: RESB 256
v_finish_task_state: RESB 256
v_finish_task_completed_box: DD 0
v_run_simulation_algo: DD 0
v_run_simulation_arrival: RESB 256
v_run_simulation_burst: RESB 256
v_run_simulation_count_box: DD 0
v_run_simulation_count: DD 0
v_run_simulation_i: DD 0
v_run_simulation_remaining: RESB 256
v_run_simulation_start_time: RESB 256
v_run_simulation_finish_time: RESB 256
v_run_simulation_state: RESB 256
v_run_simulation_saved_pc: RESB 256
v_run_simulation_saved_acc: RESB 256
v_run_simulation_checksum: RESB 256
v_run_simulation_wait_time: RESB 256
v_run_simulation_turn_time: RESB 256
v_run_simulation_queue: RESB 256
v_run_simulation_time: DD 0
v_run_simulation_next_arrival: DD 0
v_run_simulation_current: DD 0
v_run_simulation_cpu_pc: DD 0
v_run_simulation_cpu_acc: DD 0
v_run_simulation_completed_box: DD 0
v_run_simulation_q_head_box: DD 0
v_run_simulation_q_tail_box: DD 0
v_run_simulation_total_wait: DD 0
v_run_simulation_total_turn: DD 0
v_run_simulation_scheduler_calls: DD 0
v_run_simulation_dispatches_box: DD 0
v_run_simulation_candidate: DD 0
v_run_simulation_timeline: RESB 256
v_run_simulation_cpu_pc_box: DD 0
v_run_simulation_cpu_acc_box: DD 0

[section data_meta]
__spo5_meta_magic: DB "SPO5META"
__spo5_meta_json: DB "{\"types\":[],\"subprograms\":[{\"name\":\"putc\",\"symbols\":[{\"name\":\"ch\",\"label\":\"v_putc_ch\",\"type\":\"int\",\"isParam\":true}]},{\"name\":\"nl\",\"symbols\":[]},{\"name\":\"emit_space\",\"symbols\":[]},{\"name\":\"print_number\",\"symbols\":[{\"name\":\"n\",\"label\":\"v_print_number_n\",\"type\":\"int\",\"isParam\":true}]},{\"name\":\"print_label_fcfs\",\"symbols\":[]},{\"name\":\"print_label_spn\",\"symbols\":[]},{\"name\":\"print_pair_label\",\"symbols\":[{\"name\":\"a\",\"label\":\"v_print_pair_label_a\",\"type\":\"int\",\"isParam\":true},{\"name\":\"b\",\"label\":\"v_print_pair_label_b\",\"type\":\"int\",\"isParam\":true}]},{\"name\":\"print_vector\",\"symbols\":[{\"name\":\"values\",\"label\":\"v_print_vector_values\",\"type\":\"int array[64]\",\"isParam\":true},{\"name\":\"count\",\"label\":\"v_print_vector_count\",\"type\":\"int\",\"isParam\":true}]},{\"name\":\"load_workload\",\"symbols\":[{\"name\":\"arrival\",\"label\":\"v_load_workload_arrival\",\"type\":\"int array[8]\",\"isParam\":true},{\"name\":\"burst\",\"label\":\"v_load_workload_burst\",\"type\":\"int array[8]\",\"isParam\":true},{\"name\":\"count\",\"label\":\"v_load_workload_count\",\"type\":\"int array[1]\",\"isParam\":true}]},{\"name\":\"enqueue_fcfs\",\"symbols\":[{\"name\":\"queue\",\"label\":\"v_enqueue_fcfs_queue\",\"type\":\"int array[8]\",\"isParam\":true},{\"name\":\"tail_box\",\"label\":\"v_enqueue_fcfs_tail_box\",\"type\":\"int array[1]\",\"isParam\":true},{\"name\":\"task\",\"label\":\"v_enqueue_fcfs_task\",\"type\":\"int\",\"isParam\":true}]},{\"name\":\"pick_fcfs\",\"symbols\":[{\"name\":\"queue\",\"label\":\"v_pick_fcfs_queue\",\"type\":\"int array[8]\",\"isParam\":true},{\"name\":\"head_box\",\"label\":\"v_pick_fcfs_head_box\",\"type\":\"int array[1]\",\"isParam\":true},{\"name\":\"tail_box\",\"label\":\"v_pick_fcfs_tail_box\",\"type\":\"int array[1]\",\"isParam\":true}]},{\"name\":\"select_spn\",\"symbols\":[{\"name\":\"count\",\"label\":\"v_select_spn_count\",\"type\":\"int\",\"isParam\":true},{\"name\":\"state\",\"label\":\"v_select_spn_state\",\"type\":\"int array[8]\",\"isParam\":true},{\"name\":\"burst\",\"label\":\"v_select_spn_burst\",\"type\":\"int array[8]\",\"isParam\":true},{\"name\":\"arrival\",\"label\":\"v_select_spn_arrival\",\"type\":\"int array[8]\",\"isParam\":true}]},{\"name\":\"restore_pc\",\"symbols\":[{\"name\":\"task\",\"label\":\"v_restore_pc_task\",\"type\":\"int\",\"isParam\":true},{\"name\":\"saved_pc\",\"label\":\"v_restore_pc_saved_pc\",\"type\":\"int array[8]\",\"isParam\":true}]},{\"name\":\"restore_acc\",\"symbols\":[{\"name\":\"task\",\"label\":\"v_restore_acc_task\",\"type\":\"int\",\"isParam\":true},{\"name\":\"saved_acc\",\"label\":\"v_restore_acc_saved_acc\",\"type\":\"int array[8]\",\"isParam\":true}]},{\"name\":\"save_context\",\"symbols\":[{\"name\":\"task\",\"label\":\"v_save_context_task\",\"type\":\"int\",\"isParam\":true},{\"name\":\"cpu_pc\",\"label\":\"v_save_context_cpu_pc\",\"type\":\"int\",\"isParam\":true},{\"name\":\"cpu_acc\",\"label\":\"v_save_context_cpu_acc\",\"type\":\"int\",\"isParam\":true},{\"name\":\"saved_pc\",\"label\":\"v_save_context_saved_pc\",\"type\":\"int array[8]\",\"isParam\":true},{\"name\":\"saved_acc\",\"label\":\"v_save_context_saved_acc\",\"type\":\"int array[8]\",\"isParam\":true}]},{\"name\":\"mark_dispatch\",\"symbols\":[{\"name\":\"task\",\"label\":\"v_mark_dispatch_task\",\"type\":\"int\",\"isParam\":true},{\"name\":\"time\",\"label\":\"v_mark_dispatch_time\",\"type\":\"int\",\"isParam\":true},{\"name\":\"start_time\",\"label\":\"v_mark_dispatch_start_time\",\"type\":\"int array[8]\",\"isParam\":true},{\"name\":\"state\",\"label\":\"v_mark_dispatch_state\",\"type\":\"int array[8]\",\"isParam\":true},{\"name\":\"dispatches_box\",\"label\":\"v_mark_dispatch_dispatches_box\",\"type\":\"int array[1]\",\"isParam\":true}]},{\"name\":\"execute_tick\",\"symbols\":[{\"name\":\"task\",\"label\":\"v_execute_tick_task\",\"type\":\"int\",\"isParam\":true},{\"name\":\"time\",\"label\":\"v_execute_tick_time\",\"type\":\"int\",\"isParam\":true},{\"name\":\"timeline\",\"label\":\"v_execute_tick_timeline\",\"type\":\"int array[64]\",\"isParam\":true},{\"name\":\"cpu_pc_box\",\"label\":\"v_execute_tick_cpu_pc_box\",\"type\":\"int array[1]\",\"isParam\":true},{\"name\":\"cpu_acc_box\",\"label\":\"v_execute_tick_cpu_acc_box\",\"type\":\"int array[1]\",\"isParam\":true},{\"name\":\"remaining\",\"label\":\"v_execute_tick_remaining\",\"type\":\"int array[8]\",\"isParam\":true},{\"name\":\"saved_pc\",\"label\":\"v_execute_tick_saved_pc\",\"type\":\"int array[8]\",\"isParam\":true},{\"name\":\"saved_acc\",\"label\":\"v_execute_tick_saved_acc\",\"type\":\"int array[8]\",\"isParam\":true}]},{\"name\":\"finish_task\",\"symbols\":[{\"name\":\"task\",\"label\":\"v_finish_task_task\",\"type\":\"int\",\"isParam\":true},{\"name\":\"time\",\"label\":\"v_finish_task_time\",\"type\":\"int\",\"isParam\":true},{\"name\":\"cpu_acc\",\"label\":\"v_finish_task_cpu_acc\",\"type\":\"int\",\"isParam\":true},{\"name\":\"finish_time\",\"label\":\"v_finish_task_finish_time\",\"type\":\"int array[8]\",\"isParam\":true},{\"name\":\"checksum\",\"label\":\"v_finish_task_checksum\",\"type\":\"int array[8]\",\"isParam\":true},{\"name\":\"state\",\"label\":\"v_finish_task_state\",\"type\":\"int array[8]\",\"isParam\":true},{\"name\":\"completed_box\",\"label\":\"v_finish_task_completed_box\",\"type\":\"int array[1]\",\"isParam\":true}]},{\"name\":\"run_simulation\",\"symbols\":[{\"name\":\"algo\",\"label\":\"v_run_simulation_algo\",\"type\":\"int\",\"isParam\":true}]},{\"name\":\"main\",\"symbols\":[]}]}"

[section code]
main:
  ENTER 0
  JMP main_B2

main_B2:
  PUSH_CONST k3
  CALL run_simulation, 1
  POP
  JMP main_B3

main_B3:
  PUSH_CONST k13
  CALL run_simulation, 1
  POP
  JMP main_exit

main_exit:
  PUSH_CONST k0
  LEAVE
  RET

putc:
  STORE v_putc_ch
  ENTER 4
  JMP putc_B2

putc_B2:
  LOAD v_putc_ch
  CALL print, 1
  POP
  JMP putc_exit

putc_exit:
  PUSH_CONST k0
  LEAVE
  RETF

nl:
  ENTER 0
  JMP nl_B2

nl_B2:
  PUSH_CONST k1
  CALL putc, 1
  POP
  JMP nl_exit

nl_exit:
  PUSH_CONST k0
  LEAVE
  RETF

emit_space:
  ENTER 0
  JMP emit_space_B2

emit_space_B2:
  PUSH_CONST k2
  CALL putc, 1
  POP
  JMP emit_space_exit

emit_space_exit:
  PUSH_CONST k0
  LEAVE
  RETF

print_number:
  STORE v_print_number_n
  ENTER 268
  JMP print_number_B2

print_number_B2:
  LOAD v_print_number_n
  PUSH_CONST k0
  EQ
  JZ print_number_B4
  JMP print_number_B3

print_number_B4:
  PUSH_CONST k0
  STORE v_print_number_cnt
  JMP print_number_B5

print_number_B5:
  LOAD v_print_number_n
  STORE v_print_number_tmp
  JMP print_number_B6

print_number_B6:
  LOAD v_print_number_tmp
  PUSH_CONST k0
  GT
  JZ print_number_B7
  JMP print_number_B8

print_number_B8:
  PUSH_ADDR v_print_number_digits
  LOAD v_print_number_cnt
  INDEX
  LOAD v_print_number_tmp
  PUSH_CONST k1
  REM
  STORE_IND
  JMP print_number_B9

print_number_B9:
  LOAD v_print_number_cnt
  PUSH_CONST k3
  ADD
  STORE v_print_number_cnt
  JMP print_number_B10

print_number_B10:
  LOAD v_print_number_tmp
  PUSH_CONST k1
  DIV
  STORE v_print_number_tmp
  JMP print_number_B6

print_number_B7:
  JMP print_number_B11

print_number_B11:
  LOAD v_print_number_cnt
  PUSH_CONST k0
  GT
  JZ print_number_B12
  JMP print_number_B13

print_number_B13:
  LOAD v_print_number_cnt
  PUSH_CONST k3
  SUB
  STORE v_print_number_cnt
  JMP print_number_B14

print_number_B14:
  PUSH_ADDR v_print_number_digits
  LOAD v_print_number_cnt
  INDEX
  LOAD_IND
  PUSH_CONST k4
  ADD
  CALL putc, 1
  POP
  JMP print_number_B11

print_number_B12:
  JMP print_number_B15

print_number_B3:
  PUSH_CONST k4
  CALL putc, 1
  POP
  JMP print_number_B15

print_number_B15:
  JMP print_number_exit

print_number_exit:
  PUSH_CONST k0
  LEAVE
  RETF

print_label_fcfs:
  ENTER 0
  JMP print_label_fcfs_B2

print_label_fcfs_B2:
  PUSH_CONST k5
  CALL putc, 1
  POP
  JMP print_label_fcfs_B3

print_label_fcfs_B3:
  PUSH_CONST k6
  CALL putc, 1
  POP
  JMP print_label_fcfs_B4

print_label_fcfs_B4:
  PUSH_CONST k5
  CALL putc, 1
  POP
  JMP print_label_fcfs_B5

print_label_fcfs_B5:
  PUSH_CONST k7
  CALL putc, 1
  POP
  JMP print_label_fcfs_B6

print_label_fcfs_B6:
  CALL nl, 0
  POP
  JMP print_label_fcfs_exit

print_label_fcfs_exit:
  PUSH_CONST k0
  LEAVE
  RETF

print_label_spn:
  ENTER 0
  JMP print_label_spn_B2

print_label_spn_B2:
  PUSH_CONST k7
  CALL putc, 1
  POP
  JMP print_label_spn_B3

print_label_spn_B3:
  PUSH_CONST k8
  CALL putc, 1
  POP
  JMP print_label_spn_B4

print_label_spn_B4:
  PUSH_CONST k9
  CALL putc, 1
  POP
  JMP print_label_spn_B5

print_label_spn_B5:
  CALL nl, 0
  POP
  JMP print_label_spn_exit

print_label_spn_exit:
  PUSH_CONST k0
  LEAVE
  RETF

print_pair_label:
  STORE v_print_pair_label_b
  STORE v_print_pair_label_a
  ENTER 8
  JMP print_pair_label_B2

print_pair_label_B2:
  LOAD v_print_pair_label_a
  CALL putc, 1
  POP
  JMP print_pair_label_B3

print_pair_label_B3:
  LOAD v_print_pair_label_b
  PUSH_CONST k0
  NE
  JZ print_pair_label_B5
  JMP print_pair_label_B4

print_pair_label_B4:
  LOAD v_print_pair_label_b
  CALL putc, 1
  POP
  JMP print_pair_label_B5

print_pair_label_B5:
  JMP print_pair_label_B6

print_pair_label_B6:
  PUSH_CONST k10
  CALL putc, 1
  POP
  JMP print_pair_label_B7

print_pair_label_B7:
  CALL emit_space, 0
  POP
  JMP print_pair_label_exit

print_pair_label_exit:
  PUSH_CONST k0
  LEAVE
  RETF

print_vector:
  STORE v_print_vector_count
  STORE v_print_vector_values
  ENTER 264
  JMP print_vector_B2

print_vector_B2:
  PUSH_CONST k0
  STORE v_print_vector_i
  JMP print_vector_B3

print_vector_B3:
  LOAD v_print_vector_i
  LOAD v_print_vector_count
  LT
  JZ print_vector_B4
  JMP print_vector_B5

print_vector_B5:
  LOAD v_print_vector_i
  PUSH_CONST k0
  GT
  JZ print_vector_B7
  JMP print_vector_B6

print_vector_B6:
  CALL emit_space, 0
  POP
  JMP print_vector_B7

print_vector_B7:
  JMP print_vector_B8

print_vector_B8:
  LOAD v_print_vector_values
  LOAD v_print_vector_i
  INDEX
  LOAD_IND
  CALL print_number, 1
  POP
  JMP print_vector_B9

print_vector_B9:
  LOAD v_print_vector_i
  PUSH_CONST k3
  ADD
  STORE v_print_vector_i
  JMP print_vector_B3

print_vector_B4:
  JMP print_vector_B10

print_vector_B10:
  CALL nl, 0
  POP
  JMP print_vector_exit

print_vector_exit:
  PUSH_CONST k0
  LEAVE
  RETF

load_workload:
  STORE v_load_workload_count
  STORE v_load_workload_burst
  STORE v_load_workload_arrival
  ENTER 52
  JMP load_workload_B2

load_workload_B2:
  LOAD v_load_workload_count
  PUSH_CONST k0
  INDEX
  PUSH_CONST k11
  STORE_IND
  JMP load_workload_B3

load_workload_B3:
  LOAD v_load_workload_arrival
  PUSH_CONST k0
  INDEX
  PUSH_CONST k0
  STORE_IND
  JMP load_workload_B4

load_workload_B4:
  LOAD v_load_workload_arrival
  PUSH_CONST k3
  INDEX
  PUSH_CONST k12
  STORE_IND
  JMP load_workload_B5

load_workload_B5:
  LOAD v_load_workload_arrival
  PUSH_CONST k13
  INDEX
  PUSH_CONST k11
  STORE_IND
  JMP load_workload_B6

load_workload_B6:
  LOAD v_load_workload_arrival
  PUSH_CONST k12
  INDEX
  PUSH_CONST k14
  STORE_IND
  JMP load_workload_B7

load_workload_B7:
  LOAD v_load_workload_arrival
  PUSH_CONST k15
  INDEX
  PUSH_CONST k16
  STORE_IND
  JMP load_workload_B8

load_workload_B8:
  LOAD v_load_workload_arrival
  PUSH_CONST k17
  INDEX
  PUSH_CONST k18
  STORE_IND
  JMP load_workload_B9

load_workload_B9:
  LOAD v_load_workload_burst
  PUSH_CONST k0
  INDEX
  PUSH_CONST k15
  STORE_IND
  JMP load_workload_B10

load_workload_B10:
  LOAD v_load_workload_burst
  PUSH_CONST k3
  INDEX
  PUSH_CONST k15
  STORE_IND
  JMP load_workload_B11

load_workload_B11:
  LOAD v_load_workload_burst
  PUSH_CONST k13
  INDEX
  PUSH_CONST k19
  STORE_IND
  JMP load_workload_B12

load_workload_B12:
  LOAD v_load_workload_burst
  PUSH_CONST k12
  INDEX
  PUSH_CONST k19
  STORE_IND
  JMP load_workload_B13

load_workload_B13:
  LOAD v_load_workload_burst
  PUSH_CONST k15
  INDEX
  PUSH_CONST k15
  STORE_IND
  JMP load_workload_B14

load_workload_B14:
  LOAD v_load_workload_burst
  PUSH_CONST k17
  INDEX
  PUSH_CONST k15
  STORE_IND
  JMP load_workload_exit

load_workload_exit:
  PUSH_CONST k0
  LEAVE
  RETF

enqueue_fcfs:
  STORE v_enqueue_fcfs_task
  STORE v_enqueue_fcfs_tail_box
  STORE v_enqueue_fcfs_queue
  ENTER 264
  JMP enqueue_fcfs_B2

enqueue_fcfs_B2:
  LOAD v_enqueue_fcfs_queue
  LOAD v_enqueue_fcfs_tail_box
  PUSH_CONST k0
  INDEX
  LOAD_IND
  INDEX
  LOAD v_enqueue_fcfs_task
  STORE_IND
  JMP enqueue_fcfs_B3

enqueue_fcfs_B3:
  LOAD v_enqueue_fcfs_tail_box
  PUSH_CONST k0
  INDEX
  LOAD v_enqueue_fcfs_tail_box
  PUSH_CONST k0
  INDEX
  LOAD_IND
  PUSH_CONST k3
  ADD
  STORE_IND
  JMP enqueue_fcfs_exit

enqueue_fcfs_exit:
  PUSH_CONST k0
  LEAVE
  RETF

pick_fcfs:
  STORE v_pick_fcfs_tail_box
  STORE v_pick_fcfs_head_box
  STORE v_pick_fcfs_queue
  ENTER 268
  JMP pick_fcfs_B2

pick_fcfs_B2:
  LOAD v_pick_fcfs_head_box
  PUSH_CONST k0
  INDEX
  LOAD_IND
  LOAD v_pick_fcfs_tail_box
  PUSH_CONST k0
  INDEX
  LOAD_IND
  LT
  JZ pick_fcfs_B5
  JMP pick_fcfs_B3

pick_fcfs_B5:
  PUSH_CONST k0
  PUSH_CONST k3
  SUB
  STORE v_pick_fcfs_result
  JMP pick_fcfs_B6

pick_fcfs_B3:
  LOAD v_pick_fcfs_queue
  LOAD v_pick_fcfs_head_box
  PUSH_CONST k0
  INDEX
  LOAD_IND
  INDEX
  LOAD_IND
  STORE v_pick_fcfs_result
  JMP pick_fcfs_B4

pick_fcfs_B4:
  LOAD v_pick_fcfs_head_box
  PUSH_CONST k0
  INDEX
  LOAD v_pick_fcfs_head_box
  PUSH_CONST k0
  INDEX
  LOAD_IND
  PUSH_CONST k3
  ADD
  STORE_IND
  JMP pick_fcfs_B6

pick_fcfs_B6:
  JMP pick_fcfs_exit

pick_fcfs_exit:
  LOAD v_pick_fcfs_result
  LEAVE
  RETF

select_spn:
  STORE v_select_spn_arrival
  STORE v_select_spn_burst
  STORE v_select_spn_state
  STORE v_select_spn_count
  ENTER 784
  JMP select_spn_B2

select_spn_B2:
  PUSH_CONST k0
  PUSH_CONST k3
  SUB
  STORE v_select_spn_best
  JMP select_spn_B3

select_spn_B3:
  PUSH_CONST k0
  STORE v_select_spn_i
  JMP select_spn_B4

select_spn_B4:
  LOAD v_select_spn_i
  LOAD v_select_spn_count
  LT
  JZ select_spn_B5
  JMP select_spn_B6

select_spn_B6:
  LOAD v_select_spn_state
  LOAD v_select_spn_i
  INDEX
  LOAD_IND
  PUSH_CONST k3
  EQ
  JZ select_spn_B16
  JMP select_spn_B7

select_spn_B7:
  LOAD v_select_spn_best
  PUSH_CONST k0
  PUSH_CONST k3
  SUB
  EQ
  JZ select_spn_B9
  JMP select_spn_B8

select_spn_B8:
  LOAD v_select_spn_i
  STORE v_select_spn_best
  JMP select_spn_B15

select_spn_B15:
  JMP select_spn_B16

select_spn_B16:
  JMP select_spn_B17

select_spn_B17:
  LOAD v_select_spn_i
  PUSH_CONST k3
  ADD
  STORE v_select_spn_i
  JMP select_spn_B4

select_spn_B9:
  LOAD v_select_spn_burst
  LOAD v_select_spn_i
  INDEX
  LOAD_IND
  LOAD v_select_spn_burst
  LOAD v_select_spn_best
  INDEX
  LOAD_IND
  LT
  JZ select_spn_B11
  JMP select_spn_B10

select_spn_B10:
  LOAD v_select_spn_i
  STORE v_select_spn_best
  JMP select_spn_B14

select_spn_B14:
  JMP select_spn_B15

select_spn_B11:
  LOAD v_select_spn_burst
  LOAD v_select_spn_i
  INDEX
  LOAD_IND
  LOAD v_select_spn_burst
  LOAD v_select_spn_best
  INDEX
  LOAD_IND
  EQ
  LOAD v_select_spn_arrival
  LOAD v_select_spn_i
  INDEX
  LOAD_IND
  LOAD v_select_spn_arrival
  LOAD v_select_spn_best
  INDEX
  LOAD_IND
  LT
  AND_OP
  JZ select_spn_B13
  JMP select_spn_B12

select_spn_B12:
  LOAD v_select_spn_i
  STORE v_select_spn_best
  JMP select_spn_B13

select_spn_B13:
  JMP select_spn_B14

select_spn_B5:
  JMP select_spn_B18

select_spn_B18:
  LOAD v_select_spn_best
  STORE v_select_spn_result
  JMP select_spn_exit

select_spn_exit:
  LOAD v_select_spn_result
  LEAVE
  RETF

restore_pc:
  STORE v_restore_pc_saved_pc
  STORE v_restore_pc_task
  ENTER 264
  JMP restore_pc_B2

restore_pc_B2:
  LOAD v_restore_pc_saved_pc
  LOAD v_restore_pc_task
  INDEX
  LOAD_IND
  STORE v_restore_pc_result
  JMP restore_pc_exit

restore_pc_exit:
  LOAD v_restore_pc_result
  LEAVE
  RETF

restore_acc:
  STORE v_restore_acc_saved_acc
  STORE v_restore_acc_task
  ENTER 264
  JMP restore_acc_B2

restore_acc_B2:
  LOAD v_restore_acc_saved_acc
  LOAD v_restore_acc_task
  INDEX
  LOAD_IND
  STORE v_restore_acc_result
  JMP restore_acc_exit

restore_acc_exit:
  LOAD v_restore_acc_result
  LEAVE
  RETF

save_context:
  STORE v_save_context_saved_acc
  STORE v_save_context_saved_pc
  STORE v_save_context_cpu_acc
  STORE v_save_context_cpu_pc
  STORE v_save_context_task
  ENTER 524
  JMP save_context_B2

save_context_B2:
  LOAD v_save_context_saved_pc
  LOAD v_save_context_task
  INDEX
  LOAD v_save_context_cpu_pc
  STORE_IND
  JMP save_context_B3

save_context_B3:
  LOAD v_save_context_saved_acc
  LOAD v_save_context_task
  INDEX
  LOAD v_save_context_cpu_acc
  STORE_IND
  JMP save_context_exit

save_context_exit:
  PUSH_CONST k0
  LEAVE
  RETF

mark_dispatch:
  STORE v_mark_dispatch_dispatches_box
  STORE v_mark_dispatch_state
  STORE v_mark_dispatch_start_time
  STORE v_mark_dispatch_time
  STORE v_mark_dispatch_task
  ENTER 524
  JMP mark_dispatch_B2

mark_dispatch_B2:
  LOAD v_mark_dispatch_start_time
  LOAD v_mark_dispatch_task
  INDEX
  LOAD_IND
  PUSH_CONST k0
  PUSH_CONST k3
  SUB
  EQ
  JZ mark_dispatch_B4
  JMP mark_dispatch_B3

mark_dispatch_B3:
  LOAD v_mark_dispatch_start_time
  LOAD v_mark_dispatch_task
  INDEX
  LOAD v_mark_dispatch_time
  STORE_IND
  JMP mark_dispatch_B4

mark_dispatch_B4:
  JMP mark_dispatch_B5

mark_dispatch_B5:
  LOAD v_mark_dispatch_state
  LOAD v_mark_dispatch_task
  INDEX
  PUSH_CONST k13
  STORE_IND
  JMP mark_dispatch_B6

mark_dispatch_B6:
  LOAD v_mark_dispatch_dispatches_box
  PUSH_CONST k0
  INDEX
  LOAD v_mark_dispatch_dispatches_box
  PUSH_CONST k0
  INDEX
  LOAD_IND
  PUSH_CONST k3
  ADD
  STORE_IND
  JMP mark_dispatch_exit

mark_dispatch_exit:
  PUSH_CONST k0
  LEAVE
  RETF

execute_tick:
  STORE v_execute_tick_saved_acc
  STORE v_execute_tick_saved_pc
  STORE v_execute_tick_remaining
  STORE v_execute_tick_cpu_acc_box
  STORE v_execute_tick_cpu_pc_box
  STORE v_execute_tick_timeline
  STORE v_execute_tick_time
  STORE v_execute_tick_task
  ENTER 592
  JMP execute_tick_B2

execute_tick_B2:
  LOAD v_execute_tick_timeline
  LOAD v_execute_tick_time
  INDEX
  LOAD v_execute_tick_task
  PUSH_CONST k3
  ADD
  STORE_IND
  JMP execute_tick_B3

execute_tick_B3:
  LOAD v_execute_tick_cpu_acc_box
  PUSH_CONST k0
  INDEX
  LOAD v_execute_tick_cpu_acc_box
  PUSH_CONST k0
  INDEX
  LOAD_IND
  LOAD v_execute_tick_task
  PUSH_CONST k3
  ADD
  PUSH_CONST k20
  MUL
  ADD
  LOAD v_execute_tick_cpu_pc_box
  PUSH_CONST k0
  INDEX
  LOAD_IND
  ADD
  STORE_IND
  JMP execute_tick_B4

execute_tick_B4:
  LOAD v_execute_tick_cpu_pc_box
  PUSH_CONST k0
  INDEX
  LOAD v_execute_tick_cpu_pc_box
  PUSH_CONST k0
  INDEX
  LOAD_IND
  PUSH_CONST k3
  ADD
  STORE_IND
  JMP execute_tick_B5

execute_tick_B5:
  LOAD v_execute_tick_remaining
  LOAD v_execute_tick_task
  INDEX
  LOAD v_execute_tick_remaining
  LOAD v_execute_tick_task
  INDEX
  LOAD_IND
  PUSH_CONST k3
  SUB
  STORE_IND
  JMP execute_tick_B6

execute_tick_B6:
  LOAD v_execute_tick_task
  LOAD v_execute_tick_cpu_pc_box
  PUSH_CONST k0
  INDEX
  LOAD_IND
  LOAD v_execute_tick_cpu_acc_box
  PUSH_CONST k0
  INDEX
  LOAD_IND
  LOAD v_execute_tick_saved_pc
  LOAD v_execute_tick_saved_acc
  CALL save_context, 5
  POP
  JMP execute_tick_exit

execute_tick_exit:
  PUSH_CONST k0
  LEAVE
  RETF

finish_task:
  STORE v_finish_task_completed_box
  STORE v_finish_task_state
  STORE v_finish_task_checksum
  STORE v_finish_task_finish_time
  STORE v_finish_task_cpu_acc
  STORE v_finish_task_time
  STORE v_finish_task_task
  ENTER 784
  JMP finish_task_B2

finish_task_B2:
  LOAD v_finish_task_finish_time
  LOAD v_finish_task_task
  INDEX
  LOAD v_finish_task_time
  PUSH_CONST k3
  ADD
  STORE_IND
  JMP finish_task_B3

finish_task_B3:
  LOAD v_finish_task_checksum
  LOAD v_finish_task_task
  INDEX
  LOAD v_finish_task_cpu_acc
  STORE_IND
  JMP finish_task_B4

finish_task_B4:
  LOAD v_finish_task_state
  LOAD v_finish_task_task
  INDEX
  PUSH_CONST k12
  STORE_IND
  JMP finish_task_B5

finish_task_B5:
  LOAD v_finish_task_completed_box
  PUSH_CONST k0
  INDEX
  LOAD v_finish_task_completed_box
  PUSH_CONST k0
  INDEX
  LOAD_IND
  PUSH_CONST k3
  ADD
  STORE_IND
  JMP finish_task_exit

finish_task_exit:
  PUSH_CONST k0
  LEAVE
  RETF

run_simulation:
  STORE v_run_simulation_algo
  ENTER 3404
  JMP run_simulation_B2

run_simulation_B2:
  PUSH_ADDR v_run_simulation_arrival
  PUSH_ADDR v_run_simulation_burst
  PUSH_ADDR v_run_simulation_count_box
  CALL load_workload, 3
  POP
  JMP run_simulation_B3

run_simulation_B3:
  PUSH_ADDR v_run_simulation_count_box
  PUSH_CONST k0
  INDEX
  LOAD_IND
  STORE v_run_simulation_count
  JMP run_simulation_B4

run_simulation_B4:
  PUSH_CONST k0
  STORE v_run_simulation_i
  JMP run_simulation_B5

run_simulation_B5:
  LOAD v_run_simulation_i
  LOAD v_run_simulation_count
  LT
  JZ run_simulation_B6
  JMP run_simulation_B7

run_simulation_B7:
  PUSH_ADDR v_run_simulation_remaining
  LOAD v_run_simulation_i
  INDEX
  PUSH_ADDR v_run_simulation_burst
  LOAD v_run_simulation_i
  INDEX
  LOAD_IND
  STORE_IND
  JMP run_simulation_B8

run_simulation_B8:
  PUSH_ADDR v_run_simulation_start_time
  LOAD v_run_simulation_i
  INDEX
  PUSH_CONST k0
  PUSH_CONST k3
  SUB
  STORE_IND
  JMP run_simulation_B9

run_simulation_B9:
  PUSH_ADDR v_run_simulation_finish_time
  LOAD v_run_simulation_i
  INDEX
  PUSH_CONST k0
  PUSH_CONST k3
  SUB
  STORE_IND
  JMP run_simulation_B10

run_simulation_B10:
  PUSH_ADDR v_run_simulation_state
  LOAD v_run_simulation_i
  INDEX
  PUSH_CONST k0
  STORE_IND
  JMP run_simulation_B11

run_simulation_B11:
  PUSH_ADDR v_run_simulation_saved_pc
  LOAD v_run_simulation_i
  INDEX
  PUSH_CONST k0
  STORE_IND
  JMP run_simulation_B12

run_simulation_B12:
  PUSH_ADDR v_run_simulation_saved_acc
  LOAD v_run_simulation_i
  INDEX
  PUSH_CONST k0
  STORE_IND
  JMP run_simulation_B13

run_simulation_B13:
  PUSH_ADDR v_run_simulation_checksum
  LOAD v_run_simulation_i
  INDEX
  PUSH_CONST k0
  STORE_IND
  JMP run_simulation_B14

run_simulation_B14:
  PUSH_ADDR v_run_simulation_wait_time
  LOAD v_run_simulation_i
  INDEX
  PUSH_CONST k0
  STORE_IND
  JMP run_simulation_B15

run_simulation_B15:
  PUSH_ADDR v_run_simulation_turn_time
  LOAD v_run_simulation_i
  INDEX
  PUSH_CONST k0
  STORE_IND
  JMP run_simulation_B16

run_simulation_B16:
  PUSH_ADDR v_run_simulation_queue
  LOAD v_run_simulation_i
  INDEX
  PUSH_CONST k0
  STORE_IND
  JMP run_simulation_B17

run_simulation_B17:
  LOAD v_run_simulation_i
  PUSH_CONST k3
  ADD
  STORE v_run_simulation_i
  JMP run_simulation_B5

run_simulation_B6:
  JMP run_simulation_B18

run_simulation_B18:
  PUSH_CONST k0
  STORE v_run_simulation_time
  JMP run_simulation_B19

run_simulation_B19:
  PUSH_CONST k0
  STORE v_run_simulation_next_arrival
  JMP run_simulation_B20

run_simulation_B20:
  PUSH_CONST k0
  PUSH_CONST k3
  SUB
  STORE v_run_simulation_current
  JMP run_simulation_B21

run_simulation_B21:
  PUSH_CONST k0
  STORE v_run_simulation_cpu_pc
  JMP run_simulation_B22

run_simulation_B22:
  PUSH_CONST k0
  STORE v_run_simulation_cpu_acc
  JMP run_simulation_B23

run_simulation_B23:
  PUSH_ADDR v_run_simulation_completed_box
  PUSH_CONST k0
  INDEX
  PUSH_CONST k0
  STORE_IND
  JMP run_simulation_B24

run_simulation_B24:
  PUSH_ADDR v_run_simulation_q_head_box
  PUSH_CONST k0
  INDEX
  PUSH_CONST k0
  STORE_IND
  JMP run_simulation_B25

run_simulation_B25:
  PUSH_ADDR v_run_simulation_q_tail_box
  PUSH_CONST k0
  INDEX
  PUSH_CONST k0
  STORE_IND
  JMP run_simulation_B26

run_simulation_B26:
  PUSH_CONST k0
  STORE v_run_simulation_total_wait
  JMP run_simulation_B27

run_simulation_B27:
  PUSH_CONST k0
  STORE v_run_simulation_total_turn
  JMP run_simulation_B28

run_simulation_B28:
  PUSH_CONST k0
  STORE v_run_simulation_scheduler_calls
  JMP run_simulation_B29

run_simulation_B29:
  PUSH_ADDR v_run_simulation_dispatches_box
  PUSH_CONST k0
  INDEX
  PUSH_CONST k0
  STORE_IND
  JMP run_simulation_B30

run_simulation_B30:
  LOAD v_run_simulation_algo
  PUSH_CONST k3
  EQ
  JZ run_simulation_B32
  JMP run_simulation_B31

run_simulation_B32:
  CALL print_label_spn, 0
  POP
  JMP run_simulation_B33

run_simulation_B31:
  CALL print_label_fcfs, 0
  POP
  JMP run_simulation_B33

run_simulation_B33:
  JMP run_simulation_B34

run_simulation_B34:
  PUSH_CONST k21
  PUSH_CONST k0
  CALL print_pair_label, 2
  POP
  JMP run_simulation_B35

run_simulation_B35:
  PUSH_ADDR v_run_simulation_arrival
  LOAD v_run_simulation_count
  CALL print_vector, 2
  POP
  JMP run_simulation_B36

run_simulation_B36:
  PUSH_CONST k22
  PUSH_CONST k0
  CALL print_pair_label, 2
  POP
  JMP run_simulation_B37

run_simulation_B37:
  PUSH_ADDR v_run_simulation_burst
  LOAD v_run_simulation_count
  CALL print_vector, 2
  POP
  JMP run_simulation_B38

run_simulation_B38:
  PUSH_ADDR v_run_simulation_completed_box
  PUSH_CONST k0
  INDEX
  LOAD_IND
  LOAD v_run_simulation_count
  LT
  JZ run_simulation_B39
  JMP run_simulation_B40

run_simulation_B40:
  LOAD v_run_simulation_next_arrival
  LOAD v_run_simulation_count
  LT
  PUSH_ADDR v_run_simulation_arrival
  LOAD v_run_simulation_next_arrival
  INDEX
  LOAD_IND
  LOAD v_run_simulation_time
  EQ
  AND_OP
  JZ run_simulation_B41
  JMP run_simulation_B42

run_simulation_B42:
  PUSH_ADDR v_run_simulation_state
  LOAD v_run_simulation_next_arrival
  INDEX
  PUSH_CONST k3
  STORE_IND
  JMP run_simulation_B43

run_simulation_B43:
  LOAD v_run_simulation_algo
  PUSH_CONST k3
  EQ
  JZ run_simulation_B45
  JMP run_simulation_B44

run_simulation_B44:
  PUSH_ADDR v_run_simulation_queue
  PUSH_ADDR v_run_simulation_q_tail_box
  LOAD v_run_simulation_next_arrival
  CALL enqueue_fcfs, 3
  POP
  JMP run_simulation_B45

run_simulation_B45:
  JMP run_simulation_B46

run_simulation_B46:
  LOAD v_run_simulation_next_arrival
  PUSH_CONST k3
  ADD
  STORE v_run_simulation_next_arrival
  JMP run_simulation_B40

run_simulation_B41:
  JMP run_simulation_B47

run_simulation_B47:
  LOAD v_run_simulation_scheduler_calls
  PUSH_CONST k3
  ADD
  STORE v_run_simulation_scheduler_calls
  JMP run_simulation_B48

run_simulation_B48:
  LOAD v_run_simulation_current
  PUSH_CONST k0
  PUSH_CONST k3
  SUB
  EQ
  JZ run_simulation_B59
  JMP run_simulation_B49

run_simulation_B49:
  LOAD v_run_simulation_algo
  PUSH_CONST k3
  EQ
  JZ run_simulation_B51
  JMP run_simulation_B50

run_simulation_B50:
  PUSH_ADDR v_run_simulation_queue
  PUSH_ADDR v_run_simulation_q_head_box
  PUSH_ADDR v_run_simulation_q_tail_box
  CALL pick_fcfs, 3
  STORE v_run_simulation_candidate
  JMP run_simulation_B52

run_simulation_B52:
  JMP run_simulation_B53

run_simulation_B53:
  LOAD v_run_simulation_candidate
  PUSH_CONST k0
  PUSH_CONST k3
  SUB
  NE
  JZ run_simulation_B58
  JMP run_simulation_B54

run_simulation_B54:
  LOAD v_run_simulation_candidate
  STORE v_run_simulation_current
  JMP run_simulation_B55

run_simulation_B55:
  LOAD v_run_simulation_current
  PUSH_ADDR v_run_simulation_saved_pc
  CALL restore_pc, 2
  STORE v_run_simulation_cpu_pc
  JMP run_simulation_B56

run_simulation_B56:
  LOAD v_run_simulation_current
  PUSH_ADDR v_run_simulation_saved_acc
  CALL restore_acc, 2
  STORE v_run_simulation_cpu_acc
  JMP run_simulation_B57

run_simulation_B57:
  LOAD v_run_simulation_current
  LOAD v_run_simulation_time
  PUSH_ADDR v_run_simulation_start_time
  PUSH_ADDR v_run_simulation_state
  PUSH_ADDR v_run_simulation_dispatches_box
  CALL mark_dispatch, 5
  POP
  JMP run_simulation_B58

run_simulation_B58:
  JMP run_simulation_B59

run_simulation_B59:
  JMP run_simulation_B60

run_simulation_B60:
  LOAD v_run_simulation_current
  PUSH_CONST k0
  PUSH_CONST k3
  SUB
  EQ
  JZ run_simulation_B62
  JMP run_simulation_B61

run_simulation_B61:
  PUSH_ADDR v_run_simulation_timeline
  LOAD v_run_simulation_time
  INDEX
  PUSH_CONST k0
  STORE_IND
  JMP run_simulation_B71

run_simulation_B71:
  JMP run_simulation_B72

run_simulation_B72:
  LOAD v_run_simulation_time
  PUSH_CONST k3
  ADD
  STORE v_run_simulation_time
  JMP run_simulation_B38

run_simulation_B62:
  PUSH_ADDR v_run_simulation_cpu_pc_box
  PUSH_CONST k0
  INDEX
  LOAD v_run_simulation_cpu_pc
  STORE_IND
  JMP run_simulation_B63

run_simulation_B63:
  PUSH_ADDR v_run_simulation_cpu_acc_box
  PUSH_CONST k0
  INDEX
  LOAD v_run_simulation_cpu_acc
  STORE_IND
  JMP run_simulation_B64

run_simulation_B64:
  LOAD v_run_simulation_current
  LOAD v_run_simulation_time
  PUSH_ADDR v_run_simulation_timeline
  PUSH_ADDR v_run_simulation_cpu_pc_box
  PUSH_ADDR v_run_simulation_cpu_acc_box
  PUSH_ADDR v_run_simulation_remaining
  PUSH_ADDR v_run_simulation_saved_pc
  PUSH_ADDR v_run_simulation_saved_acc
  CALL execute_tick, 8
  POP
  JMP run_simulation_B65

run_simulation_B65:
  PUSH_ADDR v_run_simulation_cpu_pc_box
  PUSH_CONST k0
  INDEX
  LOAD_IND
  STORE v_run_simulation_cpu_pc
  JMP run_simulation_B66

run_simulation_B66:
  PUSH_ADDR v_run_simulation_cpu_acc_box
  PUSH_CONST k0
  INDEX
  LOAD_IND
  STORE v_run_simulation_cpu_acc
  JMP run_simulation_B67

run_simulation_B67:
  PUSH_ADDR v_run_simulation_remaining
  LOAD v_run_simulation_current
  INDEX
  LOAD_IND
  PUSH_CONST k0
  EQ
  JZ run_simulation_B70
  JMP run_simulation_B68

run_simulation_B68:
  LOAD v_run_simulation_current
  LOAD v_run_simulation_time
  LOAD v_run_simulation_cpu_acc
  PUSH_ADDR v_run_simulation_finish_time
  PUSH_ADDR v_run_simulation_checksum
  PUSH_ADDR v_run_simulation_state
  PUSH_ADDR v_run_simulation_completed_box
  CALL finish_task, 7
  POP
  JMP run_simulation_B69

run_simulation_B69:
  PUSH_CONST k0
  PUSH_CONST k3
  SUB
  STORE v_run_simulation_current
  JMP run_simulation_B70

run_simulation_B70:
  JMP run_simulation_B71

run_simulation_B51:
  LOAD v_run_simulation_count
  PUSH_ADDR v_run_simulation_state
  PUSH_ADDR v_run_simulation_burst
  PUSH_ADDR v_run_simulation_arrival
  CALL select_spn, 4
  STORE v_run_simulation_candidate
  JMP run_simulation_B52

run_simulation_B39:
  JMP run_simulation_B73

run_simulation_B73:
  PUSH_CONST k0
  STORE v_run_simulation_i
  JMP run_simulation_B74

run_simulation_B74:
  LOAD v_run_simulation_i
  LOAD v_run_simulation_count
  LT
  JZ run_simulation_B75
  JMP run_simulation_B76

run_simulation_B76:
  PUSH_ADDR v_run_simulation_wait_time
  LOAD v_run_simulation_i
  INDEX
  PUSH_ADDR v_run_simulation_finish_time
  LOAD v_run_simulation_i
  INDEX
  LOAD_IND
  PUSH_ADDR v_run_simulation_arrival
  LOAD v_run_simulation_i
  INDEX
  LOAD_IND
  SUB
  PUSH_ADDR v_run_simulation_burst
  LOAD v_run_simulation_i
  INDEX
  LOAD_IND
  SUB
  STORE_IND
  JMP run_simulation_B77

run_simulation_B77:
  PUSH_ADDR v_run_simulation_turn_time
  LOAD v_run_simulation_i
  INDEX
  PUSH_ADDR v_run_simulation_finish_time
  LOAD v_run_simulation_i
  INDEX
  LOAD_IND
  PUSH_ADDR v_run_simulation_arrival
  LOAD v_run_simulation_i
  INDEX
  LOAD_IND
  SUB
  STORE_IND
  JMP run_simulation_B78

run_simulation_B78:
  LOAD v_run_simulation_total_wait
  PUSH_ADDR v_run_simulation_wait_time
  LOAD v_run_simulation_i
  INDEX
  LOAD_IND
  ADD
  STORE v_run_simulation_total_wait
  JMP run_simulation_B79

run_simulation_B79:
  LOAD v_run_simulation_total_turn
  PUSH_ADDR v_run_simulation_turn_time
  LOAD v_run_simulation_i
  INDEX
  LOAD_IND
  ADD
  STORE v_run_simulation_total_turn
  JMP run_simulation_B80

run_simulation_B80:
  LOAD v_run_simulation_i
  PUSH_CONST k3
  ADD
  STORE v_run_simulation_i
  JMP run_simulation_B74

run_simulation_B75:
  JMP run_simulation_B81

run_simulation_B81:
  PUSH_CONST k23
  PUSH_CONST k0
  CALL print_pair_label, 2
  POP
  JMP run_simulation_B82

run_simulation_B82:
  PUSH_ADDR v_run_simulation_timeline
  LOAD v_run_simulation_time
  CALL print_vector, 2
  POP
  JMP run_simulation_B83

run_simulation_B83:
  PUSH_CONST k24
  PUSH_CONST k0
  CALL print_pair_label, 2
  POP
  JMP run_simulation_B84

run_simulation_B84:
  PUSH_ADDR v_run_simulation_wait_time
  LOAD v_run_simulation_count
  CALL print_vector, 2
  POP
  JMP run_simulation_B85

run_simulation_B85:
  PUSH_CONST k25
  PUSH_CONST k0
  CALL print_pair_label, 2
  POP
  JMP run_simulation_B86

run_simulation_B86:
  PUSH_ADDR v_run_simulation_turn_time
  LOAD v_run_simulation_count
  CALL print_vector, 2
  POP
  JMP run_simulation_B87

run_simulation_B87:
  PUSH_CONST k21
  PUSH_CONST k24
  CALL print_pair_label, 2
  POP
  JMP run_simulation_B88

run_simulation_B88:
  LOAD v_run_simulation_total_wait
  LOAD v_run_simulation_count
  DIV
  CALL print_number, 1
  POP
  JMP run_simulation_B89

run_simulation_B89:
  CALL nl, 0
  POP
  JMP run_simulation_B90

run_simulation_B90:
  PUSH_CONST k21
  PUSH_CONST k23
  CALL print_pair_label, 2
  POP
  JMP run_simulation_B91

run_simulation_B91:
  LOAD v_run_simulation_total_turn
  LOAD v_run_simulation_count
  DIV
  CALL print_number, 1
  POP
  JMP run_simulation_B92

run_simulation_B92:
  CALL nl, 0
  POP
  JMP run_simulation_B93

run_simulation_B93:
  PUSH_CONST k6
  PUSH_CONST k0
  CALL print_pair_label, 2
  POP
  JMP run_simulation_B94

run_simulation_B94:
  PUSH_ADDR v_run_simulation_checksum
  LOAD v_run_simulation_count
  CALL print_vector, 2
  POP
  JMP run_simulation_B95

run_simulation_B95:
  PUSH_CONST k26
  PUSH_CONST k0
  CALL print_pair_label, 2
  POP
  JMP run_simulation_B96

run_simulation_B96:
  LOAD v_run_simulation_scheduler_calls
  CALL print_number, 1
  POP
  JMP run_simulation_B97

run_simulation_B97:
  CALL nl, 0
  POP
  JMP run_simulation_B98

run_simulation_B98:
  PUSH_CONST k27
  PUSH_CONST k0
  CALL print_pair_label, 2
  POP
  JMP run_simulation_B99

run_simulation_B99:
  PUSH_ADDR v_run_simulation_dispatches_box
  PUSH_CONST k0
  INDEX
  LOAD_IND
  CALL print_number, 1
  POP
  JMP run_simulation_B100

run_simulation_B100:
  CALL nl, 0
  POP
  JMP run_simulation_B101

run_simulation_B101:
  CALL nl, 0
  POP
  JMP run_simulation_exit

run_simulation_exit:
  PUSH_CONST k0
  LEAVE
  RETF

print:
  PUSH_CONST __builtin_one
  SET_PORT
  OUT
  PUSH_CONST __builtin_zero
  RETF

