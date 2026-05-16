; =====================================================================
; SPO8 — чтение Btrfs-образа через PASSIVE FTP.
; Вариант 4 практического задания №3 дисциплины СПО.
;
; Модель работы:
;   1) btrfs_mount проверяет superblock — пункт 1 общего алгоритма
;      задания «проверить, поддерживается ли FS». При неудаче выдаёт
;      ответ 500 и не входит в FTP-цикл.
;   2) ftp_loop читает команды из byte stream stdin (port 0)
;      и обрабатывает их через dispatch_command — пункт 2:
;      диалоговый режим в стиле PASSIVE FTP.
;   3) Команды LIST/RETR/CWD/PWD реализуют требования 2a/2b/2c.
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
k7:   DD 7        ; v_stream_window: каждые 7 байт фиксируем passive wait
k10:  DD 10       ; \n
k13:  DD 13       ; \r
k32:  DD 32       ; ' ' — разделитель между командой и аргументом
k63:  DD 63       ; максимально допустимая длина команды (буфер 64 - 1)
k4096: DD 4096    ; ожидаемый Btrfs nodesize
k_btrfs_ft_reg: DD 1 ; BTRFS_FT_REG_FILE
k_btrfs_ft_dir: DD 2 ; BTRFS_FT_DIR

; ASCII-литералы для типов записей DIR_ITEM в листинге.
c_d:       DD 100   ; 'd' — каталог
c_f:       DD 102   ; 'f' — обычный файл
c_ascii_0: DD 48    ; '0' — для печати чисел

[section data_mem]
; ---------------------------------------------------------------------
; Раздел 1. Состояние FTP-runtime.
; ---------------------------------------------------------------------
; v_current_dir хранит inode текущего каталога из FS tree:
;   256 — /, 258 — /docs, 260 — /pictures.
; Путь для PWD восстанавливается из DIR_ITEM/INODE_ITEM образа.
v_current_dir:   DD 0

; v_cmd_count   — сколько FTP-команд обработано в этой сессии.
; v_lookup_count — сколько обращений к FS-tree выполнили cmd_*.
; v_stream_bytes — сколько байт передал sink в выходной поток.
; v_stream_window — счётчик до следующего passive wait (см. SPO7).
; v_group_waits  — сколько раз фиксировался passive wait.
v_cmd_count:     DD 0
v_lookup_count:  DD 0
v_stream_bytes:  DD 0
v_stream_window: DD 7
v_group_waits:   DD 0

; ---------------------------------------------------------------------
; Раздел 2. Скретч-переменные процедур.
; Используются совместно — память кадров CALL у нас shared
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

; Параметры sink stream_write_byte.
v_stream_ch: DD 0

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

; Состояние сканирования Btrfs FS tree leaf.
v_scan_i:        DD 0
v_inode_i:       DD 0
v_extent_i:      DD 0
v_found_dirent:  DD 0
v_found_inode:   DD 0
v_found_size:    DD 0
v_found_type:    DD 0
v_found_data_id: DD 0
v_name_id:       DD 0

; ---------------------------------------------------------------------
; Раздел 3. Буферы.
; ---------------------------------------------------------------------
; v_cmd_buf — буфер прочитанной FTP-команды (включая аргумент).
; Заканчивается NUL-байтом, размер до 63 значащих байт + NUL.
v_cmd_buf: RESB 64

; v_digits — буфер для печати беззнаковых чисел в десятичной системе.
v_digits: RESB 16

; ---------------------------------------------------------------------
; Раздел 4. Btrfs-образ варианта 4.
;
; Образ хранится как compact FS-tree leaf с Btrfs key/value полями:
; DIR_ITEM (parent directory objectid -> target inode/type/name),
; INODE_ITEM (inode -> size/type) и EXTENT_DATA (inode -> inline data).
; Сами поля описаны в docs/btrfs_image.md.
;
; Содержимое:
;   /                      каталог (inode 256)
;     docs/                каталог (inode 258)
;       info.txt           inline-extent, 19 байт   (inode 259)
;       help.txt           inline-extent, 12 байт   (inode 261)
;     pictures/            каталог (inode 260)
;       notes.txt          inline-extent, 17 байт   (inode 262)
;     readme.txt           inline-extent, 19 байт   (inode 257)
; ---------------------------------------------------------------------

