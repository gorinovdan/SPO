; -------------------------------------------------
; Hybrid runtime (deferred-preemptive mode)
; - timer IRQ stays enabled
; - IRQ handler only bumps tick counter and requests reschedule
; - actual context switch happens only at safe points in normal code
; - core scheduler/IRQ path kept from known-working runtime
; - sync primitives added separately in new memory area
; - non-blocking mutex/semaphore/stream API
; - thread_sleep implemented via tick counter + cooperative yield
; -------------------------------------------------

; Old core memory layout (kept intact):
;   0x00008000 = init_done
;   0x00008008 = started
;   0x00008010 = thread_cnt
;   0x00008018 = current_id
;   0x00008020 = saved SP task0
;   0x00008028 = saved SP task1
;   0x00008030 = saved SP task2
;   0x00008038 = saved SP task3
;   0x00008040 = saved SP task4
;   0x00008048 = saved SP task5
;   0x00008050 = scratch saved R7
;   0x00008058 = scratch restore R7 before RET
;
; Added sync memory layout (new area only):
;   0x00008100 = irq tick counter
;   0x00008108 = legacy sync status scratch (unused)
;   0x00008180 = sync status per-thread[0..7]
;   0x00008110 = stream recv scratch value
;   0x00008118 = need_resched flag (set by timer IRQ, consumed at safe points)
;   0x00008200 = mutex depth[0..7]
;   0x00008240 = mutex owner[0..7]
;   0x00008280 = sem count[0..7]
;   0x00008300 = chan capacity[0..3]
;   0x00008320 = chan head[0..3]
;   0x00008340 = chan tail[0..3]
;   0x00008360 = chan count[0..3]
;   0x00008400 = chan0 buf[16]
;   0x00008480 = chan1 buf[16]
;   0x00008500 = chan2 buf[16]
;   0x00008580 = chan3 buf[16]

; =================================================
; ABI bridge
; =================================================
_func_thread_create:
    MOV R7, FP
    MOV FP, SP
    SUBI q SP, 8
    ST_STACK q R7, stack[FP, -8]

    LD_STACK q R0, stack[FP, 8]
    CALL thread_create

    LD_STACK q R7, stack[FP, -8]
    MOV SP, FP
    MOV FP, R7
    RET

_func_thread_interupt:
    JMP thread_interupt

_func_thread_interrupt:
    JMP thread_interrupt

_func_thread_exit:
    JMP thread_exit

_func_thread_sleep:
    MOV R7, FP
    MOV FP, SP
    SUBI q SP, 8
    ST_STACK q R7, stack[FP, -8]

    LD_STACK q R0, stack[FP, 8]
    CALL thread_sleep

    LD_STACK q R7, stack[FP, -8]
    MOV SP, FP
    MOV FP, R7
    RET

_func_thread_poll:
    CALL thread_poll_resched
    RET

_func_mutex_init:
    MOV R7, FP
    MOV FP, SP
    SUBI q SP, 8
    ST_STACK q R7, stack[FP, -8]

    LD_STACK q R0, stack[FP, 8]
    CALL mutex_init

    LD_STACK q R7, stack[FP, -8]
    MOV SP, FP
    MOV FP, R7
    RET

_func_mutex_lock:
    MOV R7, FP
    MOV FP, SP
    SUBI q SP, 8
    ST_STACK q R7, stack[FP, -8]

    LD_STACK q R0, stack[FP, 8]
    CALL mutex_lock

    LD_STACK q R7, stack[FP, -8]
    MOV SP, FP
    MOV FP, R7
    RET

_func_mutex_unlock:
    MOV R7, FP
    MOV FP, SP
    SUBI q SP, 8
    ST_STACK q R7, stack[FP, -8]

    LD_STACK q R0, stack[FP, 8]
    CALL mutex_unlock

    LD_STACK q R7, stack[FP, -8]
    MOV SP, FP
    MOV FP, R7
    RET

_func_sem_init:
    MOV R7, FP
    MOV FP, SP
    SUBI q SP, 8
    ST_STACK q R7, stack[FP, -8]

    LD_STACK q R0, stack[FP, 8]
    LD_STACK q R1, stack[FP, 16]
    CALL sem_init

    LD_STACK q R7, stack[FP, -8]
    MOV SP, FP
    MOV FP, R7
    RET

