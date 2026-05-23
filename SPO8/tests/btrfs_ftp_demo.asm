; =====================================================================
; SPO8 — чтение Btrfs-образа через пассивный FTP.
; Вариант 4 практического задания №3 дисциплины СПО.
;
; Модель работы:
;   1) btrfs_mount проверяет superblock — пункт 1 общего алгоритма
;      задания «проверить, поддерживается ли FS». При неудаче выдаёт
;      ответ 500 и не входит в FTP-цикл.
;   2) ftp_loop читает команды из байтового потока SimplePipe (PIPE_IN)
;      и обрабатывает их через dispatch_command — пункт 2:
;      диалоговый режим в стиле пассивного FTP.
;   3) Команды LIST/RETR/COPY/CWD/PWD реализуют требования 2a/2b/2c.
;      Дополнительно поддержаны PASV, SYST, NOOP, HELP, TYPE и QUIT,
;      чтобы FTP-сценарий выглядел естественно.
; =====================================================================

[section const_pool]
; --- числовые константы для арифметики и сравнений ---
k0:   DD 0
k1:   DD 1
k2:   DD 2
k3:   DD 3
k4:   DD 4
k5:   DD 5
k6:   DD 6
k7:   DD 7        ; v_stream_window: каждые 7 байт фиксируем пассивное ожидание
k8:   DD 8
k10:  DD 10       ; \n
k13:  DD 13       ; \r
k16:  DD 16
k32:  DD 32       ; ' ' — разделитель между командой и аргументом
k63:  DD 63       ; максимально допустимая длина команды (буфер 64 - 1)
k128: DD 128      ; размер порции outbox для пассивного канала данных
k256: DD 256
k512: DD 512
k65536: DD 65536
k16777216: DD 16777216
k1000: DD 1000 ; стартовое окно для подключения FTP-адаптера к VM
k4096: DD 4096
k_btrfs_ft_reg: DD 1 ; BTRFS_FT_REG_FILE
k_btrfs_ft_dir: DD 2 ; BTRFS_FT_DIR
k_blk_magic_off: DD 65600    ; 0x10000 + 0x40: магическое значение суперблока Btrfs
k_blk_root_off: DD 65664     ; 0x10000 + 0x80: root_dir objectid
k_blk_nodesize_off: DD 65684 ; 0x10000 + 0x94: nodesize
k_blk_readme_off: DD 131072
k_blk_info_off: DD 131104
k_blk_help_off: DD 131136
k_blk_notes_off: DD 131168

; ASCII-литералы для типов записей DIR_ITEM в листинге.
c_d:       DD 100   ; 'd' — каталог
c_f:       DD 102   ; 'f' — обычный файл
c_slash:   DD 47    ; '/' — разделитель пути
c_ascii_0: DD 48    ; '0' — для печати чисел

[section data_mem]
; ---------------------------------------------------------------------
; Раздел 1. Состояние FTP во время выполнения.
; ---------------------------------------------------------------------
; v_current_dir хранит inode текущего каталога из дерева FS.
; Путь для PWD ведётся отдельно и обновляется командами CWD/CDUP.
v_current_dir:   DD 0

; v_cmd_count   — сколько FTP-команд обработано в этой сессии.
; v_lookup_count — сколько обращений к дереву FS выполнили cmd_*.
; v_stream_bytes — сколько байт передал приёмник вывода в выходной поток.
; v_stream_window — счётчик до следующего пассивного ожидания (см. SPO7).
; v_group_waits  — сколько раз фиксировалось пассивное ожидание.
v_cmd_count:     DD 0
v_lookup_count:  DD 0
v_stream_bytes:  DD 0
v_stream_window: DD 7
v_group_waits:   DD 0

; ---------------------------------------------------------------------
; Раздел 2. Скретч-переменные процедур.
; Используются совместно: память кадров CALL общая
; (POP_SYS 19 в main выставляет df_size=0).
; ---------------------------------------------------------------------
v_read_i:    DD 0
v_read_ch:   DD 0
v_emit_addr: DD 0
v_emit_i:    DD 0
v_emit_ch:   DD 0

; Сравнение байтовых строк: ztext_eq, prefix_eq.
v_eq_a:  DD 0
v_eq_b:  DD 0
v_eq_n:  DD 0
v_eq_i:  DD 0
v_eq_ca: DD 0
v_eq_cb: DD 0

; Аргумент команды: смещение в v_cmd_buf.
v_arg_off: DD 0

; Параметры приёмника вывода stream_write_byte.
v_stream_ch: DD 0
v_sink:      DD 0      ; 0 = управляющий FTP-поток, 1 = пассивный поток данных
v_data_len:  DD 0      ; сколько байт накоплено в data_pipe_outbox

; Параметры форматирования списка/файла.
v_entry_type:  DD 0
v_entry_inode: DD 0
v_entry_size:  DD 0
v_entry_name:  DD 0
v_uint_n:   DD 0
v_uint_cnt: DD 0
v_file_inode: DD 0
v_file_size:  DD 0
v_file_data:  DD 0

; Параметры BlockDevice/BackDevice.
v_block_src:   DD 0
v_block_dst:   DD 0
v_block_len:   DD 0
v_block_i:     DD 0
v_block_j:     DD 0
v_block_chunk: DD 0
v_block_ch:    DD 0
v_block_off:   DD 0
v_block_value: DD 0
v_mount_root:  DD 0
v_mount_nodesize: DD 0

; Состояние сканирования листа дерева FS в Btrfs.
v_scan_i:        DD 0
v_inode_i:       DD 0
v_extent_i:      DD 0
v_found_dirent:  DD 0
v_found_inode:   DD 0
v_found_size:    DD 0
v_found_type:    DD 0
v_found_data_id: DD 0
v_found_block_off: DD 0
v_found_extent_size: DD 0
v_name_id:       DD 0
v_name_off:      DD 0
v_name_len:      DD 0
v_find_parent:   DD 0
v_arg_cmp_off:   DD 0
v_arg_absolute:  DD 0

; Состояние COPY: очередь каталогов для рекурсивного обхода DIR_ITEM.
v_copy_target: DD 0
v_copy_dir:    DD 0
v_copy_head:   DD 0
v_copy_tail:   DD 0
v_copy_queue: RESB 1024

; ---------------------------------------------------------------------
; Раздел 3. Буферы.
; ---------------------------------------------------------------------
; v_cmd_buf — буфер прочитанной FTP-команды (включая аргумент).
; Заканчивается NUL-байтом, размер до 63 значащих байт + NUL.
v_cmd_buf: RESB 64

; v_digits — буфер для печати беззнаковых чисел в десятичной системе.
v_digits: RESB 16

; v_pwd_buf — текущий путь для PWD. Хранится без завершающего NUL,
; длина лежит в v_pwd_len.
v_pwd_len: DD 0
v_pwd_buf: RESB 256

; ---------------------------------------------------------------------
; Раздел 4. Btrfs-образ варианта 4.
; BEGIN GENERATED BTRFS TABLES
;
; Этот блок заменяется скриптом gen_btrfs_ftp_asm.py после сборки
; настоящего Btrfs-образа каталога SPO8. Ниже оставлена минимальная
; заглушка, чтобы шаблон оставался синтаксически полным.
; ---------------------------------------------------------------------
img_root_inode: DD 256
img_inode_count: DD 1
img_inode_objectid: DD 256
img_inode_type: DD 2
img_inode_size: DD 0
img_dirent_count: DD 0
img_dirent_parent: DD 0
img_dirent_inode: DD 0
img_dirent_type: DD 0
img_dirent_name_id: DD 0
img_extent_count: DD 0
img_extent_inode: DD 0
img_extent_block_off: DD 0
img_extent_size: DD 0
img_name_count: DD 0
img_name_offset: DD 0
img_name_len: DD 0
img_name_pool: DB ""
; END GENERATED BTRFS TABLES

; ---------------------------------------------------------------------
; Раздел 5. Эталонные имена для match-функций.
; Хранятся отдельно, чтобы было видно, что v_cmd_buf сравнивается
; именно с фиксированными ASCII-токенами, а не разбирается посимвольно.
; ---------------------------------------------------------------------
m_pasv:   DB "PASV"
m_pasv_z: DB 0
m_pwd:    DB "PWD"
m_pwd_z:  DB 0
m_list:   DB "LIST"
m_list_z: DB 0
m_cwd:    DB "CWD"
m_cwd_z:  DB 0
m_retr:   DB "RETR"
m_retr_z: DB 0
m_copy:   DB "COPY"
m_copy_z: DB 0
m_quit:   DB "QUIT"
m_quit_z: DB 0
m_syst:   DB "SYST"
m_syst_z: DB 0
m_noop:   DB "NOOP"
m_noop_z: DB 0
m_help:   DB "HELP"
m_help_z: DB 0
m_type:   DB "TYPE"
m_type_z: DB 0
m_user:   DB "USER"
m_user_z: DB 0
m_pass:   DB "PASS"
m_pass_z: DB 0
m_feat:   DB "FEAT"
m_feat_z: DB 0
m_opts:   DB "OPTS"
m_opts_z: DB 0
m_epsv:   DB "EPSV"
m_epsv_z: DB 0
m_nlst:   DB "NLST"
m_nlst_z: DB 0
m_size:   DB "SIZE"
m_size_z: DB 0
m_mdtm:   DB "MDTM"
m_mdtm_z: DB 0
m_cdup:   DB "CDUP"
m_cdup_z: DB 0
m_clnt:   DB "CLNT"
m_clnt_z: DB 0
m_auth:   DB "AUTH"
m_auth_z: DB 0
m_rest:   DB "REST"
m_rest_z: DB 0

; --- эталонные специальные пути для CWD/COPY. ---
p_root:     DB "/"
p_root_z:   DB 0
p_dot:      DB "."
p_dot_z:    DB 0
p_dotdot:   DB ".."
p_dotdot_z: DB 0