; --- Btrfs superblock (упрощённая версия). ---
; В реальном Btrfs superblock начинается с offset 0x10000, magic
; находится по offset 0x40 относительно его начала. Здесь мы
; храним только поля, нужные для mount-проверки.
img_super_magic:        DB "_BHRfS_M"
img_super_magic_z:      DB 0
img_root_dir_objectid:  DD 6
img_nodesize:           DD 4096
img_root_tree_logical:  DD 4194304   ; 0x00400000
img_chunk_tree_logical: DD 5242880   ; 0x00500000
img_fs_tree_objectid:   DD 5
img_fs_tree_leaf_logical: DD 6291456 ; 0x00600000

; --- INODE_ITEM-номера. ---
img_root_inode:     DD 256
img_docs_inode:     DD 258
img_pictures_inode: DD 260
img_readme_inode:   DD 257
img_info_inode:     DD 259
img_help_inode:     DD 261
img_notes_inode:    DD 262

; --- размеры файлов (поле size INODE_ITEM). ---
img_zero_size:   DD 0
img_readme_size: DD 19
img_info_size:   DD 19
img_help_size:   DD 12
img_notes_size:  DD 17

; --- DIR_ITEM имена (NUL-терминированные ASCII). ---
img_name_docs:     DB "docs"
img_name_docs_z:   DB 0
img_name_pictures: DB "pictures"
img_name_pictures_z: DB 0
img_name_readme:   DB "readme.txt"
img_name_readme_z: DB 0
img_name_info:     DB "info.txt"
img_name_info_z:   DB 0
img_name_help:     DB "help.txt"
img_name_help_z:   DB 0
img_name_notes:    DB "notes.txt"
img_name_notes_z:  DB 0

; --- inline EXTENT_DATA (тип = 0). ---
img_data_readme:   DB "Hello from SPO8 FS"
img_data_readme_lf: DB 10
img_data_readme_z: DB 0
img_data_info:     DB "BTRFS TREE WALK OK"
img_data_info_lf:  DB 10
img_data_info_z:   DB 0
img_data_help:     DB "RETR works."
img_data_help_lf:  DB 10
img_data_help_z:   DB 0
img_data_notes:    DB "subtree readable"
img_data_notes_lf: DB 10
img_data_notes_z:  DB 0

; --- FS tree leaf: INODE_ITEM records. ---
; type соответствует BTRFS_FT_*; size — поле INODE_ITEM.size.
img_inode_count: DD 7
img_inode_objectid: DD 256
img_inode_objectid_1: DD 258
img_inode_objectid_2: DD 260
img_inode_objectid_3: DD 257
img_inode_objectid_4: DD 259
img_inode_objectid_5: DD 261
img_inode_objectid_6: DD 262
img_inode_type: DD 2
img_inode_type_1: DD 2
img_inode_type_2: DD 2
img_inode_type_3: DD 1
img_inode_type_4: DD 1
img_inode_type_5: DD 1
img_inode_type_6: DD 1
img_inode_size: DD 0
img_inode_size_1: DD 0
img_inode_size_2: DD 0
img_inode_size_3: DD 19
img_inode_size_4: DD 19
img_inode_size_5: DD 12
img_inode_size_6: DD 17