_func_sem_wait:
    MOV R7, FP
    MOV FP, SP
    SUBI q SP, 8
    ST_STACK q R7, stack[FP, -8]

    LD_STACK q R0, stack[FP, 8]
    CALL sem_wait

    LD_STACK q R7, stack[FP, -8]
    MOV SP, FP
    MOV FP, R7
    RET

_func_sem_post:
    MOV R7, FP
    MOV FP, SP
    SUBI q SP, 8
    ST_STACK q R7, stack[FP, -8]

    LD_STACK q R0, stack[FP, 8]
    CALL sem_post

    LD_STACK q R7, stack[FP, -8]
    MOV SP, FP
    MOV FP, R7
    RET

_func_stream_init:
    MOV R7, FP
    MOV FP, SP
    SUBI q SP, 8
    ST_STACK q R7, stack[FP, -8]

    LD_STACK q R0, stack[FP, 8]
    LD_STACK q R1, stack[FP, 16]
    CALL stream_init

    LD_STACK q R7, stack[FP, -8]
    MOV SP, FP
    MOV FP, R7
    RET

_func_stream_send:
    MOV R7, FP
    MOV FP, SP
    SUBI q SP, 8
    ST_STACK q R7, stack[FP, -8]

    LD_STACK q R0, stack[FP, 8]
    LD_STACK q R1, stack[FP, 16]
    CALL stream_send

    LD_STACK q R7, stack[FP, -8]
    MOV SP, FP
    MOV FP, R7
    RET

_func_stream_recv:
    MOV R7, FP
    MOV FP, SP
    SUBI q SP, 8
    ST_STACK q R7, stack[FP, -8]

    LD_STACK q R0, stack[FP, 8]
    CALL stream_recv

    LD_STACK q R7, stack[FP, -8]
    MOV SP, FP
    MOV FP, R7
    RET

; Optional aliases for future semantic updates
_func_mutex_try_lock:
    JMP _func_mutex_lock

_func_sem_try_wait:
    JMP _func_sem_wait

_func_stream_try_send:
    JMP _func_stream_send

_func_stream_try_recv:
    JMP _func_stream_recv

_func_sync_status:
    JMP sync_status

_func_stream_status:
    JMP sync_status

_func_sync_chan_init:
    JMP _func_stream_init

_func_sync_chan_send:
    JMP _func_stream_send

_func_sync_chan_recv:
    JMP _func_stream_recv

; =================================================
; Core scheduler (kept as close as possible to known-working runtime)
; =================================================
thread_create:
    PUSHQ R1
    PUSHQ R2
    PUSHQ R3
    PUSHQ R4
    PUSHQ R5
    PUSHQ R6
    PUSHQ R7
    PUSHQ FP

    MOV R5, R0

    LD_DATA q R1, 0x00008000
    LDI32 R2, 0
    CMP q R1, R2
    JNZ thread_create_after_init