; ---------------------------------------------------------------------
; Раздел 6. Сообщения протокола пассивного FTP и баннеры.
; ---------------------------------------------------------------------
s_banner:    DB "SPO8 BTRFS FTP"
s_banner_lf: DB 10
s_banner_z:  DB 0
s_fs_ok_1:   DB "FS OK magic=_BHRfS_M root_dir="
s_fs_ok_1_z: DB 0
s_fs_ok_2:   DB " nodesize="
s_fs_ok_2_z: DB 0
s_newline:   DB 10
s_newline_z: DB 0
s_220:       DB "220 SPO8 Btrfs image ready"
s_220_lf:    DB 10
s_220_z:     DB 0
s_prompt:    DB "> "
s_prompt_z:  DB 0
s_227:       DB "227 Entering Passive Mode (127,0,0,1,7,228)"
s_227_lf:    DB 10
s_227_z:     DB 0
s_229:       DB "229 Entering Extended Passive Mode (|||2020|)"
s_229_lf:    DB 10
s_229_z:     DB 0
s_pwd_pre:   DB "257 "
s_pwd_pre_quote: DB 34
s_pwd_pre_z: DB 0
s_pwd_post:  DB 34
s_pwd_post_lf: DB 10
s_pwd_post_z: DB 0
s_150_list:  DB "150 directory stream follows"
s_150_list_lf: DB 10
s_150_list_z: DB 0
s_226:       DB "226 transfer complete"
s_226_lf:    DB 10
s_226_z:     DB 0
s_250:       DB "250 CWD ok"
s_250_lf:    DB 10
s_250_z:     DB 0
s_550:       DB "550 not found"
s_550_lf:    DB 10
s_550_z:     DB 0
s_502:       DB "502 command not implemented"
s_502_lf:    DB 10
s_502_z:     DB 0
s_150_inode: DB "150 inode="
s_150_inode_z: DB 0
s_size:      DB " size="
s_size_z:    DB 0
s_extent:    DB " extent=btrfs"
s_extent_lf: DB 10
s_extent_z:  DB 0
s_150_copy_dir: DB "150 recursive directory copy follows"
s_150_copy_dir_lf: DB 10
s_150_copy_dir_z: DB 0
s_copy_file: DB "COPY file "
s_copy_file_z: DB 0
s_226_copy: DB "226 copy complete"
s_226_copy_lf: DB 10
s_226_copy_z: DB 0
s_215:       DB "215 UNIX Type: L8"
s_215_lf:    DB 10
s_215_z:     DB 0
s_200_noop:  DB "200 NOOP ok"
s_200_noop_lf: DB 10
s_200_noop_z: DB 0
s_200_type:  DB "200 Type set"
s_200_type_lf: DB 10
s_200_type_z: DB 0
s_200_ok:    DB "200 OK"
s_200_ok_lf: DB 10
s_200_ok_z:  DB 0
s_213:       DB "213 "
s_213_z:     DB 0
s_mdtm:      DB "213 20260516000000"
s_mdtm_lf:   DB 10
s_mdtm_z:    DB 0
s_230:       DB "230 Login successful"
s_230_lf:    DB 10
s_230_z:     DB 0
s_331:       DB "331 User name okay, need password"
s_331_lf:    DB 10
s_331_z:     DB 0
s_350:       DB "350 Restart position accepted"
s_350_lf:    DB 10
s_350_z:     DB 0
s_150_file:  DB "150 opening data connection"
s_150_file_lf: DB 10
s_150_file_z: DB 0
s_unix_dir:  DB "drwxr-xr-x 1 spo spo "
s_unix_dir_z: DB 0
s_unix_file: DB "-rw-r--r-- 1 spo spo "
s_unix_file_z: DB 0
s_unix_date: DB " Jan 01 00:00 "
s_unix_date_z: DB 0
s_help_1:    DB "214-Supported commands:"
s_help_1_lf: DB 10
s_help_1_z:  DB 0
s_help_2:    DB "214 USER PASS FEAT OPTS PASV EPSV PWD LIST NLST CWD CDUP RETR SIZE MDTM COPY SYST NOOP HELP TYPE QUIT"
s_help_2_lf: DB 10
s_help_2_z:  DB 0
s_feat_1:    DB "211-Features:"
s_feat_1_lf: DB 10
s_feat_1_z:  DB 0
s_feat_2:    DB " UTF8"
s_feat_2_lf: DB 10
s_feat_2_z:  DB 0
s_feat_3:    DB " EPSV"
s_feat_3_lf: DB 10
s_feat_3_z:  DB 0
s_feat_4:    DB " PASV"
s_feat_4_lf: DB 10
s_feat_4_z:  DB 0
s_feat_5:    DB " SIZE"
s_feat_5_lf: DB 10
s_feat_5_z:  DB 0
s_feat_6:    DB " MDTM"
s_feat_6_lf: DB 10
s_feat_6_z:  DB 0
s_feat_end:  DB "211 End"
s_feat_end_lf: DB 10
s_feat_end_z: DB 0
s_221:       DB "221 bye"
s_221_lf:    DB 10
s_221_z:     DB 0
s_stats_1:   DB "STATS cmd="
s_stats_1_z: DB 0
s_stats_2:   DB " lookup="
s_stats_2_z: DB 0
s_stats_3:   DB " stream="
s_stats_3_z: DB 0
s_stats_4:   DB " gw="
s_stats_4_z: DB 0
s_ok:        DB "OK"
s_ok_lf:     DB 10
s_ok_z:      DB 0
s_mount_fail: DB "500 unsupported filesystem"
s_mount_fail_lf: DB 10
s_mount_fail_z: DB 0
s_magic:     DB "_BHRfS_M"
s_magic_z:   DB 0

[section code]
; =====================================================================
; main — точка входа.
; =====================================================================
main:
  ; SPO8 использует общий data_mem образа для Btrfs-образа, состояния FTP
  ; и состояния потока. Чтобы CALL не выделял отдельный кадр под каждую
  ; процедуру, выставляем df_size=0 (POP_SYS 19) — все процедуры будут
  ; работать с одной и той же памятью данных.
  PUSH_CONST k0
  POP_SYS 19

  ; В TCP-конфигурации RemoteTasks подключает SimplePipe к локальному
  ; FTP-адаптеру и сразу запускает VM. Небольшое стартовое окно даёт
  ; адаптеру завершить сетевую стыковку до первого приветствия 220.
  CALL ftp_boot_wait, 0
  POP

  ; Сбрасываем счётчики состояния FTP.
  LOAD img_root_inode
  STORE v_current_dir
  PUSH_CONST k0
  STORE v_cmd_count
  PUSH_CONST k0
  STORE v_lookup_count
  PUSH_CONST k0
  STORE v_stream_bytes
  PUSH_CONST k7
  STORE v_stream_window
  PUSH_CONST k0
  STORE v_group_waits
  PUSH_CONST k0
  STORE v_sink
  PUSH_CONST k0
  STORE v_data_len
  CALL pwd_set_root, 0
  POP

  ; Блочный образ уже подготовлен локальной частью задания через
  ; mkfs.btrfs, mount, копирование каталога SPO8 и umount. VM получает
  ; этот файл как BlockDevice и читает его через BackDevice/read.

  ; --- Пункт 1 общего алгоритма: проверяем поддержку FS. ---
  CALL btrfs_mount, 0
  JZ main_mount_fail

  ; FS поддерживается — первым ответом отдаём стандартное FTP-приветствие.
  PUSH_ADDR s_220
  CALL emit_ztext, 1
  POP

  ; --- Пункт 2: переходим в диалоговый цикл FTP. ---
  CALL ftp_loop, 0
  POP
  RET

main_mount_fail:
  ; FS не поддерживается — печатаем 500 и выходим без FTP-цикла.
  PUSH_ADDR s_mount_fail
  CALL emit_ztext, 1
  POP
  RET

ftp_boot_wait:
  ENTER 0
  PUSH_CONST k0
  STORE v_read_i
ftp_boot_wait_loop:
  LOAD v_read_i
  PUSH_CONST k1000
  LT
  JZ ftp_boot_wait_done
  LOAD v_read_i
  PUSH_CONST k1
  ADD
  STORE v_read_i
  JMP ftp_boot_wait_loop
ftp_boot_wait_done:
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; Вспомогательные процедуры BlockDevice.
; block_prepare_image оставлен как совместимая заглушка. Реальный образ
; теперь создаётся до запуска VM по схеме mkfs.btrfs/mount/copy/umount.
; =====================================================================
block_prepare_image:
  ENTER 0
  PUSH_CONST k0
  LEAVE
  RETF

; block_write_from_mem(src_addr, block_offset, len)
block_write_from_mem:
  STORE v_block_len
  STORE v_block_dst
  STORE v_block_src
  ENTER 0
  PUSH_CONST k0
  STORE v_block_i
block_write_from_mem_loop:
  LOAD v_block_i
  LOAD v_block_len
  LT
  JZ block_write_from_mem_done
  LOAD v_block_dst
  LOAD v_block_i
  ADD
  LOAD v_block_src
  LOAD v_block_i
  INDEXB
  LOADB_IND
  BLOCK_WRITE_BYTE
  LOAD v_block_i
  PUSH_CONST k1
  ADD
  STORE v_block_i
  JMP block_write_from_mem_loop
block_write_from_mem_done:
  PUSH_CONST k0
  LEAVE
  RETF

; block_write_u32(block_offset, value), порядок байтов little-endian
block_write_u32:
  STORE v_block_value
  STORE v_block_off
  ENTER 0
  PUSH_CONST k0
  STORE v_block_i
block_write_u32_loop:
  LOAD v_block_i
  PUSH_CONST k4
  LT
  JZ block_write_u32_done
  LOAD v_block_off
  LOAD v_block_i
  ADD
  LOAD v_block_value
  PUSH_CONST k256
  REM
  BLOCK_WRITE_BYTE
  LOAD v_block_value
  PUSH_CONST k256
  DIV
  STORE v_block_value
  LOAD v_block_i
  PUSH_CONST k1
  ADD
  STORE v_block_i
  JMP block_write_u32_loop
