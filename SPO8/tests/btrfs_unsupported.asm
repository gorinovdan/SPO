; =====================================================================
; SPO8 — негативный сценарий «файловая система не поддерживается».
;
; Программа специально содержит суперблок с искажённым магическим значением
; ("EXT4FS!_" вместо "_BHRfS_M"). Цель — продемонстрировать ветку
; пункта 1 общего алгоритма задания: «проверить, поддерживается ли
; файловая система». При отказе FTP-цикл не запускается и программа
; завершает работу с ответом 500.
; =====================================================================

[section const_pool]
k0:    DD 0
k1:    DD 1
k4096: DD 4096

[section data_mem]
; --- скретч-переменные emit_ztext / ztext_eq. ---
v_emit_addr: DD 0
v_emit_i:    DD 0
v_emit_ch:   DD 0
v_eq_a:  DD 0
v_eq_b:  DD 0
v_eq_i:  DD 0
v_eq_ca: DD 0
v_eq_cb: DD 0

; --- испорченный superblock. ---
; Магическое значение не совпадает с "_BHRfS_M" — btrfs_mount должен вернуть 0.
img_super_magic:        DB "EXT4FS!_"
img_super_magic_z:      DB 0
img_root_dir_objectid:  DD 6
img_nodesize:           DD 4096

; --- эталон магического значения для сравнения. ---
s_magic:        DB "_BHRfS_M"
s_magic_z:      DB 0

; --- сообщения. ---
s_banner:        DB "SPO8 BTRFS FTP"
s_banner_lf:     DB 10
s_banner_z:      DB 0
s_unsupported:   DB "500 unsupported filesystem"
s_unsupported_lf: DB 10
s_unsupported_z: DB 0
s_done:          DB "OK_NEG"
s_done_lf:       DB 10
s_done_z:        DB 0

[section code]
; =====================================================================
; main — точка входа.
; Печатает баннер, пытается смонтировать FS и в любом случае выводит
; маркер OK_NEG, чтобы валидатор мог отличить корректный отказ от
; обрыва выполнения.
; =====================================================================
main:
  ; Делаем data_mem общим для всех вызовов (см. spec.md, df_size=0).
  PUSH_CONST k0
  POP_SYS 19

  PUSH_ADDR s_banner
  CALL emit_ztext, 1
  POP

  CALL btrfs_mount, 0
  JZ main_unsupported

  ; Если мы здесь — образ ошибочно прошёл проверку, печатаем 500
  ; всё равно (страховка для теста), но без OK_NEG.
  PUSH_ADDR s_unsupported
  CALL emit_ztext, 1
  POP
  RET

main_unsupported:
  PUSH_ADDR s_unsupported
  CALL emit_ztext, 1
  POP
  PUSH_ADDR s_done
  CALL emit_ztext, 1
  POP
  RET

; =====================================================================
; btrfs_mount — упрощённая копия из btrfs_ftp_demo.asm:
;   1) magic == "_BHRfS_M";
;   2) nodesize == 4096;
;   3) root_dir_objectid > 0.
; В этом тесте первый пункт заведомо нарушен.
; =====================================================================
btrfs_mount:
  ENTER 0
  PUSH_ADDR img_super_magic
  PUSH_ADDR s_magic
  CALL ztext_eq, 2
  JZ btrfs_mount_fail
  LOAD img_nodesize
  PUSH_CONST k4096
  EQ
  JZ btrfs_mount_fail
  LOAD img_root_dir_objectid
  PUSH_CONST k0
  GT
  JZ btrfs_mount_fail
  PUSH_CONST k1
  LEAVE
  RETF

btrfs_mount_fail:
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; ztext_eq(a, b) — побайтовое сравнение двух NUL-терминированных строк.
; =====================================================================
ztext_eq:
  STORE v_eq_b
  STORE v_eq_a
  ENTER 0
  PUSH_CONST k0
  STORE v_eq_i

ztext_eq_loop:
  LOAD v_eq_a
  LOAD v_eq_i
  INDEXB
  LOADB_IND
  STORE v_eq_ca
  LOAD v_eq_b
  LOAD v_eq_i
  INDEXB
  LOADB_IND
  STORE v_eq_cb
  LOAD v_eq_ca
  LOAD v_eq_cb
  EQ
  JZ ztext_eq_false
  LOAD v_eq_ca
  PUSH_CONST k0
  EQ
  JZ ztext_eq_next
  PUSH_CONST k1
  LEAVE
  RETF

ztext_eq_next:
  LOAD v_eq_i
  PUSH_CONST k1
  ADD
  STORE v_eq_i
  JMP ztext_eq_loop

ztext_eq_false:
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; emit_ztext(addr) — печатает NUL-терминированную строку в SimplePipe.
; В негативном сценарии нам не нужны счётчики потока: достаточно
; простого побайтного PIPE_OUT, чтобы валидатор увидел сообщение.
; =====================================================================
emit_ztext:
  STORE v_emit_addr
  ENTER 0
  PUSH_CONST k0
  STORE v_emit_i

emit_ztext_loop:
  LOAD v_emit_addr
  LOAD v_emit_i
  INDEXB
  LOADB_IND
  STORE v_emit_ch
  LOAD v_emit_ch
  PUSH_CONST k0
  EQ
  JZ emit_ztext_emit
  PUSH_CONST k0
  LEAVE
  RETF

emit_ztext_emit:
  LOAD v_emit_ch
  PIPE_OUT
  LOAD v_emit_i
  PUSH_CONST k1
  ADD
  STORE v_emit_i
  JMP emit_ztext_loop