; --- FS tree leaf: DIR_ITEM records. ---
; parent — objectid каталога, inode — location.objectid целевой записи,
; name_id выбирает NUL-терминированное имя ниже через emit_name_by_id.
img_dirent_count: DD 6
img_dirent_parent: DD 256
img_dirent_parent_1: DD 256
img_dirent_parent_2: DD 256
img_dirent_parent_3: DD 258
img_dirent_parent_4: DD 258
img_dirent_parent_5: DD 260
img_dirent_inode: DD 258
img_dirent_inode_1: DD 260
img_dirent_inode_2: DD 257
img_dirent_inode_3: DD 259
img_dirent_inode_4: DD 261
img_dirent_inode_5: DD 262
img_dirent_type: DD 2
img_dirent_type_1: DD 2
img_dirent_type_2: DD 1
img_dirent_type_3: DD 1
img_dirent_type_4: DD 1
img_dirent_type_5: DD 1
img_dirent_name_id: DD 1
img_dirent_name_id_1: DD 2
img_dirent_name_id_2: DD 3
img_dirent_name_id_3: DD 4
img_dirent_name_id_4: DD 5
img_dirent_name_id_5: DD 6

; --- FS tree leaf: EXTENT_DATA records. ---
; extent_type 0 означает inline extent; data_id выбирает byte payload.
img_extent_count: DD 4
img_extent_inode: DD 257
img_extent_inode_1: DD 259
img_extent_inode_2: DD 261
img_extent_inode_3: DD 262
img_extent_type: DD 0
img_extent_type_1: DD 0
img_extent_type_2: DD 0
img_extent_type_3: DD 0
img_extent_data_id: DD 1
img_extent_data_id_1: DD 2
img_extent_data_id_2: DD 3
img_extent_data_id_3: DD 4

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

; --- эталонные пути для CWD. ---
p_root:     DB "/"
p_root_z:   DB 0
p_dot:      DB "."
p_dot_z:    DB 0
p_dotdot:   DB ".."
p_dotdot_z: DB 0
p_docs:     DB "docs"
p_docs_z:   DB 0
p_pictures: DB "pictures"
p_pictures_z: DB 0

; --- эталонные имена файлов для RETR. ---
n_readme: DB "readme.txt"
n_readme_z: DB 0
n_info:   DB "info.txt"
n_info_z: DB 0
n_help:   DB "help.txt"
n_help_z: DB 0
n_notes:  DB "notes.txt"
n_notes_z: DB 0

; ---------------------------------------------------------------------
; Раздел 6. Сообщения протокола PASSIVE FTP и баннеры.
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
s_227:       DB "227 Entering Passive Mode (0,0,0,0,0,1)"
s_227_lf:    DB 10
s_227_z:     DB 0
s_pwd_pre:   DB "257 "
s_pwd_pre_quote: DB 34
s_pwd_pre_z: DB 0
s_pwd_root:  DB "/"
s_pwd_root_z: DB 0
s_pwd_docs:  DB "/docs"
s_pwd_docs_z: DB 0
s_pwd_pictures: DB "/pictures"
s_pwd_pictures_z: DB 0
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
s_extent:    DB " extent=inline"
s_extent_lf: DB 10
s_extent_z:  DB 0
s_215:       DB "215 UNIX Type: L8"
s_215_lf:    DB 10
s_215_z:     DB 0
s_200_noop:  DB "200 NOOP ok"
s_200_noop_lf: DB 10
s_200_noop_z: DB 0
s_200_type:  DB "200 Type set"
s_200_type_lf: DB 10
s_200_type_z: DB 0
s_help_1:    DB "214-Supported commands:"
s_help_1_lf: DB 10
s_help_1_z:  DB 0
s_help_2:    DB "214 PASV PWD LIST CWD RETR SYST NOOP HELP TYPE QUIT"
s_help_2_lf: DB 10
s_help_2_z:  DB 0
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
  ; SPO8 использует общий image data_mem для Btrfs-образа, FTP-runtime
  ; и состояния потока. Чтобы CALL не выделял отдельный кадр под каждую
  ; процедуру, выставляем df_size=0 (POP_SYS 19) — все процедуры будут
  ; работать с одной и той же памятью данных.
  PUSH_CONST k0
  POP_SYS 19

  ; Сбрасываем счётчики FTP-runtime.
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

  ; --- Пункт 1 общего алгоритма: проверяем поддержку FS. ---
  CALL btrfs_mount, 0
  JZ main_mount_fail

  ; FS поддерживается — печатаем баннер и сводку superblock.
  PUSH_ADDR s_banner
  CALL emit_ztext, 1
  POP
  PUSH_ADDR s_fs_ok_1
  CALL emit_ztext, 1
  POP
  LOAD img_root_dir_objectid
  CALL emit_uint, 1
  POP
  PUSH_ADDR s_fs_ok_2
  CALL emit_ztext, 1
  POP
  LOAD img_nodesize
  CALL emit_uint, 1
  POP
  PUSH_ADDR s_newline
  CALL emit_ztext, 1
  POP
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