thread_create_do_init:
    LDI32 R1, 0
    ST_DATA b R1, 0x1000C
    ST_DATA b R1, 0x10010
    ST_DATA b R1, 0x10014
    ST_DATA q R1, 0x11038
    ST_DATA q R1, 0x11040

    ST_DATA q R1, 0x00008008
    ST_DATA q R1, 0x00008010
    ST_DATA q R1, 0x00008018
    ST_DATA q R1, 0x00008050
    ST_DATA q R1, 0x00008058

    ; init added runtime/sync globals
    ST_DATA q R1, 0x00008100
    ST_DATA q R1, 0x00008110
    ST_DATA q R1, 0x00008118

    ; clear thread_active[0..5]
    ST_DATA q R1, 0x00008120
    ST_DATA q R1, 0x00008128
    ST_DATA q R1, 0x00008130
    ST_DATA q R1, 0x00008138
    ST_DATA q R1, 0x00008140
    ST_DATA q R1, 0x00008148

    ; clear sync_status[0..7]
    ST_DATA q R1, 0x00008180
    ST_DATA q R1, 0x00008188
    ST_DATA q R1, 0x00008190
    ST_DATA q R1, 0x00008198
    ST_DATA q R1, 0x000081A0
    ST_DATA q R1, 0x000081A8
    ST_DATA q R1, 0x000081B0
    ST_DATA q R1, 0x000081B8

    ; clear mutex_depth[0..7]
    ST_DATA q R1, 0x00008200
    ST_DATA q R1, 0x00008208
    ST_DATA q R1, 0x00008210
    ST_DATA q R1, 0x00008218
    ST_DATA q R1, 0x00008220
    ST_DATA q R1, 0x00008228
    ST_DATA q R1, 0x00008230
    ST_DATA q R1, 0x00008238

    ; clear mutex_owner[0..7]
    ST_DATA q R1, 0x00008240
    ST_DATA q R1, 0x00008248
    ST_DATA q R1, 0x00008250
    ST_DATA q R1, 0x00008258
    ST_DATA q R1, 0x00008260
    ST_DATA q R1, 0x00008268
    ST_DATA q R1, 0x00008270
    ST_DATA q R1, 0x00008278

    ; clear sem_count[0..7]
    ST_DATA q R1, 0x00008280
    ST_DATA q R1, 0x00008288
    ST_DATA q R1, 0x00008290
    ST_DATA q R1, 0x00008298
    ST_DATA q R1, 0x000082A0
    ST_DATA q R1, 0x000082A8
    ST_DATA q R1, 0x000082B0
    ST_DATA q R1, 0x000082B8

    ; clear channel metadata[0..3]
    ST_DATA q R1, 0x00008300
    ST_DATA q R1, 0x00008308
    ST_DATA q R1, 0x00008310
    ST_DATA q R1, 0x00008318

    ST_DATA q R1, 0x00008320
    ST_DATA q R1, 0x00008328
    ST_DATA q R1, 0x00008330
    ST_DATA q R1, 0x00008338

    ST_DATA q R1, 0x00008340
    ST_DATA q R1, 0x00008348
    ST_DATA q R1, 0x00008350
    ST_DATA q R1, 0x00008358

    ST_DATA q R1, 0x00008360
    ST_DATA q R1, 0x00008368
    ST_DATA q R1, 0x00008370
    ST_DATA q R1, 0x00008378

    ; keep IRQ vector installed, but timer-driven preemption is disabled in stable mode
    LDI32 R1, thread_irq_handler
    ST_DATA q R1, 0x10108

    LDI32 R1, 1
    ST_DATA q R1, 0x00008000

thread_create_after_init:
    LD_DATA q R1, 0x00008010
    LDI32 R2, 6
    CMP q R1, R2
    JL thread_create_has_slot

thread_create_fail:
    LDI32 R0, 0xFFFFFFFF
    JMP thread_create_return

thread_create_has_slot:
    MOV R0, R1

    LDI32 R2, 0
    CMP q R1, R2
    JNZ tc_check_1
    LDI32 R3, 0x00110000
    SUBI q R3, 88
    ST_DATA q R3, 0x00008020
    JMP tc_build_frame

tc_check_1:
    LDI32 R2, 1
    CMP q R1, R2
    JNZ tc_check_2
    LDI32 R3, 0x00120000
    SUBI q R3, 88
    ST_DATA q R3, 0x00008028
    JMP tc_build_frame

tc_check_2:
    LDI32 R2, 2
    CMP q R1, R2
    JNZ tc_check_3
    LDI32 R3, 0x00130000
    SUBI q R3, 88
    ST_DATA q R3, 0x00008030
    JMP tc_build_frame

tc_check_3:
    LDI32 R2, 3
    CMP q R1, R2
    JNZ tc_check_4
    LDI32 R3, 0x00140000
    SUBI q R3, 88
    ST_DATA q R3, 0x00008038
    JMP tc_build_frame

tc_check_4:
    LDI32 R2, 4
    CMP q R1, R2
    JNZ tc_slot_5
    LDI32 R3, 0x00150000
    SUBI q R3, 88
    ST_DATA q R3, 0x00008040
    JMP tc_build_frame

tc_slot_5:
    LDI32 R3, 0x00160000
    SUBI q R3, 88
    ST_DATA q R3, 0x00008048

tc_build_frame:
    ; [0] FP [8]R7 [16]R6 [24]R5 [32]R4 [40]R3 [48]R2 [56]R1 [64]R0 [72]FLAGS [80]RET-IP
    LDI32 R4, 0
    ST_STACK q R4, stack[R3, 0]
    ST_STACK q R4, stack[R3, 8]
    ST_STACK q R4, stack[R3, 16]
    ST_STACK q R4, stack[R3, 24]
    ST_STACK q R4, stack[R3, 32]
    ST_STACK q R4, stack[R3, 40]
    ST_STACK q R4, stack[R3, 48]
    ST_STACK q R4, stack[R3, 56]
    ST_STACK q R4, stack[R3, 64]
    ST_STACK q R4, stack[R3, 72]
    ST_STACK q R5, stack[R3, 80]
    LDI32 R4, thread_exit_trampoline
    ST_STACK q R4, stack[R3, 88]

    MOV R0, R1
    CALL rt_addr_thread_active
    LDI32 R2, 1
    ST_PTR q R2, [R7, 0]

    LD_DATA q R1, 0x00008010
    ADDI q R1, 1
    ST_DATA q R1, 0x00008010