block_write_u32_done:
  PUSH_CONST k0
  LEAVE
  RETF

; block_read_u32(block_offset) -> value, порядок байтов little-endian
block_read_u32:
  STORE v_block_off
  ENTER 0
  LOAD v_block_off
  BLOCK_READ_BYTE
  STORE v_block_value
  LOAD v_block_off
  PUSH_CONST k1
  ADD
  BLOCK_READ_BYTE
  PUSH_CONST k256
  MUL
  LOAD v_block_value
  ADD
  STORE v_block_value
  LOAD v_block_off
  PUSH_CONST k2
  ADD
  BLOCK_READ_BYTE
  PUSH_CONST k65536
  MUL
  LOAD v_block_value
  ADD
  STORE v_block_value
  LOAD v_block_off
  PUSH_CONST k3
  ADD
  BLOCK_READ_BYTE
  PUSH_CONST k16777216
  MUL
  LOAD v_block_value
  ADD
  STORE v_block_value
  LOAD v_block_value
  LEAVE
  RETF

; block_eq_mem(block_offset, addr, len) -> 1/0
block_eq_mem:
  STORE v_block_len
  STORE v_block_src
  STORE v_block_off
  ENTER 0
  PUSH_CONST k0
  STORE v_block_i
block_eq_mem_loop:
  LOAD v_block_i
  LOAD v_block_len
  LT
  JZ block_eq_mem_true
  LOAD v_block_off
  LOAD v_block_i
  ADD
  BLOCK_READ_BYTE
  STORE v_block_ch
  LOAD v_block_src
  LOAD v_block_i
  INDEXB
  LOADB_IND
  LOAD v_block_ch
  EQ
  JZ block_eq_mem_false
  LOAD v_block_i
  PUSH_CONST k1
  ADD
  STORE v_block_i
  JMP block_eq_mem_loop
block_eq_mem_true:
  PUSH_CONST k1
  LEAVE
  RETF
block_eq_mem_false:
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; btrfs_mount — проверяет, что образ соответствует Btrfs.
; Возвращает 1 при успехе, 0 при отказе.
; Условия поддержки:
;   1) magic совпадает с "_BHRfS_M";
;   2) nodesize > 0;
;   3) root_dir_objectid > 0.
; =====================================================================
btrfs_mount:
  ENTER 0
  PUSH_CONST k_blk_magic_off
  PUSH_ADDR s_magic
  PUSH_CONST k8
  CALL block_eq_mem, 3
  JZ btrfs_mount_fail
  PUSH_CONST k_blk_nodesize_off
  CALL block_read_u32, 1
  STORE v_mount_nodesize
  LOAD v_mount_nodesize
  PUSH_CONST k0
  GT
  JZ btrfs_mount_fail
  PUSH_CONST k_blk_root_off
  CALL block_read_u32, 1
  STORE v_mount_root
  LOAD v_mount_root
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
; ftp_loop — основной диалоговый цикл.
; Читает строки команд из управляющего SimplePipe и диспатчит их.
; Завершается когда dispatch_command вернёт 0 (на QUIT) или
; когда read_line вернёт 0 (EOF на входе).
; =====================================================================
ftp_loop:
  ENTER 0
ftp_loop_next:
  CALL read_line, 0
  JZ ftp_loop_done
  LOAD v_cmd_count
  PUSH_CONST k1
  ADD
  STORE v_cmd_count
  CALL dispatch_command, 0
  JZ ftp_loop_done
  JMP ftp_loop_next
ftp_loop_done:
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; read_line — читает одну FTP-команду в v_cmd_buf.
; Терминаторы: '\n', '\r' (игнорируется), 0 (EOF).
; Возвращает 1, если строка прочитана; 0 при EOF в начале строки.
; =====================================================================
read_line:
  ENTER 0
  ; Путь RemoteTasks использует SimplePipe SyncReceive через PIPE_IN.
  PUSH_CONST k0
  STORE v_read_i

read_line_loop:
  PIPE_IN
  STORE v_read_ch
  ; ch == 0 — EOF. Возвращаем результат в зависимости от того,
  ; успели мы прочитать что-нибудь или нет.
  LOAD v_read_ch
  PUSH_CONST k0
  EQ
  JZ read_line_check_cr
  LOAD v_read_i
  PUSH_CONST k0
  EQ
  JZ read_line_terminate_success
  PUSH_CONST k0
  LEAVE
  RETF

read_line_check_cr:
  ; '\r' — игнорируем, ждём '\n'.
  LOAD v_read_ch
  PUSH_CONST k13
  EQ
  JZ read_line_check_lf
  JMP read_line_loop

read_line_check_lf:
  ; '\n' — конец строки.
  LOAD v_read_ch
  PUSH_CONST k10
  EQ
  JZ read_line_store_char
  JMP read_line_terminate_success

read_line_store_char:
  ; Защита от переполнения буфера команды.
  LOAD v_read_i
  PUSH_CONST k63
  LT
  JZ read_line_loop
  PUSH_ADDR v_cmd_buf
  LOAD v_read_i
  INDEXB
  LOAD v_read_ch
  STOREB_IND
  LOAD v_read_i
  PUSH_CONST k1
  ADD
  STORE v_read_i
  JMP read_line_loop

read_line_terminate_success:
  ; Записываем NUL в конец буфера и возвращаем 1.
  PUSH_ADDR v_cmd_buf
  LOAD v_read_i
  INDEXB
  PUSH_CONST k0
  STOREB_IND
  PUSH_CONST k1
  LEAVE
  RETF

; =====================================================================
; echo_command — печатает "> " + содержимое v_cmd_buf + "\n".
; Соответствует поведению пассивного FTP, когда сервер подтверждает
; принятую команду в управляющем канале.
; =====================================================================
echo_command:
  ENTER 0
  PUSH_ADDR s_prompt
  CALL emit_ztext, 1
  POP
  PUSH_ADDR v_cmd_buf
  CALL emit_ztext, 1
  POP
  PUSH_ADDR s_newline
  CALL emit_ztext, 1
  POP
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; dispatch_command — разбирает v_cmd_buf и вызывает обработчик.
; Возвращает 0 на QUIT (сигнал завершения цикла), 1 в остальных случаях.
;
; Сравнение идёт целыми ASCII-токенами через cmd_starts_with,
; а не первой буквой — поэтому, например, "QUOTA" не будет
; распознано как "QUIT".
; =====================================================================
dispatch_command:
  ENTER 0

  ; Сначала вычисляем смещение аргумента (первый не-пробел после
  ; первого пробела). Если аргумента нет, v_arg_off == 0.
  CALL compute_arg_offset, 0
  STORE v_arg_off

  ; USER/PASS и совместимые команды, которые используют реальные FTP-клиенты.
  PUSH_ADDR m_user
  PUSH_CONST k4
  CALL cmd_starts_with, 2
  JZ dispatch_check_pass
  PUSH_ADDR s_331
  CALL emit_ztext, 1
  POP
  PUSH_CONST k1
  LEAVE
  RETF

dispatch_check_pass:
  PUSH_ADDR m_pass
  PUSH_CONST k4
  CALL cmd_starts_with, 2
  JZ dispatch_check_feat
  PUSH_ADDR s_230
  CALL emit_ztext, 1
  POP
  PUSH_CONST k1
  LEAVE
  RETF

dispatch_check_feat:
  PUSH_ADDR m_feat
  PUSH_CONST k4
  CALL cmd_starts_with, 2
  JZ dispatch_check_opts
  CALL cmd_feat, 0
  POP
  PUSH_CONST k1
  LEAVE
  RETF

dispatch_check_opts:
  PUSH_ADDR m_opts
  PUSH_CONST k4
  CALL cmd_starts_with, 2
  JZ dispatch_check_epsv
  PUSH_ADDR s_200_ok
  CALL emit_ztext, 1
  POP
  PUSH_CONST k1
  LEAVE
  RETF

dispatch_check_epsv:
  PUSH_ADDR m_epsv
  PUSH_CONST k4
  CALL cmd_starts_with, 2
  JZ dispatch_check_clnt
  PUSH_ADDR s_229
  CALL emit_ztext, 1
  POP
  PUSH_CONST k1
  LEAVE
  RETF

dispatch_check_clnt:
  PUSH_ADDR m_clnt
  PUSH_CONST k4
  CALL cmd_starts_with, 2
  JZ dispatch_check_auth
  PUSH_ADDR s_200_ok
  CALL emit_ztext, 1
  POP
  PUSH_CONST k1
  LEAVE
  RETF

dispatch_check_auth:
  PUSH_ADDR m_auth
  PUSH_CONST k4
  CALL cmd_starts_with, 2
  JZ dispatch_check_rest
  ; Поддерживается только обычный FTP. FileZilla/curl переходят к нему после отказа AUTH TLS.
  PUSH_ADDR s_502
  CALL emit_ztext, 1
  POP
  PUSH_CONST k1
  LEAVE
  RETF

dispatch_check_rest:
  PUSH_ADDR m_rest
  PUSH_CONST k4
  CALL cmd_starts_with, 2
  JZ dispatch_check_quit
  PUSH_ADDR s_350
  CALL emit_ztext, 1
  POP
  PUSH_CONST k1
  LEAVE
  RETF

  ; QUIT — завершение сессии.
dispatch_check_quit:
  PUSH_ADDR m_quit
  PUSH_CONST k4
  CALL cmd_starts_with, 2
  JZ dispatch_check_pasv
  PUSH_ADDR s_221
  CALL emit_ztext, 1
  POP
  CALL emit_stats, 0
  POP
  PUSH_CONST k0
  LEAVE
  RETF

dispatch_check_pasv:
  PUSH_ADDR m_pasv
  PUSH_CONST k4
  CALL cmd_starts_with, 2
  JZ dispatch_check_pwd
  PUSH_ADDR s_227
  CALL emit_ztext, 1
  POP
  PUSH_CONST k1
  LEAVE
  RETF