; =====================================================================
; btrfs_mount — проверяет, что образ соответствует Btrfs.
; Возвращает 1 при успехе, 0 при отказе.
; Условия поддержки:
;   1) magic совпадает с "_BHRfS_M";
;   2) nodesize == 4096;
;   3) root_dir_objectid > 0.
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
; ftp_loop — основной диалоговый цикл.
; Читает строки команд из stdin, эхо-печатает их и диспатчит.
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
  CALL echo_command, 0
  POP
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
  ; port 0 — стандартный вход VM (rin_s).
  PUSH_CONST k0
  SET_PORT
  PUSH_CONST k0
  STORE v_read_i

read_line_loop:
  IN
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
; Соответствует поведению PASSIVE FTP, когда сервер подтверждает
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

  ; QUIT — завершение сессии.
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
  JZ dispatch_check_cwd
  CALL cmd_list, 0
  POP
  PUSH_CONST k1
  LEAVE
  RETF

dispatch_check_cwd:
  PUSH_ADDR m_cwd
  PUSH_CONST k3
  CALL cmd_starts_with, 2
  JZ dispatch_check_retr
  CALL cmd_cwd, 0
  POP
  PUSH_CONST k1
  LEAVE
  RETF

dispatch_check_retr:
  PUSH_ADDR m_retr
  PUSH_CONST k4
  CALL cmd_starts_with, 2
  JZ dispatch_check_syst
  CALL cmd_retr, 0
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
; с target и за target идёт ровно один из терминаторов команды
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
  ; После target должен идти терминатор: 0, ' ', '\r' или '\n'.
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
; (по смещению v_arg_off) с NUL-терминированной строкой target.
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
  ; Берём очередной байт target и парный байт буфера команды.
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
  ; Если target дошёл до NUL — переходим к проверке терминатора в буфере.
  ; Иначе — сравниваем символы.
  LOAD v_eq_cb
  PUSH_CONST k0
  EQ
  JZ arg_eq_compare
  ; --- здесь cb == 0: target закончился, в буфере должен быть терминатор. ---
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
; emit_pwd — печатает текущий каталог в формате 257 "<path>".
; =====================================================================
emit_pwd:
  ENTER 0
  PUSH_ADDR s_pwd_pre
  CALL emit_ztext, 1
  POP
  LOAD v_current_dir
  LOAD img_root_inode
  EQ
  JZ emit_pwd_check_docs
  PUSH_ADDR s_pwd_root
  CALL emit_ztext, 1
  POP
  JMP emit_pwd_close
emit_pwd_check_docs:
  LOAD v_current_dir
  LOAD img_docs_inode
  EQ
  JZ emit_pwd_pictures
  PUSH_ADDR s_pwd_docs
  CALL emit_ztext, 1
  POP
  JMP emit_pwd_close
emit_pwd_pictures:
  PUSH_ADDR s_pwd_pictures
  CALL emit_ztext, 1
  POP