thread_create_return:
    POPQ FP
    POPQ R7
    POPQ R6
    POPQ R5
    POPQ R4
    POPQ R3
    POPQ R2
    POPQ R1
    RET

thread_interupt:
    JMP thread_interrupt

thread_interrupt:
    LD_DATA q R1, 0x00008010
    LDI32 R2, 0
    CMP q R1, R2
    JNZ thread_interrupt_have_threads
    RET

thread_interrupt_have_threads:
    LD_DATA q R1, 0x00008008
    LDI32 R2, 0
    CMP q R1, R2
    JNZ thread_interrupt_yield

thread_interrupt_start:
    LDI32 R1, 1
    ST_DATA q R1, 0x00008008
    LDI32 R1, 0
    ST_DATA q R1, 0x00008018
    ST_DATA q R1, 0x00008118

    ; deferred-preemptive mode:
    ;   configure periodic timer IRQ, but do not context-switch from IRQ handler
    ;   real switch happens later in safe points via thread_poll_resched/thread_interrupt
    LDI32 R1, 0
    ST_DATA b R1, 0x10014
    LDI32 R1, 1
    ST_DATA b R1, 0x10010
    LDI32 R1, 10000
    ST_DATA q R1, 0x11038

    LD_DATA q SP, 0x00008020

    POPQ FP
    POPQ R7
    POPQ R6
    POPQ R5
    POPQ R4
    POPQ R3
    POPQ R2
    POPQ R1
    POPQ R0
    POPF

    ST_DATA q R7, 0x00008058
    LDI32 R7, 1
    ST_DATA b R7, 0x1000C
    LD_DATA q R7, 0x00008058
    RET

thread_interrupt_yield:
    ST_DATA q R7, 0x00008050

    LDI32 R7, 0
    ST_DATA b R7, 0x1000C

    PUSHF
    PUSHQ R0
    PUSHQ R1
    PUSHQ R2
    PUSHQ R3
    PUSHQ R4
    PUSHQ R5
    PUSHQ R6
    LD_DATA q R7, 0x00008050
    PUSHQ R7
    PUSHQ FP

    LD_DATA q R6, 0x00008018
    LDI32 R1, 0
    CMP q R6, R1
    JNZ py_save_1
    ST_DATA q SP, 0x00008020
    JMP py_choose_next

py_save_1:
    LDI32 R1, 1
    CMP q R6, R1
    JNZ py_save_2
    ST_DATA q SP, 0x00008028
    JMP py_choose_next

py_save_2:
    LDI32 R1, 2
    CMP q R6, R1
    JNZ py_save_3
    ST_DATA q SP, 0x00008030
    JMP py_choose_next

py_save_3:
    LDI32 R1, 3
    CMP q R6, R1
    JNZ py_save_4
    ST_DATA q SP, 0x00008038
    JMP py_choose_next

py_save_4:
    LDI32 R1, 4
    CMP q R6, R1
    JNZ py_save_5
    ST_DATA q SP, 0x00008040
    JMP py_choose_next

py_save_5:
    ST_DATA q SP, 0x00008048

py_choose_next:
    CALL rt_pick_next_active_from_r6
    LDI32 R1, 0xFFFFFFFF
    CMP q R0, R1
    JNZ py_next_ok
    JMP rt_no_active_threads

py_next_ok:
    ST_DATA q R0, 0x00008018

    LDI32 R1, 0
    CMP q R0, R1
    JNZ py_load_1
    LD_DATA q SP, 0x00008020
    JMP py_restore

py_load_1:
    LDI32 R1, 1
    CMP q R0, R1
    JNZ py_load_2
    LD_DATA q SP, 0x00008028
    JMP py_restore

py_load_2:
    LDI32 R1, 2
    CMP q R0, R1
    JNZ py_load_3
    LD_DATA q SP, 0x00008030
    JMP py_restore

py_load_3:
    LDI32 R1, 3
    CMP q R0, R1
    JNZ py_load_4
    LD_DATA q SP, 0x00008038
    JMP py_restore