dispatch_check_pwd:
  PUSH_ADDR m_pwd
  PUSH_CONST k3
  CALL cmd_starts_with, 2
  JZ dispatch_check_list
  CALL emit_pwd, 0
  POP
  PUSH_CONST k1
  LEAVE
  RETF

dispatch_check_list:
  PUSH_ADDR m_list
  PUSH_CONST k4
  CALL cmd_starts_with, 2
  JZ dispatch_check_nlst
  CALL cmd_list, 0
  POP
  PUSH_CONST k1
  LEAVE
  RETF

dispatch_check_nlst:
  PUSH_ADDR m_nlst
  PUSH_CONST k4
  CALL cmd_starts_with, 2
  JZ dispatch_check_cwd
  CALL cmd_nlst, 0
  POP
  PUSH_CONST k1
  LEAVE
  RETF

dispatch_check_cwd:
  PUSH_ADDR m_cwd
  PUSH_CONST k3
  CALL cmd_starts_with, 2
  JZ dispatch_check_cdup
  CALL cmd_cwd, 0
  POP
  PUSH_CONST k1
  LEAVE
  RETF

dispatch_check_cdup:
  PUSH_ADDR m_cdup
  PUSH_CONST k4
  CALL cmd_starts_with, 2
  JZ dispatch_check_retr
  CALL cmd_cdup, 0
  POP
  PUSH_CONST k1
  LEAVE
  RETF

dispatch_check_retr:
  PUSH_ADDR m_retr
  PUSH_CONST k4
  CALL cmd_starts_with, 2
  JZ dispatch_check_size
  CALL cmd_retr, 0
  POP
  PUSH_CONST k1
  LEAVE
  RETF

dispatch_check_size:
  PUSH_ADDR m_size
  PUSH_CONST k4
  CALL cmd_starts_with, 2
  JZ dispatch_check_mdtm
  CALL cmd_size, 0
  POP
  PUSH_CONST k1
  LEAVE
  RETF

dispatch_check_mdtm:
  PUSH_ADDR m_mdtm
  PUSH_CONST k4
  CALL cmd_starts_with, 2
  JZ dispatch_check_copy
  CALL cmd_mdtm, 0
  POP
  PUSH_CONST k1
  LEAVE
  RETF

dispatch_check_copy:
  PUSH_ADDR m_copy
  PUSH_CONST k4
  CALL cmd_starts_with, 2
  JZ dispatch_check_syst
  CALL cmd_copy, 0
  POP
  PUSH_CONST k1
  LEAVE
  RETF

dispatch_check_syst:
  PUSH_ADDR m_syst
  PUSH_CONST k4
  CALL cmd_starts_with, 2
  JZ dispatch_check_noop
  PUSH_ADDR s_215
  CALL emit_ztext, 1
  POP
  PUSH_CONST k1
  LEAVE
  RETF

dispatch_check_noop:
  PUSH_ADDR m_noop
  PUSH_CONST k4
  CALL cmd_starts_with, 2
  JZ dispatch_check_help
  PUSH_ADDR s_200_noop
  CALL emit_ztext, 1
  POP
  PUSH_CONST k1
  LEAVE
  RETF

dispatch_check_help:
  PUSH_ADDR m_help
  PUSH_CONST k4
  CALL cmd_starts_with, 2
  JZ dispatch_check_type
  PUSH_ADDR s_help_1
  CALL emit_ztext, 1
  POP
  PUSH_ADDR s_help_2
  CALL emit_ztext, 1
  POP
  PUSH_CONST k1
  LEAVE
  RETF

dispatch_check_type:
  PUSH_ADDR m_type
  PUSH_CONST k4
  CALL cmd_starts_with, 2
  JZ dispatch_unknown
  PUSH_ADDR s_200_type
  CALL emit_ztext, 1
  POP
  PUSH_CONST k1
  LEAVE
  RETF

dispatch_unknown:
  PUSH_ADDR s_502
  CALL emit_ztext, 1
  POP
  PUSH_CONST k1
  LEAVE
  RETF

; =====================================================================
; cmd_starts_with(target_addr, n) — проверяет, что v_cmd_buf начинается
; с эталоном и за эталоном идёт ровно один из терминаторов команды
; (NUL, пробел, '\r', '\n'). Возвращает 1/0.
; =====================================================================
cmd_starts_with:
  STORE v_eq_n
  STORE v_eq_b
  ENTER 0

  ; Сравниваем первые n байт.
  PUSH_ADDR v_cmd_buf
  STORE v_eq_a
  PUSH_CONST k0
  STORE v_eq_i

cmd_starts_with_loop:
  LOAD v_eq_i
  LOAD v_eq_n
  LT
  JZ cmd_starts_with_check_end
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
  JZ cmd_starts_with_false
  LOAD v_eq_i
  PUSH_CONST k1
  ADD
  STORE v_eq_i
  JMP cmd_starts_with_loop

cmd_starts_with_check_end:
  ; После эталона должен идти терминатор: 0, ' ', '\r' или '\n'.
  PUSH_ADDR v_cmd_buf
  LOAD v_eq_n
  INDEXB
  LOADB_IND
  STORE v_eq_ca
  LOAD v_eq_ca
  PUSH_CONST k0
  EQ
  JZ cmd_starts_with_check_space
  PUSH_CONST k1
  LEAVE
  RETF
cmd_starts_with_check_space:
  LOAD v_eq_ca
  PUSH_CONST k32
  EQ
  JZ cmd_starts_with_check_cr
  PUSH_CONST k1
  LEAVE
  RETF
cmd_starts_with_check_cr:
  LOAD v_eq_ca
  PUSH_CONST k13
  EQ
  JZ cmd_starts_with_check_lf
  PUSH_CONST k1
  LEAVE
  RETF
cmd_starts_with_check_lf:
  LOAD v_eq_ca
  PUSH_CONST k10
  EQ
  JZ cmd_starts_with_false
  PUSH_CONST k1
  LEAVE
  RETF

cmd_starts_with_false:
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; compute_arg_offset — возвращает смещение в v_cmd_buf, где начинается
; аргумент команды (первый не-пробел после первого пробела).
; Если аргумента нет, возвращает 0.
; =====================================================================
compute_arg_offset:
  ENTER 0
  PUSH_CONST k0
  STORE v_eq_i

compute_arg_skip_token:
  ; Идём по байтам, пока не встретим пробел или конец строки.
  PUSH_ADDR v_cmd_buf
  LOAD v_eq_i
  INDEXB
  LOADB_IND
  STORE v_eq_ca
  LOAD v_eq_ca
  PUSH_CONST k0
  EQ
  JZ compute_arg_check_space
  ; Дошли до NUL — аргумента нет.
  PUSH_CONST k0
  LEAVE
  RETF

compute_arg_check_space:
  LOAD v_eq_ca
  PUSH_CONST k32
  EQ
  JZ compute_arg_advance
  ; Нашли пробел — пропускаем все пробелы.
  JMP compute_arg_skip_spaces

compute_arg_advance:
  LOAD v_eq_i
  PUSH_CONST k1
  ADD
  STORE v_eq_i
  JMP compute_arg_skip_token

compute_arg_skip_spaces:
  LOAD v_eq_i
  PUSH_CONST k1
  ADD
  STORE v_eq_i
  PUSH_ADDR v_cmd_buf
  LOAD v_eq_i
  INDEXB
  LOADB_IND
  STORE v_eq_ca
  LOAD v_eq_ca
  PUSH_CONST k32
  EQ
  JZ compute_arg_check_zero
  JMP compute_arg_skip_spaces

compute_arg_check_zero:
  LOAD v_eq_ca
  PUSH_CONST k0
  EQ
  JZ compute_arg_done
  ; Только пробелы до конца — аргумента нет.
  PUSH_CONST k0
  LEAVE
  RETF

compute_arg_done:
  LOAD v_eq_i
  LEAVE
  RETF

; =====================================================================
; arg_eq(target_addr) — сравнивает аргумент в v_cmd_buf
; (по смещению v_arg_off) с NUL-терминированной эталонной строкой.
; Аргумент завершается NUL/пробелом/'\r'/'\n'. Возвращает 1/0.
; =====================================================================
arg_eq:
  STORE v_eq_b
  ENTER 0
  ; Если аргумента нет (v_arg_off == 0), сразу возвращаем 0.
  LOAD v_arg_off
  PUSH_CONST k0
  EQ
  JZ arg_eq_start
  PUSH_CONST k0
  LEAVE
  RETF
arg_eq_start:
  PUSH_CONST k0
  STORE v_eq_i

arg_eq_loop:
  ; Берём очередной байт эталона и парный байт буфера команды.
  LOAD v_eq_b
  LOAD v_eq_i
  INDEXB
  LOADB_IND
  STORE v_eq_cb
  PUSH_ADDR v_cmd_buf
  LOAD v_arg_off
  LOAD v_eq_i
  ADD
  INDEXB
  LOADB_IND
  STORE v_eq_ca
  ; Если эталон дошёл до NUL — переходим к проверке терминатора в буфере.
  ; Иначе — сравниваем символы.
  LOAD v_eq_cb
  PUSH_CONST k0
  EQ
  JZ arg_eq_compare
  ; --- здесь cb == 0: эталон закончился, в буфере должен быть терминатор. ---
  LOAD v_eq_ca
  PUSH_CONST k0
  EQ
  JZ arg_eq_check_space
  PUSH_CONST k1
  LEAVE
  RETF
arg_eq_check_space:
  LOAD v_eq_ca
  PUSH_CONST k32
  EQ
  JZ arg_eq_check_cr
  PUSH_CONST k1
  LEAVE
  RETF
arg_eq_check_cr:
  LOAD v_eq_ca
  PUSH_CONST k13
  EQ
  JZ arg_eq_check_lf
  PUSH_CONST k1
  LEAVE
  RETF
arg_eq_check_lf:
  LOAD v_eq_ca
  PUSH_CONST k10
  EQ
  JZ arg_eq_false
  PUSH_CONST k1
  LEAVE
  RETF