emit_pwd_close:
  PUSH_ADDR s_pwd_post
  CALL emit_ztext, 1
  POP
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; cmd_cwd — изменяет текущий каталог.
; Аргументы: "/", ".", ".." или имя DIR_ITEM в текущем каталоге.
; Поиск выполняется сканированием Btrfs DIR_ITEM records.
; =====================================================================
cmd_cwd:
  ENTER 0
  LOAD v_lookup_count
  PUSH_CONST k1
  ADD
  STORE v_lookup_count

  ; arg == "/" -> root
  PUSH_ADDR p_root
  CALL arg_eq, 1
  JZ cmd_cwd_check_dot
  LOAD img_root_inode
  STORE v_current_dir
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

  ; Сканируем FS tree DIR_ITEM: parent == v_current_dir.
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
  PUSH_ADDR s_226
  CALL emit_ztext, 1
  POP
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; emit_list_entry(type, inode, size, name_id) — печатает строку LIST.
; Аргументы извлекаются в обратном порядке (CALL заталкивает их слева
; направо, callee снимает в порядке, обратном объявлению).
; =====================================================================
emit_list_entry:
  STORE v_entry_name
  STORE v_entry_size
  STORE v_entry_inode
  STORE v_entry_type
  ENTER 0
  LOAD v_entry_type
  CALL stream_write_byte, 1
  POP
  PUSH_CONST k32
  CALL stream_write_byte, 1
  POP
  LOAD v_entry_inode
  CALL emit_uint, 1
  POP
  PUSH_CONST k32
  CALL stream_write_byte, 1
  POP
  LOAD v_entry_size
  CALL emit_uint, 1
  POP
  PUSH_CONST k32
  CALL stream_write_byte, 1
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
; cmd_retr — извлекает inline-extent файла по имени.
; DIR_ITEM выбирает inode, INODE_ITEM даёт размер, EXTENT_DATA даёт payload.
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
  LOAD v_found_data_id
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
  LOAD v_file_data
  CALL emit_data_by_id, 1
  POP
  PUSH_ADDR s_226
  CALL emit_ztext, 1
  POP
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
  LOAD v_current_dir
  EQ
  JZ fs_find_dirent_next

  PUSH_ADDR img_dirent_name_id
  LOAD v_scan_i
  INDEX
  LOAD_IND
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
; fs_find_extent_data(inode) — ищет inline EXTENT_DATA для inode.
; При успехе v_found_data_id указывает на payload.
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

  PUSH_ADDR img_extent_type
  LOAD v_extent_i
  INDEX
  LOAD_IND
  PUSH_CONST k0
  EQ
  JZ fs_find_extent_next

  PUSH_ADDR img_extent_data_id
  LOAD v_extent_i
  INDEX
  LOAD_IND
  STORE v_found_data_id
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
  PUSH_CONST k1
  EQ
  JZ fs_arg_name_2
  PUSH_ADDR img_name_docs
  CALL arg_eq, 1
  LEAVE
  RETF
fs_arg_name_2:
  LOAD v_name_id
  PUSH_CONST k2
  EQ
  JZ fs_arg_name_3
  PUSH_ADDR img_name_pictures
  CALL arg_eq, 1
  LEAVE
  RETF
fs_arg_name_3:
  LOAD v_name_id
  PUSH_CONST k3
  EQ
  JZ fs_arg_name_4
  PUSH_ADDR img_name_readme
  CALL arg_eq, 1
  LEAVE
  RETF
fs_arg_name_4:
  LOAD v_name_id
  PUSH_CONST k4
  EQ
  JZ fs_arg_name_5
  PUSH_ADDR img_name_info
  CALL arg_eq, 1
  LEAVE
  RETF
fs_arg_name_5:
  LOAD v_name_id
  PUSH_CONST k5
  EQ
  JZ fs_arg_name_6
  PUSH_ADDR img_name_help
  CALL arg_eq, 1
  LEAVE
  RETF
fs_arg_name_6:
  LOAD v_name_id
  PUSH_CONST k6
  EQ
  JZ fs_arg_name_missing
  PUSH_ADDR img_name_notes
  CALL arg_eq, 1
  LEAVE
  RETF