py_load_4:
    LDI32 R1, 4
    CMP q R0, R1
    JNZ py_load_5
    LD_DATA q SP, 0x00008040
    JMP py_restore

py_load_5:
    LD_DATA q SP, 0x00008048

py_restore:
    LDI32 R1, 0
    ST_DATA q R1, 0x00008118

    POPQ FP
    POPQ R7
    POPQ R6
    POPQ R5
    POPQ R4
    POPQ R3
    POPQ R2
    POPQ R1
    POPQ R0
    POPF

    ST_DATA q R7, 0x00008058
    LDI32 R7, 1
    ST_DATA b R7, 0x1000C
    LD_DATA q R7, 0x00008058
    RET

thread_irq_handler:
    ST_DATA q R7, 0x00008050

    LD_DATA q R7, 0x10000
    PUSHQ R7

    PUSHF
    PUSHQ R0
    PUSHQ R1
    PUSHQ R2
    PUSHQ R3
    PUSHQ R4
    PUSHQ R5
    PUSHQ R6
    LD_DATA q R7, 0x00008050
    PUSHQ R7
    PUSHQ FP

    ; acknowledge timer IRQ
    LDI32 R0, 0
    ST_DATA b R0, 0x10014

    ; tick++
    LD_DATA q R0, 0x00008100
    ADDI q R0, 1
    ST_DATA q R0, 0x00008100

    ; ask for reschedule, but do NOT switch context inside IRQ
    LDI32 R0, 1
    ST_DATA q R0, 0x00008118

    POPQ FP
    POPQ R7
    POPQ R6
    POPQ R5
    POPQ R4
    POPQ R3
    POPQ R2
    POPQ R1
    POPQ R0
    POPF
    RET

; =================================================
; Sync helpers
; =================================================
rt_disable_irq:
    LDI32 R7, 0
    ST_DATA b R7, 0x1000C
    RET

rt_enable_irq_if_started:
    LD_DATA q R7, 0x00008008
    LDI32 R6, 0
    CMP q R7, R6
    JZ rt_enable_irq_if_started_done

    LDI32 R7, 1
    ST_DATA b R7, 0x1000C

    CALL thread_poll_resched

rt_enable_irq_if_started_done:
    RET

thread_poll_resched:
    LD_DATA q R1, 0x00008008
    LDI32 R2, 0
    CMP q R1, R2
    JZ thread_poll_resched_done

    LD_DATA q R1, 0x00008118
    CMP q R1, R2
    JZ thread_poll_resched_done

    CALL thread_interrupt

thread_poll_resched_done:
    RET

; R0=id -> R7=&sync_status[id]
rt_addr_sync_status:
    MOV R7, R0
    LDI32 R6, 8
    MUL q R7, R6
    LDI32 R6, 0x00008180
    ADD q R7, R6
    RET

; in: R0=status ; out R0 preserved
rt_store_sync_status:
    PUSHQ R1
    PUSHQ R2
    MOV R1, R0
    LD_DATA q R0, 0x00008018
    CALL rt_addr_sync_status
    ST_PTR q R1, [R7, 0]
    MOV R0, R1
    POPQ R2
    POPQ R1
    RET

sync_status:
    LD_DATA q R0, 0x00008018
    CALL rt_addr_sync_status
    LD_PTR q R0, [R7, 0]
    RET

; R0=id -> R7=&mutex_depth[id]
rt_addr_mutex_depth:
    MOV R7, R0
    LDI32 R6, 8
    MUL q R7, R6
    LDI32 R6, 0x00008200
    ADD q R7, R6
    RET

; R0=id -> R7=&mutex_owner[id]
rt_addr_mutex_owner:
    MOV R7, R0
    LDI32 R6, 8
    MUL q R7, R6
    LDI32 R6, 0x00008240
    ADD q R7, R6
    RET

; R0=id -> R7=&sem_count[id]
rt_addr_sem_count:
    MOV R7, R0
    LDI32 R6, 8
    MUL q R7, R6
    LDI32 R6, 0x00008280
    ADD q R7, R6
    RET

; R0=id -> R7=&chan_capacity[id]
rt_addr_chan_capacity:
    MOV R7, R0
    LDI32 R6, 8
    MUL q R7, R6
    LDI32 R6, 0x00008300
    ADD q R7, R6
    RET

; R0=id -> R7=&chan_head[id]
rt_addr_chan_head:
    MOV R7, R0
    LDI32 R6, 8
    MUL q R7, R6
    LDI32 R6, 0x00008320
    ADD q R7, R6
    RET