arg_eq_compare:
  ; --- здесь cb != 0: символы должны совпасть, иначе fail. ---
  LOAD v_eq_ca
  LOAD v_eq_cb
  EQ
  JZ arg_eq_false
  LOAD v_eq_i
  PUSH_CONST k1
  ADD
  STORE v_eq_i
  JMP arg_eq_loop

arg_eq_false:
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; cmd_feat — список возможностей для стандартных FTP-клиентов.
; =====================================================================
cmd_feat:
  ENTER 0
  PUSH_ADDR s_feat_1
  CALL emit_ztext, 1
  POP
  PUSH_ADDR s_feat_2
  CALL emit_ztext, 1
  POP
  PUSH_ADDR s_feat_3
  CALL emit_ztext, 1
  POP
  PUSH_ADDR s_feat_4
  CALL emit_ztext, 1
  POP
  PUSH_ADDR s_feat_5
  CALL emit_ztext, 1
  POP
  PUSH_ADDR s_feat_6
  CALL emit_ztext, 1
  POP
  PUSH_ADDR s_feat_end
  CALL emit_ztext, 1
  POP
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; emit_pwd — печатает текущий каталог в формате 257 "<path>".
; =====================================================================
emit_pwd:
  ENTER 0
  PUSH_ADDR s_pwd_pre
  CALL emit_ztext, 1
  POP
  PUSH_ADDR v_pwd_buf
  LOAD v_pwd_len
  CALL emit_bytes, 2
  POP
emit_pwd_close:
  PUSH_ADDR s_pwd_post
  CALL emit_ztext, 1
  POP
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; pwd_set_root / pwd_append_name / pwd_pop — поддержка текущего пути
; для PWD. Имена берутся из DIR_ITEM, поэтому путь соответствует
; просканированному Btrfs-дереву, а не заранее заданному примеру.
; =====================================================================
pwd_set_root:
  ENTER 0
  PUSH_CONST k1
  STORE v_pwd_len
  PUSH_ADDR v_pwd_buf
  PUSH_CONST k0
  INDEXB
  PUSH_CONST c_slash
  STOREB_IND
  PUSH_CONST k0
  LEAVE
  RETF

pwd_append_name:
  STORE v_name_id
  ENTER 0
  LOAD v_name_id
  CALL name_load_info, 1
  POP
  LOAD v_pwd_len
  PUSH_CONST k1
  GT
  JZ pwd_append_copy
  PUSH_ADDR v_pwd_buf
  LOAD v_pwd_len
  INDEXB
  PUSH_CONST c_slash
  STOREB_IND
  LOAD v_pwd_len
  PUSH_CONST k1
  ADD
  STORE v_pwd_len
pwd_append_copy:
  PUSH_CONST k0
  STORE v_eq_i
pwd_append_loop:
  LOAD v_eq_i
  LOAD v_name_len
  LT
  JZ pwd_append_done
  PUSH_ADDR v_pwd_buf
  LOAD v_pwd_len
  LOAD v_eq_i
  ADD
  INDEXB
  PUSH_ADDR img_name_pool
  LOAD v_name_off
  LOAD v_eq_i
  ADD
  INDEXB
  LOADB_IND
  STOREB_IND
  LOAD v_eq_i
  PUSH_CONST k1
  ADD
  STORE v_eq_i
  JMP pwd_append_loop
pwd_append_done:
  LOAD v_pwd_len
  LOAD v_name_len
  ADD
  STORE v_pwd_len
  PUSH_CONST k0
  LEAVE
  RETF

pwd_pop:
  ENTER 0
  LOAD v_pwd_len
  PUSH_CONST k1
  LE
  JZ pwd_pop_loop
  CALL pwd_set_root, 0
  POP
  PUSH_CONST k0
  LEAVE
  RETF
pwd_pop_loop:
  LOAD v_pwd_len
  PUSH_CONST k1
  SUB
  STORE v_pwd_len
  LOAD v_pwd_len
  PUSH_CONST k1
  LE
  JZ pwd_pop_check_slash
  CALL pwd_set_root, 0
  POP
  PUSH_CONST k0
  LEAVE
  RETF
pwd_pop_check_slash:
  PUSH_ADDR v_pwd_buf
  LOAD v_pwd_len
  INDEXB
  LOADB_IND
  PUSH_CONST c_slash
  EQ
  JZ pwd_pop_loop
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; cmd_cwd — изменяет текущий каталог.
; Аргументы: "/", ".", ".." или имя DIR_ITEM в текущем каталоге.
; Поиск выполняется сканированием записей Btrfs DIR_ITEM.
; =====================================================================
cmd_cwd:
  ENTER 0
  LOAD v_lookup_count
  PUSH_CONST k1
  ADD
  STORE v_lookup_count

  ; arg == "/" означает переход в корень.
  PUSH_ADDR p_root
  CALL arg_eq, 1
  JZ cmd_cwd_check_dot
  LOAD img_root_inode
  STORE v_current_dir
  CALL pwd_set_root, 0
  POP
  JMP cmd_cwd_ok

cmd_cwd_check_dot:
  PUSH_ADDR p_dot
  CALL arg_eq, 1
  JZ cmd_cwd_check_dotdot
  ; "." — остаёмся в текущем каталоге.
  JMP cmd_cwd_ok

cmd_cwd_check_dotdot:
  PUSH_ADDR p_dotdot
  CALL arg_eq, 1
  JZ cmd_cwd_lookup_dir
  CALL fs_parent_of_current, 0
  STORE v_current_dir
  CALL pwd_pop, 0
  POP
  JMP cmd_cwd_ok

cmd_cwd_lookup_dir:
  CALL fs_find_dirent_by_arg, 0
  JZ cmd_cwd_missing
  LOAD v_found_type
  PUSH_CONST k_btrfs_ft_dir
  EQ
  JZ cmd_cwd_missing
  LOAD v_found_inode
  STORE v_current_dir
  LOAD v_arg_absolute
  PUSH_CONST k1
  EQ
  JZ cmd_cwd_append
  CALL pwd_set_root, 0
  POP
cmd_cwd_append:
  LOAD v_name_id
  CALL pwd_append_name, 1
  POP
  JMP cmd_cwd_ok

cmd_cwd_ok:
  PUSH_ADDR s_250
  CALL emit_ztext, 1
  POP
  PUSH_CONST k0
  LEAVE
  RETF

cmd_cwd_missing:
  PUSH_ADDR s_550
  CALL emit_ztext, 1
  POP
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; cmd_cdup — стандартный FTP-синоним CWD ...
; =====================================================================
cmd_cdup:
  ENTER 0
  LOAD v_lookup_count
  PUSH_CONST k1
  ADD
  STORE v_lookup_count
  CALL fs_parent_of_current, 0
  STORE v_current_dir
  CALL pwd_pop, 0
  POP
  PUSH_ADDR s_250
  CALL emit_ztext, 1
  POP
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; cmd_list — выводит элементы текущего каталога:
;   <type> <inode> <size> <name>
; type: 'd' для каталогов, 'f' для файлов.
; =====================================================================
cmd_list:
  ENTER 0
  LOAD v_lookup_count
  PUSH_CONST k1
  ADD
  STORE v_lookup_count
  PUSH_ADDR s_150_list
  CALL emit_ztext, 1
  POP
  PUSH_CONST k1
  STORE v_sink

  ; Сканируем DIR_ITEM дерева FS: parent == v_current_dir.
  PUSH_CONST k0
  STORE v_scan_i

cmd_list_loop:
  LOAD v_scan_i
  LOAD img_dirent_count
  LT
  JZ cmd_list_done

  PUSH_ADDR img_dirent_parent
  LOAD v_scan_i
  INDEX
  LOAD_IND
  LOAD v_current_dir
  EQ
  JZ cmd_list_next

  PUSH_ADDR img_dirent_inode
  LOAD v_scan_i
  INDEX
  LOAD_IND
  STORE v_file_inode

  LOAD v_file_inode
  CALL fs_load_inode_size, 1
  STORE v_file_size

  PUSH_ADDR img_dirent_name_id
  LOAD v_scan_i
  INDEX
  LOAD_IND
  STORE v_name_id

  PUSH_ADDR img_dirent_type
  LOAD v_scan_i
  INDEX
  LOAD_IND
  PUSH_CONST k_btrfs_ft_dir
  EQ
  JZ cmd_list_emit_file

  PUSH_CONST c_d
  LOAD v_file_inode
  LOAD v_file_size
  LOAD v_name_id
  CALL emit_list_entry, 4
  POP
  JMP cmd_list_next

cmd_list_emit_file:
  PUSH_CONST c_f
  LOAD v_file_inode
  LOAD v_file_size
  LOAD v_name_id
  CALL emit_list_entry, 4
  POP

cmd_list_next:
  LOAD v_scan_i
  PUSH_CONST k1
  ADD
  STORE v_scan_i
  JMP cmd_list_loop

cmd_list_done:
  CALL data_stream_flush, 0
  POP
  PUSH_CONST k0
  STORE v_sink
  PUSH_ADDR s_226
  CALL emit_ztext, 1
  POP
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; cmd_nlst — список одних имён через пассивный поток данных.
; =====================================================================
cmd_nlst:
  ENTER 0
  LOAD v_lookup_count
  PUSH_CONST k1
  ADD
  STORE v_lookup_count
  PUSH_ADDR s_150_list
  CALL emit_ztext, 1
  POP
  PUSH_CONST k1
  STORE v_sink

  PUSH_CONST k0
  STORE v_scan_i

cmd_nlst_loop:
  LOAD v_scan_i
  LOAD img_dirent_count
  LT
  JZ cmd_nlst_done
  PUSH_ADDR img_dirent_parent
  LOAD v_scan_i
  INDEX
  LOAD_IND
  LOAD v_current_dir
  EQ
  JZ cmd_nlst_next
  PUSH_ADDR img_dirent_name_id
  LOAD v_scan_i
  INDEX
  LOAD_IND
  CALL emit_name_by_id, 1
  POP
  PUSH_ADDR s_newline
  CALL emit_ztext, 1
  POP