fs_arg_name_missing:
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; emit_name_by_id(name_id) — печатает имя DIR_ITEM через stream sink.
; =====================================================================
emit_name_by_id:
  STORE v_name_id
  ENTER 0
  LOAD v_name_id
  PUSH_CONST k1
  EQ
  JZ emit_name_2
  PUSH_ADDR img_name_docs
  CALL emit_ztext, 1
  POP
  JMP emit_name_done
emit_name_2:
  LOAD v_name_id
  PUSH_CONST k2
  EQ
  JZ emit_name_3
  PUSH_ADDR img_name_pictures
  CALL emit_ztext, 1
  POP
  JMP emit_name_done
emit_name_3:
  LOAD v_name_id
  PUSH_CONST k3
  EQ
  JZ emit_name_4
  PUSH_ADDR img_name_readme
  CALL emit_ztext, 1
  POP
  JMP emit_name_done
emit_name_4:
  LOAD v_name_id
  PUSH_CONST k4
  EQ
  JZ emit_name_5
  PUSH_ADDR img_name_info
  CALL emit_ztext, 1
  POP
  JMP emit_name_done
emit_name_5:
  LOAD v_name_id
  PUSH_CONST k5
  EQ
  JZ emit_name_6
  PUSH_ADDR img_name_help
  CALL emit_ztext, 1
  POP
  JMP emit_name_done
emit_name_6:
  LOAD v_name_id
  PUSH_CONST k6
  EQ
  JZ emit_name_done
  PUSH_ADDR img_name_notes
  CALL emit_ztext, 1
  POP
emit_name_done:
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; emit_data_by_id(data_id) — печатает inline EXTENT_DATA payload.
; Размер берётся из v_file_size, полученного из INODE_ITEM.
; =====================================================================
emit_data_by_id:
  STORE v_file_data
  ENTER 0
  LOAD v_file_data
  PUSH_CONST k1
  EQ
  JZ emit_data_2
  PUSH_ADDR img_data_readme
  LOAD v_file_size
  CALL emit_bytes, 2
  POP
  JMP emit_data_done
emit_data_2:
  LOAD v_file_data
  PUSH_CONST k2
  EQ
  JZ emit_data_3
  PUSH_ADDR img_data_info
  LOAD v_file_size
  CALL emit_bytes, 2
  POP
  JMP emit_data_done
emit_data_3:
  LOAD v_file_data
  PUSH_CONST k3
  EQ
  JZ emit_data_4
  PUSH_ADDR img_data_help
  LOAD v_file_size
  CALL emit_bytes, 2
  POP
  JMP emit_data_done
emit_data_4:
  LOAD v_file_data
  PUSH_CONST k4
  EQ
  JZ emit_data_done
  PUSH_ADDR img_data_notes
  LOAD v_file_size
  CALL emit_bytes, 2
  POP
emit_data_done:
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
; emit_ztext(addr) — печатает NUL-терминированную строку через sink.
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
; emit_bytes(addr, n) — печатает n байт начиная с addr через sink.
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
; emit_uint(n) — печатает беззнаковое десятичное число через sink.
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
; Используется только в btrfs_mount для сверки superblock magic.
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
; stream_write_byte(byte) — единая точка вывода (sink).
; Соответствует sink stream-pipeline’а из SPO7:
;   - увеличивает счётчик переданных байтов v_stream_bytes;
;   - после каждых v_stream_window=7 байт фиксирует passive
;     GROUP_WAIT (v_group_waits++) — модель «synchronous non-blocking»;
;   - затем дописывает байт в port 1 (rout_s).
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
  ; passive GROUP_WAIT — sink сообщает планировщику, что окно
  ; неблокирующих операций исчерпано, и сбрасывает его на 7.
  LOAD v_group_waits
  PUSH_CONST k1
  ADD
  STORE v_group_waits
  PUSH_CONST k7
  STORE v_stream_window
stream_write_out:
  PUSH_CONST k1
  SET_PORT
  LOAD v_stream_ch
  OUT
  PUSH_CONST k0
  LEAVE
  RETF