; R0=id -> R7=&chan_tail[id]
rt_addr_chan_tail:
    MOV R7, R0
    LDI32 R6, 8
    MUL q R7, R6
    LDI32 R6, 0x00008340
    ADD q R7, R6
    RET

; R0=id -> R7=&chan_count[id]
rt_addr_chan_count:
    MOV R7, R0
    LDI32 R6, 8
    MUL q R7, R6
    LDI32 R6, 0x00008360
    ADD q R7, R6
    RET

; R0=channel id -> R7=buffer base
rt_chan_buffer_base:
    LDI32 R6, 0
    CMP q R0, R6
    JNZ rt_chan_buffer_base_1
    LDI32 R7, 0x00008400
    RET
rt_chan_buffer_base_1:
    LDI32 R6, 1
    CMP q R0, R6
    JNZ rt_chan_buffer_base_2
    LDI32 R7, 0x00008480
    RET
rt_chan_buffer_base_2:
    LDI32 R6, 2
    CMP q R0, R6
    JNZ rt_chan_buffer_base_3
    LDI32 R7, 0x00008500
    RET
rt_chan_buffer_base_3:
    LDI32 R7, 0x00008580
    RET

; R0=chan id, R1=index -> R7=&buffer[id][index]
rt_chan_item_addr:
    PUSHQ R4
    PUSHQ R5
    PUSHQ R6
    CALL rt_chan_buffer_base
    MOV R5, R7
    MOV R4, R1
    LDI32 R6, 8
    MUL q R4, R6
    MOV R7, R5
    ADD q R7, R4
    POPQ R6
    POPQ R5
    POPQ R4
    RET

; R0=id -> R7=&thread_active[id]
rt_addr_thread_active:
    MOV R7, R0
    LDI32 R6, 8
    MUL q R7, R6
    LDI32 R6, 0x00008120
    ADD q R7, R6
    RET

; in: R6=current_id
; out: R0=next active thread id, or 0xFFFFFFFF if none
rt_pick_next_active_from_r6:
    PUSHQ R1
    PUSHQ R2
    PUSHQ R3
    PUSHQ R4
    PUSHQ R5

    MOV R0, R6
    LD_DATA q R5, 0x00008010
    MOV R4, R5
    LDI32 R3, 0
    CMP q R4, R3
    JNZ rt_pick_next_loop
    LDI32 R0, 0xFFFFFFFF
    JMP rt_pick_next_done

rt_pick_next_loop:
    ADDI q R0, 1
    CMP q R0, R5
    JNZ rt_pick_next_nowrap
    LDI32 R0, 0

rt_pick_next_nowrap:
    CALL rt_addr_thread_active
    LD_PTR q R1, [R7, 0]
    LDI32 R3, 1
    CMP q R1, R3
    JZ rt_pick_next_done

    SUBI q R4, 1
    LDI32 R3, 0
    CMP q R4, R3
    JG rt_pick_next_loop

    LDI32 R0, 0xFFFFFFFF

rt_pick_next_done:
    POPQ R5
    POPQ R4
    POPQ R3
    POPQ R2
    POPQ R1
    RET

rt_no_active_threads:
    LDI32 R0, 0
    ST_DATA b R0, 0x1000C
    HLT
    JMP rt_no_active_threads

thread_exit_trampoline:
    JMP thread_exit

thread_exit:
    CALL rt_disable_irq

    LD_DATA q R4, 0x00008018
    MOV R0, R4
    CALL rt_addr_thread_active
    LDI32 R1, 0
    ST_PTR q R1, [R7, 0]
    CALL rt_store_sync_status

    CALL rt_enable_irq_if_started

thread_exit_loop:
    CALL thread_interrupt
    JMP thread_exit_loop

; =================================================
; thread_sleep(ticks)
; - waits until irq tick counter reaches deadline
; - yields through normal safe-point scheduler path
; =================================================
thread_sleep:
    LD_DATA q R2, 0x00008100
    ADD q R2, R0

thread_sleep_loop:
    LD_DATA q R3, 0x00008100
    CMP q R3, R2
    JGE thread_sleep_done
    CALL thread_interrupt
    JMP thread_sleep_loop

thread_sleep_done:
    RET