cmd_nlst_next:
  LOAD v_scan_i
  PUSH_CONST k1
  ADD
  STORE v_scan_i
  JMP cmd_nlst_loop

cmd_nlst_done:
  CALL data_stream_flush, 0
  POP
  PUSH_CONST k0
  STORE v_sink
  PUSH_ADDR s_226
  CALL emit_ztext, 1
  POP
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; emit_list_entry(type, inode, size, name_id) — печатает строку LIST.
; Аргументы извлекаются в обратном порядке (CALL заталкивает их слева
; направо, вызываемая процедура снимает их в порядке, обратном объявлению).
; =====================================================================
emit_list_entry:
  STORE v_entry_name
  STORE v_entry_size
  STORE v_entry_inode
  STORE v_entry_type
  ENTER 0
  LOAD v_entry_type
  PUSH_CONST c_d
  EQ
  JZ emit_list_entry_file
  PUSH_ADDR s_unix_dir
  CALL emit_ztext, 1
  POP
  JMP emit_list_entry_common
emit_list_entry_file:
  PUSH_ADDR s_unix_file
  CALL emit_ztext, 1
  POP
emit_list_entry_common:
  ; Формат Unix LIST: тип/права, владелец/группа, размер, дата, имя.
  LOAD v_entry_size
  CALL emit_uint, 1
  POP
  PUSH_ADDR s_unix_date
  CALL emit_ztext, 1
  POP
  LOAD v_entry_name
  CALL emit_name_by_id, 1
  POP
  PUSH_ADDR s_newline
  CALL emit_ztext, 1
  POP
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; cmd_retr — извлекает встроенный extent файла по имени.
; DIR_ITEM выбирает inode, INODE_ITEM даёт размер, EXTENT_DATA даёт содержимое.
; =====================================================================
cmd_retr:
  ENTER 0
  LOAD v_lookup_count
  PUSH_CONST k1
  ADD
  STORE v_lookup_count

  CALL fs_find_dirent_by_arg, 0
  JZ cmd_retr_missing
  LOAD v_found_type
  PUSH_CONST k_btrfs_ft_reg
  EQ
  JZ cmd_retr_missing

  LOAD v_found_inode
  CALL fs_load_inode_size, 1
  STORE v_file_size
  LOAD v_found_inode
  CALL fs_find_extent_data, 1
  JZ cmd_retr_missing

  LOAD v_found_inode
  LOAD v_file_size
  LOAD v_found_block_off
  CALL emit_file, 3
  POP
  PUSH_CONST k0
  LEAVE
  RETF

cmd_retr_missing:
  PUSH_ADDR s_550
  CALL emit_ztext, 1
  POP
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; cmd_size — возвращает размер файла для FTP-клиентов перед RETR.
; =====================================================================
cmd_size:
  ENTER 0
  LOAD v_lookup_count
  PUSH_CONST k1
  ADD
  STORE v_lookup_count
  CALL fs_find_dirent_by_arg, 0
  JZ cmd_size_missing
  LOAD v_found_type
  PUSH_CONST k_btrfs_ft_reg
  EQ
  JZ cmd_size_missing
  LOAD v_found_inode
  CALL fs_load_inode_size, 1
  STORE v_file_size
  PUSH_ADDR s_213
  CALL emit_ztext, 1
  POP
  LOAD v_file_size
  CALL emit_uint, 1
  POP
  PUSH_ADDR s_newline
  CALL emit_ztext, 1
  POP
  PUSH_CONST k0
  LEAVE
  RETF

cmd_size_missing:
  PUSH_ADDR s_550
  CALL emit_ztext, 1
  POP
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; cmd_mdtm — детерминированная временная метка для всех файлов тестового образа.
; =====================================================================
cmd_mdtm:
  ENTER 0
  LOAD v_lookup_count
  PUSH_CONST k1
  ADD
  STORE v_lookup_count
  CALL fs_find_dirent_by_arg, 0
  JZ cmd_mdtm_missing
  PUSH_ADDR s_mdtm
  CALL emit_ztext, 1
  POP
  PUSH_CONST k0
  LEAVE
  RETF

cmd_mdtm_missing:
  PUSH_ADDR s_550
  CALL emit_ztext, 1
  POP
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; emit_file(inode, size, data_id) — печатает заголовок 150,
; содержимое и заключительную 226. Соответствует RETR в FTP.
; =====================================================================
emit_file:
  STORE v_file_data
  STORE v_file_size
  STORE v_file_inode
  ENTER 0
  PUSH_ADDR s_150_inode
  CALL emit_ztext, 1
  POP
  LOAD v_file_inode
  CALL emit_uint, 1
  POP
  PUSH_ADDR s_size
  CALL emit_ztext, 1
  POP
  LOAD v_file_size
  CALL emit_uint, 1
  POP
  PUSH_ADDR s_extent
  CALL emit_ztext, 1
  POP
  PUSH_CONST k1
  STORE v_sink
  LOAD v_file_data
  LOAD v_file_size
  CALL emit_block_data, 2
  POP
  CALL data_stream_flush, 0
  POP
  PUSH_CONST k0
  STORE v_sink
  PUSH_ADDR s_226
  CALL emit_ztext, 1
  POP
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; cmd_copy — явная команда копирования файла или каталога.
; Файл копируется как RETR. Каталог обходится рекурсивно через очередь
; inode каталогов: DIR_ITEM -> INODE_ITEM -> EXTENT_DATA.
; Аргументы: "/", ".", ".." или имя элемента текущей директории.
; =====================================================================
cmd_copy:
  ENTER 0
  LOAD v_lookup_count
  PUSH_CONST k1
  ADD
  STORE v_lookup_count

  ; COPY без аргумента не имеет смысла.
  LOAD v_arg_off
  PUSH_CONST k0
  EQ
  JZ cmd_copy_check_root
  JMP cmd_copy_missing

cmd_copy_check_root:
  PUSH_ADDR p_root
  CALL arg_eq, 1
  JZ cmd_copy_check_dot
  LOAD img_root_inode
  STORE v_copy_target
  PUSH_CONST k_btrfs_ft_dir
  STORE v_found_type
  JMP cmd_copy_dispatch

cmd_copy_check_dot:
  PUSH_ADDR p_dot
  CALL arg_eq, 1
  JZ cmd_copy_check_dotdot
  LOAD v_current_dir
  STORE v_copy_target
  PUSH_CONST k_btrfs_ft_dir
  STORE v_found_type
  JMP cmd_copy_dispatch

cmd_copy_check_dotdot:
  PUSH_ADDR p_dotdot
  CALL arg_eq, 1
  JZ cmd_copy_lookup
  CALL fs_parent_of_current, 0
  STORE v_copy_target
  PUSH_CONST k_btrfs_ft_dir
  STORE v_found_type
  JMP cmd_copy_dispatch

cmd_copy_lookup:
  CALL fs_find_dirent_by_arg, 0
  JZ cmd_copy_missing
  LOAD v_found_inode
  STORE v_copy_target

cmd_copy_dispatch:
  LOAD v_found_type
  PUSH_CONST k_btrfs_ft_reg
  EQ
  JZ cmd_copy_check_dir
  LOAD v_copy_target
  CALL copy_emit_inode_file, 1
  JZ cmd_copy_missing
  PUSH_CONST k0
  LEAVE
  RETF

cmd_copy_check_dir:
  LOAD v_found_type
  PUSH_CONST k_btrfs_ft_dir
  EQ
  JZ cmd_copy_missing
  LOAD v_copy_target
  CALL copy_dir_tree, 1
  POP
  PUSH_CONST k0
  LEAVE
  RETF

cmd_copy_missing:
  PUSH_ADDR s_550
  CALL emit_ztext, 1
  POP
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; copy_dir_tree(root_inode) — рекурсивно копирует все обычные файлы
; внутри каталога root_inode. Подкаталоги добавляются в очередь.
; =====================================================================
copy_dir_tree:
  STORE v_copy_target
  ENTER 0
  PUSH_ADDR s_150_copy_dir
  CALL emit_ztext, 1
  POP

  PUSH_CONST k0
  STORE v_copy_head
  PUSH_CONST k0
  STORE v_copy_tail

  ; Кладём root_inode в хвост очереди.
  PUSH_ADDR v_copy_queue
  LOAD v_copy_tail
  INDEX
  LOAD v_copy_target
  STORE_IND
  LOAD v_copy_tail
  PUSH_CONST k1
  ADD
  STORE v_copy_tail

copy_dir_queue_loop:
  LOAD v_copy_head
  LOAD v_copy_tail
  LT
  JZ copy_dir_done

  PUSH_ADDR v_copy_queue
  LOAD v_copy_head
  INDEX
  LOAD_IND
  STORE v_copy_dir
  LOAD v_copy_head
  PUSH_CONST k1
  ADD
  STORE v_copy_head

  PUSH_CONST k0
  STORE v_scan_i

copy_dir_scan_loop:
  LOAD v_scan_i
  LOAD img_dirent_count
  LT
  JZ copy_dir_queue_loop

  PUSH_ADDR img_dirent_parent
  LOAD v_scan_i
  INDEX
  LOAD_IND
  LOAD v_copy_dir
  EQ
  JZ copy_dir_next

  PUSH_ADDR img_dirent_inode
  LOAD v_scan_i
  INDEX
  LOAD_IND
  STORE v_file_inode

  PUSH_ADDR img_dirent_type
  LOAD v_scan_i
  INDEX
  LOAD_IND
  STORE v_found_type

  PUSH_ADDR img_dirent_name_id
  LOAD v_scan_i
  INDEX
  LOAD_IND
  STORE v_name_id

  LOAD v_found_type
  PUSH_CONST k_btrfs_ft_reg
  EQ
  JZ copy_dir_check_subdir

  PUSH_ADDR s_copy_file
  CALL emit_ztext, 1
  POP
  LOAD v_name_id
  CALL emit_name_by_id, 1
  POP
  PUSH_ADDR s_newline
  CALL emit_ztext, 1
  POP
  LOAD v_file_inode
  CALL copy_emit_inode_file, 1
  POP
  JMP copy_dir_next