; =================================================
; Mutexes (non-blocking)
; return: R0=1 success, R0=0 busy/fail
; also mirror to sync_status
; =================================================
mutex_init:
    CALL rt_disable_irq

    MOV R4, R0
    CALL rt_addr_mutex_depth
    LDI32 R1, 0
    ST_PTR q R1, [R7, 0]

    MOV R0, R4
    CALL rt_addr_mutex_owner
    LDI32 R1, 0xFFFFFFFF
    ST_PTR q R1, [R7, 0]

    LDI32 R0, 1
    CALL rt_store_sync_status
    CALL rt_enable_irq_if_started
    RET

mutex_lock:
mutex_try_lock:
    CALL rt_disable_irq

    MOV R4, R0
    CALL rt_addr_mutex_depth
    LD_PTR q R1, [R7, 0]
    LDI32 R2, 0
    CMP q R1, R2
    JNZ mutex_lock_check_owner

    ; first acquisition
    MOV R0, R4
    CALL rt_addr_mutex_depth
    LDI32 R1, 1
    ST_PTR q R1, [R7, 0]

    LD_DATA q R3, 0x00008018
    MOV R0, R4
    CALL rt_addr_mutex_owner
    ST_PTR q R3, [R7, 0]

    LDI32 R0, 1
    CALL rt_store_sync_status
    CALL rt_enable_irq_if_started
    RET

mutex_lock_check_owner:
    LD_DATA q R3, 0x00008018
    MOV R0, R4
    CALL rt_addr_mutex_owner
    LD_PTR q R1, [R7, 0]
    CMP q R1, R3
    JNZ mutex_lock_busy

    ; recursive acquisition by owner: depth++
    MOV R0, R4
    CALL rt_addr_mutex_depth
    LD_PTR q R1, [R7, 0]
    ADDI q R1, 1
    ST_PTR q R1, [R7, 0]

    LDI32 R0, 1
    CALL rt_store_sync_status
    CALL rt_enable_irq_if_started
    RET

mutex_lock_busy:
    LDI32 R0, 0
    CALL rt_store_sync_status
    CALL rt_enable_irq_if_started
    RET

mutex_unlock:
    CALL rt_disable_irq

    MOV R4, R0
    LD_DATA q R3, 0x00008018

    MOV R0, R4
    CALL rt_addr_mutex_owner
    LD_PTR q R1, [R7, 0]
    CMP q R1, R3
    JNZ mutex_unlock_fail

    MOV R0, R4
    CALL rt_addr_mutex_depth
    LD_PTR q R1, [R7, 0]
    LDI32 R2, 1
    CMP q R1, R2
    JLE mutex_unlock_release
    SUBI q R1, 1
    ST_PTR q R1, [R7, 0]

    LDI32 R0, 1
    CALL rt_store_sync_status
    CALL rt_enable_irq_if_started
    RET

mutex_unlock_release:
    MOV R0, R4
    CALL rt_addr_mutex_depth
    LDI32 R1, 0
    ST_PTR q R1, [R7, 0]

    MOV R0, R4
    CALL rt_addr_mutex_owner
    LDI32 R1, 0xFFFFFFFF
    ST_PTR q R1, [R7, 0]

    LDI32 R0, 1
    CALL rt_store_sync_status
    CALL rt_enable_irq_if_started
    RET

mutex_unlock_fail:
    LDI32 R0, 0
    CALL rt_store_sync_status
    CALL rt_enable_irq_if_started
    RET

; =================================================
; Semaphores (non-blocking)
; =================================================
sem_init:
    CALL rt_disable_irq

    MOV R4, R0
    MOV R5, R1
    MOV R0, R4
    CALL rt_addr_sem_count
    ST_PTR q R5, [R7, 0]

    LDI32 R0, 1
    CALL rt_store_sync_status
    CALL rt_enable_irq_if_started
    RET

sem_wait:
sem_try_wait:
    CALL rt_disable_irq

    MOV R4, R0
    CALL rt_addr_sem_count
    LD_PTR q R1, [R7, 0]
    LDI32 R2, 0
    CMP q R1, R2
    JLE sem_wait_busy

    SUBI q R1, 1
    ST_PTR q R1, [R7, 0]

    LDI32 R0, 1
    CALL rt_store_sync_status
    CALL rt_enable_irq_if_started
    RET

sem_wait_busy:
    LDI32 R0, 0
    CALL rt_store_sync_status
    CALL rt_enable_irq_if_started
    RET

sem_post:
    CALL rt_disable_irq

    MOV R4, R0
    CALL rt_addr_sem_count
    LD_PTR q R1, [R7, 0]
    ADDI q R1, 1
    ST_PTR q R1, [R7, 0]

    LDI32 R0, 1
    CALL rt_store_sync_status
    CALL rt_enable_irq_if_started
    RET