copy_dir_check_subdir:
  LOAD v_found_type
  PUSH_CONST k_btrfs_ft_dir
  EQ
  JZ copy_dir_next
  LOAD v_copy_tail
  PUSH_CONST k256
  LT
  JZ copy_dir_next
  PUSH_ADDR v_copy_queue
  LOAD v_copy_tail
  INDEX
  LOAD v_file_inode
  STORE_IND
  LOAD v_copy_tail
  PUSH_CONST k1
  ADD
  STORE v_copy_tail

copy_dir_next:
  LOAD v_scan_i
  PUSH_CONST k1
  ADD
  STORE v_scan_i
  JMP copy_dir_scan_loop

copy_dir_done:
  PUSH_ADDR s_226_copy
  CALL emit_ztext, 1
  POP
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; copy_emit_inode_file(inode) — копирует обычный файл по inode.
; Возвращает 1, если встроенный extent найден, иначе 0.
; =====================================================================
copy_emit_inode_file:
  STORE v_file_inode
  ENTER 0
  LOAD v_file_inode
  CALL fs_load_inode_size, 1
  STORE v_file_size
  LOAD v_file_inode
  CALL fs_find_extent_data, 1
  JZ copy_emit_inode_file_missing
  LOAD v_file_inode
  LOAD v_file_size
  LOAD v_found_block_off
  CALL emit_file, 3
  POP
  PUSH_CONST k1
  LEAVE
  RETF

copy_emit_inode_file_missing:
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; fs_find_dirent_by_arg — ищет DIR_ITEM в текущем каталоге по аргументу
; команды. При успехе заполняет v_found_dirent/v_found_inode/
; v_found_type и возвращает 1.
; =====================================================================
fs_find_dirent_by_arg:
  ENTER 0
  LOAD v_arg_off
  PUSH_CONST k0
  EQ
  JZ fs_find_dirent_prepare
  PUSH_CONST k0
  LEAVE
  RETF

fs_find_dirent_prepare:
  PUSH_CONST k0
  STORE v_arg_absolute
  LOAD v_current_dir
  STORE v_find_parent
  LOAD v_arg_off
  STORE v_arg_cmp_off
  PUSH_ADDR v_cmd_buf
  LOAD v_arg_off
  INDEXB
  LOADB_IND
  PUSH_CONST c_slash
  EQ
  JZ fs_find_dirent_scan_start
  PUSH_CONST k1
  STORE v_arg_absolute
  LOAD img_root_inode
  STORE v_find_parent
  LOAD v_arg_off
  PUSH_CONST k1
  ADD
  STORE v_arg_cmp_off

fs_find_dirent_scan_start:
  PUSH_CONST k0
  STORE v_scan_i

fs_find_dirent_loop:
  LOAD v_scan_i
  LOAD img_dirent_count
  LT
  JZ fs_find_dirent_missing

  PUSH_ADDR img_dirent_parent
  LOAD v_scan_i
  INDEX
  LOAD_IND
  LOAD v_find_parent
  EQ
  JZ fs_find_dirent_next

  PUSH_ADDR img_dirent_name_id
  LOAD v_scan_i
  INDEX
  LOAD_IND
  STORE v_name_id
  LOAD v_name_id
  CALL fs_arg_eq_name, 1
  JZ fs_find_dirent_next

  LOAD v_scan_i
  STORE v_found_dirent
  PUSH_ADDR img_dirent_inode
  LOAD v_scan_i
  INDEX
  LOAD_IND
  STORE v_found_inode
  PUSH_ADDR img_dirent_type
  LOAD v_scan_i
  INDEX
  LOAD_IND
  STORE v_found_type
  PUSH_CONST k1
  LEAVE
  RETF

fs_find_dirent_next:
  LOAD v_scan_i
  PUSH_CONST k1
  ADD
  STORE v_scan_i
  JMP fs_find_dirent_loop

fs_find_dirent_missing:
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; fs_parent_of_current — находит родительский каталог текущего inode
; по DIR_ITEM с типом BTRFS_FT_DIR. Для корня возвращает корень.
; =====================================================================
fs_parent_of_current:
  ENTER 0
  LOAD v_current_dir
  LOAD img_root_inode
  EQ
  JZ fs_parent_scan
  LOAD img_root_inode
  LEAVE
  RETF

fs_parent_scan:
  PUSH_CONST k0
  STORE v_scan_i

fs_parent_loop:
  LOAD v_scan_i
  LOAD img_dirent_count
  LT
  JZ fs_parent_default_root

  PUSH_ADDR img_dirent_inode
  LOAD v_scan_i
  INDEX
  LOAD_IND
  LOAD v_current_dir
  EQ
  JZ fs_parent_next

  PUSH_ADDR img_dirent_type
  LOAD v_scan_i
  INDEX
  LOAD_IND
  PUSH_CONST k_btrfs_ft_dir
  EQ
  JZ fs_parent_next

  PUSH_ADDR img_dirent_parent
  LOAD v_scan_i
  INDEX
  LOAD_IND
  LEAVE
  RETF

fs_parent_next:
  LOAD v_scan_i
  PUSH_CONST k1
  ADD
  STORE v_scan_i
  JMP fs_parent_loop

fs_parent_default_root:
  LOAD img_root_inode
  LEAVE
  RETF

; =====================================================================
; fs_load_inode_size(inode) — ищет INODE_ITEM и возвращает size.
; Дополнительно заполняет v_found_type/v_found_size.
; =====================================================================
fs_load_inode_size:
  STORE v_found_inode
  ENTER 0
  PUSH_CONST k0
  STORE v_inode_i

fs_load_inode_loop:
  LOAD v_inode_i
  LOAD img_inode_count
  LT
  JZ fs_load_inode_missing

  PUSH_ADDR img_inode_objectid
  LOAD v_inode_i
  INDEX
  LOAD_IND
  LOAD v_found_inode
  EQ
  JZ fs_load_inode_next

  PUSH_ADDR img_inode_type
  LOAD v_inode_i
  INDEX
  LOAD_IND
  STORE v_found_type
  PUSH_ADDR img_inode_size
  LOAD v_inode_i
  INDEX
  LOAD_IND
  STORE v_found_size
  LOAD v_found_size
  LEAVE
  RETF

fs_load_inode_next:
  LOAD v_inode_i
  PUSH_CONST k1
  ADD
  STORE v_inode_i
  JMP fs_load_inode_loop

fs_load_inode_missing:
  PUSH_CONST k0
  STORE v_found_type
  PUSH_CONST k0
  STORE v_found_size
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; fs_find_extent_data(inode) — ищет EXTENT_DATA для inode.
; При успехе v_found_block_off указывает на физическое смещение
; данных в настоящем Btrfs-образе, подключённом как BlockDevice.
; =====================================================================
fs_find_extent_data:
  STORE v_found_inode
  ENTER 0
  PUSH_CONST k0
  STORE v_extent_i

fs_find_extent_loop:
  LOAD v_extent_i
  LOAD img_extent_count
  LT
  JZ fs_find_extent_missing

  PUSH_ADDR img_extent_inode
  LOAD v_extent_i
  INDEX
  LOAD_IND
  LOAD v_found_inode
  EQ
  JZ fs_find_extent_next

  PUSH_ADDR img_extent_block_off
  LOAD v_extent_i
  INDEX
  LOAD_IND
  STORE v_found_block_off
  PUSH_ADDR img_extent_size
  LOAD v_extent_i
  INDEX
  LOAD_IND
  STORE v_found_extent_size
  PUSH_CONST k1
  LEAVE
  RETF

fs_find_extent_next:
  LOAD v_extent_i
  PUSH_CONST k1
  ADD
  STORE v_extent_i
  JMP fs_find_extent_loop

fs_find_extent_missing:
  PUSH_CONST k0
  STORE v_found_data_id
  PUSH_CONST k0
  STORE v_found_block_off
  PUSH_CONST k0
  STORE v_found_extent_size
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; fs_arg_eq_name(name_id) — сравнивает аргумент FTP-команды с именем
; DIR_ITEM. Возвращает 1/0.
; =====================================================================
fs_arg_eq_name:
  STORE v_name_id
  ENTER 0
  LOAD v_name_id
  CALL name_load_info, 1
  POP
  PUSH_CONST k0
  STORE v_eq_i

fs_arg_name_loop:
  LOAD v_eq_i
  LOAD v_name_len
  LT
  JZ fs_arg_name_check_end
  PUSH_ADDR img_name_pool
  LOAD v_name_off
  LOAD v_eq_i
  ADD
  INDEXB
  LOADB_IND
  STORE v_eq_cb
  PUSH_ADDR v_cmd_buf
  LOAD v_arg_cmp_off
  LOAD v_eq_i
  ADD
  INDEXB
  LOADB_IND
  STORE v_eq_ca
  LOAD v_eq_ca
  LOAD v_eq_cb
  EQ
  JZ fs_arg_name_false
  LOAD v_eq_i
  PUSH_CONST k1
  ADD
  STORE v_eq_i
  JMP fs_arg_name_loop

fs_arg_name_check_end:
  PUSH_ADDR v_cmd_buf
  LOAD v_arg_cmp_off
  LOAD v_name_len
  ADD
  INDEXB
  LOADB_IND
  STORE v_eq_ca
  LOAD v_eq_ca
  PUSH_CONST k0
  EQ
  JZ fs_arg_name_check_space
  PUSH_CONST k1
  LEAVE
  RETF
fs_arg_name_check_space:
  LOAD v_eq_ca
  PUSH_CONST k32
  EQ
  JZ fs_arg_name_check_cr
  PUSH_CONST k1
  LEAVE
  RETF
fs_arg_name_check_cr:
  LOAD v_eq_ca
  PUSH_CONST k13
  EQ
  JZ fs_arg_name_check_lf
  PUSH_CONST k1
  LEAVE
  RETF
fs_arg_name_check_lf:
  LOAD v_eq_ca
  PUSH_CONST k10
  EQ
  JZ fs_arg_name_false
  PUSH_CONST k1
  LEAVE
  RETF
fs_arg_name_false:
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; name_load_info(name_id) — загружает offset/len имени из сгенерированной
; таблицы, полученной из реального дерева Btrfs.
; =====================================================================
name_load_info:
  STORE v_name_id
  ENTER 0
  LOAD v_name_id
  LOAD img_name_count
  LT
  JZ name_load_missing
  PUSH_ADDR img_name_offset
  LOAD v_name_id
  INDEX
  LOAD_IND
  STORE v_name_off
  PUSH_ADDR img_name_len
  LOAD v_name_id
  INDEX
  LOAD_IND
  STORE v_name_len
  PUSH_CONST k1
  LEAVE
  RETF
name_load_missing:
  PUSH_CONST k0
  STORE v_name_off
  PUSH_CONST k0
  STORE v_name_len
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; emit_name_by_id(name_id) — печатает имя DIR_ITEM через потоковый приёмник вывода.
; =====================================================================
emit_name_by_id:
  STORE v_name_id
  ENTER 0
  LOAD v_name_id
  CALL name_load_info, 1
  POP
  PUSH_ADDR img_name_pool
  LOAD v_name_off
  INDEXB
  LOAD v_name_len
  CALL emit_bytes, 2
  POP
emit_name_done:
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; emit_data_by_id оставлен только как совместимая заглушка: теперь RETR/COPY
; читают данные напрямую из физического смещения BlockDevice.
; =====================================================================
emit_data_by_id:
  STORE v_file_data
  ENTER 0
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; emit_stats — печатает итоговую статистику и маркер OK.
; =====================================================================
emit_stats:
  ENTER 0
  PUSH_ADDR s_stats_1
  CALL emit_ztext, 1
  POP
  LOAD v_cmd_count
  CALL emit_uint, 1
  POP
  PUSH_ADDR s_stats_2
  CALL emit_ztext, 1
  POP
  LOAD v_lookup_count
  CALL emit_uint, 1
  POP
  PUSH_ADDR s_stats_3
  CALL emit_ztext, 1
  POP
  LOAD v_stream_bytes
  CALL emit_uint, 1
  POP
  PUSH_ADDR s_stats_4
  CALL emit_ztext, 1
  POP
  LOAD v_group_waits
  CALL emit_uint, 1
  POP
  PUSH_ADDR s_newline
  CALL emit_ztext, 1
  POP
  PUSH_ADDR s_ok
  CALL emit_ztext, 1
  POP
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; emit_ztext(addr) — печатает NUL-терминированную строку через приёмник вывода.
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
  CALL stream_write_byte, 1
  POP
  LOAD v_emit_i
  PUSH_CONST k1
  ADD
  STORE v_emit_i
  JMP emit_ztext_loop

; =====================================================================
; emit_bytes(addr, n) — печатает n байт начиная с addr через приёмник вывода.
; =====================================================================
emit_bytes:
  STORE v_file_size
  STORE v_file_data
  ENTER 0
  PUSH_CONST k0
  STORE v_emit_i
emit_bytes_loop:
  LOAD v_emit_i
  LOAD v_file_size
  LT
  JZ emit_bytes_done
  LOAD v_file_data
  LOAD v_emit_i
  INDEXB
  LOADB_IND
  CALL stream_write_byte, 1
  POP
  LOAD v_emit_i
  PUSH_CONST k1
  ADD
  STORE v_emit_i
  JMP emit_bytes_loop
emit_bytes_done:
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; emit_block_data(block_offset, n) — читает n байт из BlockDevice и
; печатает через приёмник вывода. Для пассивного FTP-канала данные идут
; порциями: BackDevice/read заполняет block_buffer, а DATA_COPY_BLOCK
; переносит эту порцию в FSPipe. Побайтовый путь оставлен только как
; совместимый вариант для управляющего потока.
; =====================================================================
emit_block_data:
  STORE v_block_len
  STORE v_block_off
  ENTER 0
  PUSH_CONST k0
  STORE v_block_i
emit_block_data_loop:
  LOAD v_block_i
  LOAD v_block_len
  LT
  JZ emit_block_data_done
  LOAD v_block_len
  LOAD v_block_i
  SUB
  STORE v_block_chunk
  LOAD v_block_chunk
  PUSH_CONST k512
  LE
  JZ emit_block_data_limit_512
  JMP emit_block_data_chunk_ready
emit_block_data_limit_512:
  PUSH_CONST k512
  STORE v_block_chunk
emit_block_data_chunk_ready:
  LOAD v_block_off
  LOAD v_block_i
  ADD
  LOAD v_block_chunk
  BLOCK_READ_BUF
  LOAD v_sink
  PUSH_CONST k1
  EQ
  JZ emit_block_data_control_loop
  LOAD v_stream_bytes
  LOAD v_block_chunk
  ADD
  STORE v_stream_bytes
  LOAD v_group_waits
  LOAD v_block_chunk
  PUSH_CONST k7
  DIV
  ADD
  STORE v_group_waits
  LOAD v_block_chunk
  DATA_COPY_BLOCK
  JMP emit_block_data_chunk_done
emit_block_data_control_loop:
  PUSH_CONST k0
  STORE v_block_j
emit_block_data_chunk_loop:
  LOAD v_block_j
  LOAD v_block_chunk
  LT
  JZ emit_block_data_chunk_done
  LOAD v_block_j
  BLOCK_BUF_BYTE
  CALL stream_write_byte, 1
  POP
  LOAD v_block_j
  PUSH_CONST k1
  ADD
  STORE v_block_j
  JMP emit_block_data_chunk_loop
emit_block_data_chunk_done:
  LOAD v_block_i
  LOAD v_block_chunk
  ADD
  STORE v_block_i
  JMP emit_block_data_loop
emit_block_data_done:
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; emit_uint(n) — печатает беззнаковое десятичное число через приёмник вывода.
; Используем v_digits как стек цифр.
; =====================================================================
emit_uint:
  STORE v_uint_n
  ENTER 0
  PUSH_CONST k0
  STORE v_uint_cnt
  LOAD v_uint_n
  PUSH_CONST k0
  EQ
  JZ emit_uint_collect
  PUSH_CONST c_ascii_0
  CALL stream_write_byte, 1
  POP
  PUSH_CONST k0
  LEAVE
  RETF
emit_uint_collect:
  LOAD v_uint_n
  PUSH_CONST k0
  GT
  JZ emit_uint_print
  PUSH_ADDR v_digits
  LOAD v_uint_cnt
  INDEXB
  LOAD v_uint_n
  PUSH_CONST k10
  REM
  PUSH_CONST c_ascii_0
  ADD
  STOREB_IND
  LOAD v_uint_n
  PUSH_CONST k10
  DIV
  STORE v_uint_n
  LOAD v_uint_cnt
  PUSH_CONST k1
  ADD
  STORE v_uint_cnt
  JMP emit_uint_collect
emit_uint_print:
  LOAD v_uint_cnt
  PUSH_CONST k0
  GT
  JZ emit_uint_done
  LOAD v_uint_cnt
  PUSH_CONST k1
  SUB
  STORE v_uint_cnt
  PUSH_ADDR v_digits
  LOAD v_uint_cnt
  INDEXB
  LOADB_IND
  CALL stream_write_byte, 1
  POP
  JMP emit_uint_print
emit_uint_done:
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; ztext_eq(a, b) — сравнивает две NUL-терминированные строки байт-в-байт.
; Используется в btrfs_mount для сверки магического значения суперблока.
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
; stream_write_byte(byte) — единая точка вывода, то есть приёмник потока.
; Соответствует приёмнику потокового конвейера из SPO7:
;   - увеличивает счётчик переданных байтов v_stream_bytes;
;   - после каждых v_stream_window=7 байт фиксирует пассивное
;     GROUP_WAIT (v_group_waits++) — модель синхронных неблокирующих операций;
;   - затем дописывает байт в SimplePipe SyncSend через PIPE_OUT.
; =====================================================================
stream_write_byte:
  STORE v_stream_ch
  ENTER 0
  LOAD v_stream_bytes
  PUSH_CONST k1
  ADD
  STORE v_stream_bytes
  LOAD v_stream_window
  PUSH_CONST k1
  SUB
  STORE v_stream_window
  LOAD v_stream_window
  PUSH_CONST k0
  EQ
  JZ stream_write_out
  ; Пассивное GROUP_WAIT: приёмник сообщает планировщику, что окно
  ; неблокирующих операций исчерпано, и сбрасывает его на 7.
  LOAD v_group_waits
  PUSH_CONST k1
  ADD
  STORE v_group_waits
  PUSH_CONST k7
  STORE v_stream_window
stream_write_out:
  LOAD v_stream_ch
  LOAD v_sink
  PUSH_CONST k1
  EQ
  JZ stream_write_control
  CALL data_stream_write_byte, 1
  POP
  PUSH_CONST k0
  LEAVE
  RETF
stream_write_control:
  PIPE_OUT
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; data_stream_write_byte(byte) / data_stream_flush()
; Отдельный пассивный канал данных. Для RemoteTasks SimplePipe это
; быстрее и ближе к реальному FTP, чем отправлять каждый байт через
; control[0] SyncSend: байты копятся в outbox, затем отправляются
; одной операцией Sending.
; =====================================================================
data_stream_write_byte:
  STORE v_stream_ch
  ENTER 0
  LOAD v_data_len
  LOAD v_stream_ch
  DATA_BUF_BYTE
  LOAD v_data_len
  PUSH_CONST k1
  ADD
  STORE v_data_len
  LOAD v_data_len
  PUSH_CONST k512
  EQ
  JZ data_stream_write_done
  CALL data_stream_flush, 0
  POP
data_stream_write_done:
  PUSH_CONST k0
  LEAVE
  RETF

data_stream_flush:
  ENTER 0
  LOAD v_data_len
  DATA_FLUSH
  PUSH_CONST k0
  STORE v_data_len
  PUSH_CONST k0
  LEAVE
  RETF