; =================================================
; Streams / channels (non-blocking bounded FIFO)
; stream_recv returns value in R0, success bit in sync_status
; =================================================
stream_init:
    CALL rt_disable_irq

    MOV R4, R0
    MOV R5, R1

    ; clamp capacity to [1,16]
    LDI32 R6, 1
    CMP q R5, R6
    JGE stream_init_cap_low_ok
    LDI32 R5, 1
stream_init_cap_low_ok:
    LDI32 R6, 16
    CMP q R5, R6
    JLE stream_init_cap_hi_ok
    LDI32 R5, 16
stream_init_cap_hi_ok:

    MOV R0, R4
    CALL rt_addr_chan_capacity
    ST_PTR q R5, [R7, 0]

    MOV R0, R4
    CALL rt_addr_chan_head
    LDI32 R1, 0
    ST_PTR q R1, [R7, 0]

    MOV R0, R4
    CALL rt_addr_chan_tail
    LDI32 R1, 0
    ST_PTR q R1, [R7, 0]

    MOV R0, R4
    CALL rt_addr_chan_count
    LDI32 R1, 0
    ST_PTR q R1, [R7, 0]

    LDI32 R0, 1
    CALL rt_store_sync_status
    CALL rt_enable_irq_if_started
    RET

stream_send:
stream_try_send:
    CALL rt_disable_irq

    MOV R4, R0
    MOV R5, R1

    MOV R0, R4
    CALL rt_addr_chan_count
    LD_PTR q R2, [R7, 0]

    MOV R0, R4
    CALL rt_addr_chan_capacity
    LD_PTR q R3, [R7, 0]

    CMP q R2, R3
    JGE stream_send_busy

    MOV R0, R4
    CALL rt_addr_chan_tail
    LD_PTR q R1, [R7, 0]

    MOV R0, R4
    CALL rt_chan_item_addr
    ST_PTR q R5, [R7, 0]

    ADDI q R1, 1
    MOV R0, R4
    CALL rt_addr_chan_capacity
    LD_PTR q R3, [R7, 0]
    CMP q R1, R3
    JL stream_send_tail_ok
    LDI32 R1, 0
stream_send_tail_ok:

    MOV R0, R4
    CALL rt_addr_chan_tail
    ST_PTR q R1, [R7, 0]

    MOV R0, R4
    CALL rt_addr_chan_count
    LD_PTR q R2, [R7, 0]
    ADDI q R2, 1
    ST_PTR q R2, [R7, 0]

    LDI32 R0, 1
    CALL rt_store_sync_status
    CALL rt_enable_irq_if_started
    RET

stream_send_busy:
    LDI32 R0, 0
    CALL rt_store_sync_status
    CALL rt_enable_irq_if_started
    RET

stream_recv:
stream_try_recv:
    CALL rt_disable_irq

    MOV R4, R0
    MOV R0, R4
    CALL rt_addr_chan_count
    LD_PTR q R2, [R7, 0]
    LDI32 R3, 0
    CMP q R2, R3
    JLE stream_recv_empty

    MOV R0, R4
    CALL rt_addr_chan_head
    LD_PTR q R1, [R7, 0]

    MOV R0, R4
    CALL rt_chan_item_addr
    LD_PTR q R5, [R7, 0]

    ADDI q R1, 1
    MOV R0, R4
    CALL rt_addr_chan_capacity
    LD_PTR q R3, [R7, 0]
    CMP q R1, R3
    JL stream_recv_head_ok
    LDI32 R1, 0
stream_recv_head_ok:

    MOV R0, R4
    CALL rt_addr_chan_head
    ST_PTR q R1, [R7, 0]

    MOV R0, R4
    CALL rt_addr_chan_count
    LD_PTR q R2, [R7, 0]
    SUBI q R2, 1
    ST_PTR q R2, [R7, 0]

    ST_DATA q R5, 0x00008110
    LDI32 R0, 1
    CALL rt_store_sync_status
    CALL rt_enable_irq_if_started
    LD_DATA q R0, 0x00008110
    RET

stream_recv_empty:
    LDI32 R0, 0
    ST_DATA q R0, 0x00008110
    CALL rt_store_sync_status
    CALL rt_enable_irq_if_started
    LD_DATA q R0, 0x00008110
    RET
