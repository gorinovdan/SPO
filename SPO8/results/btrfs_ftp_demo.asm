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
v_path_next:     DD 0
v_path_has_more: DD 0
v_path_inode:    DD 0

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
; Этот раздел генерируется из настоящего Btrfs-образа,
; созданного через mkfs.btrfs, mount, копирование SPO8 и umount.
; В VM таблицы используются как индекс дерева, а байты RETR/COPY
; читаются напрямую из BlockDevice по физическим смещениям extent.
; ---------------------------------------------------------------------
img_root_inode: DD 256

img_inode_count: DD 65
img_inode_objectid: DD 256
img_inode_objectid_1: DD 257
img_inode_objectid_2: DD 258
img_inode_objectid_3: DD 259
img_inode_objectid_4: DD 260
img_inode_objectid_5: DD 261
img_inode_objectid_6: DD 262
img_inode_objectid_7: DD 263
img_inode_objectid_8: DD 264
img_inode_objectid_9: DD 265
img_inode_objectid_10: DD 266
img_inode_objectid_11: DD 267
img_inode_objectid_12: DD 268
img_inode_objectid_13: DD 269
img_inode_objectid_14: DD 270
img_inode_objectid_15: DD 271
img_inode_objectid_16: DD 272
img_inode_objectid_17: DD 273
img_inode_objectid_18: DD 274
img_inode_objectid_19: DD 275
img_inode_objectid_20: DD 276
img_inode_objectid_21: DD 277
img_inode_objectid_22: DD 278
img_inode_objectid_23: DD 279
img_inode_objectid_24: DD 280
img_inode_objectid_25: DD 281
img_inode_objectid_26: DD 282
img_inode_objectid_27: DD 283
img_inode_objectid_28: DD 284
img_inode_objectid_29: DD 285
img_inode_objectid_30: DD 286
img_inode_objectid_31: DD 287
img_inode_objectid_32: DD 288
img_inode_objectid_33: DD 289
img_inode_objectid_34: DD 290
img_inode_objectid_35: DD 291
img_inode_objectid_36: DD 292
img_inode_objectid_37: DD 293
img_inode_objectid_38: DD 294
img_inode_objectid_39: DD 295
img_inode_objectid_40: DD 296
img_inode_objectid_41: DD 297
img_inode_objectid_42: DD 298
img_inode_objectid_43: DD 299
img_inode_objectid_44: DD 300
img_inode_objectid_45: DD 301
img_inode_objectid_46: DD 302
img_inode_objectid_47: DD 303
img_inode_objectid_48: DD 304
img_inode_objectid_49: DD 305
img_inode_objectid_50: DD 306
img_inode_objectid_51: DD 307
img_inode_objectid_52: DD 308
img_inode_objectid_53: DD 309
img_inode_objectid_54: DD 310
img_inode_objectid_55: DD 311
img_inode_objectid_56: DD 312
img_inode_objectid_57: DD 313
img_inode_objectid_58: DD 314
img_inode_objectid_59: DD 315
img_inode_objectid_60: DD 316
img_inode_objectid_61: DD 317
img_inode_objectid_62: DD 318
img_inode_objectid_63: DD 319
img_inode_objectid_64: DD 320
img_inode_type: DD 2
img_inode_type_1: DD 2
img_inode_type_2: DD 2
img_inode_type_3: DD 2
img_inode_type_4: DD 2
img_inode_type_5: DD 2
img_inode_type_6: DD 2
img_inode_type_7: DD 2
img_inode_type_8: DD 2
img_inode_type_9: DD 2
img_inode_type_10: DD 2
img_inode_type_11: DD 2
img_inode_type_12: DD 1
img_inode_type_13: DD 1
img_inode_type_14: DD 1
img_inode_type_15: DD 1
img_inode_type_16: DD 1
img_inode_type_17: DD 1
img_inode_type_18: DD 1
img_inode_type_19: DD 1
img_inode_type_20: DD 1
img_inode_type_21: DD 1
img_inode_type_22: DD 1
img_inode_type_23: DD 1
img_inode_type_24: DD 1
img_inode_type_25: DD 1
img_inode_type_26: DD 1
img_inode_type_27: DD 1
img_inode_type_28: DD 1
img_inode_type_29: DD 1
img_inode_type_30: DD 1
img_inode_type_31: DD 1
img_inode_type_32: DD 1
img_inode_type_33: DD 1
img_inode_type_34: DD 1
img_inode_type_35: DD 1
img_inode_type_36: DD 1
img_inode_type_37: DD 1
img_inode_type_38: DD 1
img_inode_type_39: DD 1
img_inode_type_40: DD 1
img_inode_type_41: DD 1
img_inode_type_42: DD 1
img_inode_type_43: DD 1
img_inode_type_44: DD 1
img_inode_type_45: DD 1
img_inode_type_46: DD 1
img_inode_type_47: DD 1
img_inode_type_48: DD 1
img_inode_type_49: DD 1
img_inode_type_50: DD 1
img_inode_type_51: DD 1
img_inode_type_52: DD 1
img_inode_type_53: DD 1
img_inode_type_54: DD 1
img_inode_type_55: DD 1
img_inode_type_56: DD 1
img_inode_type_57: DD 1
img_inode_type_58: DD 1
img_inode_type_59: DD 1
img_inode_type_60: DD 1
img_inode_type_61: DD 1
img_inode_type_62: DD 1
img_inode_type_63: DD 1
img_inode_type_64: DD 1
img_inode_size: DD 8
img_inode_size_1: DD 276
img_inode_size_2: DD 16
img_inode_size_3: DD 184
img_inode_size_4: DD 20
img_inode_size_5: DD 52
img_inode_size_6: DD 18
img_inode_size_7: DD 28
img_inode_size_8: DD 210
img_inode_size_9: DD 576
img_inode_size_10: DD 64
img_inode_size_11: DD 32
img_inode_size_12: DD 3298
img_inode_size_13: DD 3005
img_inode_size_14: DD 4359
img_inode_size_15: DD 3608
img_inode_size_16: DD 4147
img_inode_size_17: DD 8146
img_inode_size_18: DD 15627
img_inode_size_19: DD 30260
img_inode_size_20: DD 16152
img_inode_size_21: DD 1338
img_inode_size_22: DD 12344
img_inode_size_23: DD 2094
img_inode_size_24: DD 1004
img_inode_size_25: DD 297
img_inode_size_26: DD 60252
img_inode_size_27: DD 5280
img_inode_size_28: DD 90184
img_inode_size_29: DD 136383
img_inode_size_30: DD 3671
img_inode_size_31: DD 15711
img_inode_size_32: DD 54540
img_inode_size_33: DD 2785
img_inode_size_34: DD 40556
img_inode_size_35: DD 980
img_inode_size_36: DD 64
img_inode_size_37: DD 4187
img_inode_size_38: DD 200
img_inode_size_39: DD 659
img_inode_size_40: DD 76235
img_inode_size_41: DD 5214
img_inode_size_42: DD 1064
img_inode_size_43: DD 15789
img_inode_size_44: DD 3058
img_inode_size_45: DD 1129
img_inode_size_46: DD 3493
img_inode_size_47: DD 2953
img_inode_size_48: DD 13282
img_inode_size_49: DD 11971
img_inode_size_50: DD 5269
img_inode_size_51: DD 3225
img_inode_size_52: DD 7161
img_inode_size_53: DD 1982
img_inode_size_54: DD 5445
img_inode_size_55: DD 528
img_inode_size_56: DD 424
img_inode_size_57: DD 21804
img_inode_size_58: DD 5264
img_inode_size_59: DD 9683
img_inode_size_60: DD 324
img_inode_size_61: DD 3531
img_inode_size_62: DD 1993
img_inode_size_63: DD 5517
img_inode_size_64: DD 2302

img_dirent_count: DD 64
img_dirent_parent: DD 256
img_dirent_parent_1: DD 257
img_dirent_parent_2: DD 257
img_dirent_parent_3: DD 257
img_dirent_parent_4: DD 257
img_dirent_parent_5: DD 257
img_dirent_parent_6: DD 257
img_dirent_parent_7: DD 257
img_dirent_parent_8: DD 257
img_dirent_parent_9: DD 257
img_dirent_parent_10: DD 257
img_dirent_parent_11: DD 257
img_dirent_parent_12: DD 257
img_dirent_parent_13: DD 257
img_dirent_parent_14: DD 257
img_dirent_parent_15: DD 257
img_dirent_parent_16: DD 257
img_dirent_parent_17: DD 257
img_dirent_parent_18: DD 257
img_dirent_parent_19: DD 258
img_dirent_parent_20: DD 258
img_dirent_parent_21: DD 259
img_dirent_parent_22: DD 259
img_dirent_parent_23: DD 259
img_dirent_parent_24: DD 259
img_dirent_parent_25: DD 259
img_dirent_parent_26: DD 259
img_dirent_parent_27: DD 259
img_dirent_parent_28: DD 259
img_dirent_parent_29: DD 259
img_dirent_parent_30: DD 259
img_dirent_parent_31: DD 260
img_dirent_parent_32: DD 260
img_dirent_parent_33: DD 261
img_dirent_parent_34: DD 261
img_dirent_parent_35: DD 262
img_dirent_parent_36: DD 263
img_dirent_parent_37: DD 264
img_dirent_parent_38: DD 264
img_dirent_parent_39: DD 264
img_dirent_parent_40: DD 264
img_dirent_parent_41: DD 264
img_dirent_parent_42: DD 265
img_dirent_parent_43: DD 265
img_dirent_parent_44: DD 265
img_dirent_parent_45: DD 265
img_dirent_parent_46: DD 265
img_dirent_parent_47: DD 265
img_dirent_parent_48: DD 265
img_dirent_parent_49: DD 265
img_dirent_parent_50: DD 265
img_dirent_parent_51: DD 265
img_dirent_parent_52: DD 265
img_dirent_parent_53: DD 265
img_dirent_parent_54: DD 265
img_dirent_parent_55: DD 265
img_dirent_parent_56: DD 265
img_dirent_parent_57: DD 265
img_dirent_parent_58: DD 266
img_dirent_parent_59: DD 266
img_dirent_parent_60: DD 266
img_dirent_parent_61: DD 266
img_dirent_parent_62: DD 267
img_dirent_parent_63: DD 267
img_dirent_inode: DD 257
img_dirent_inode_1: DD 270
img_dirent_inode_2: DD 274
img_dirent_inode_3: DD 265
img_dirent_inode_4: DD 268
img_dirent_inode_5: DD 262
img_dirent_inode_6: DD 267
img_dirent_inode_7: DD 258
img_dirent_inode_8: DD 272
img_dirent_inode_9: DD 264
img_dirent_inode_10: DD 259
img_dirent_inode_11: DD 273
img_dirent_inode_12: DD 275
img_dirent_inode_13: DD 260
img_dirent_inode_14: DD 263
img_dirent_inode_15: DD 271
img_dirent_inode_16: DD 261
img_dirent_inode_17: DD 269
img_dirent_inode_18: DD 266
img_dirent_inode_19: DD 277
img_dirent_inode_20: DD 276
img_dirent_inode_21: DD 285
img_dirent_inode_22: DD 282
img_dirent_inode_23: DD 278
img_dirent_inode_24: DD 283
img_dirent_inode_25: DD 281
img_dirent_inode_26: DD 286
img_dirent_inode_27: DD 284
img_dirent_inode_28: DD 287
img_dirent_inode_29: DD 279
img_dirent_inode_30: DD 280
img_dirent_inode_31: DD 289
img_dirent_inode_32: DD 288
img_dirent_inode_33: DD 290
img_dirent_inode_34: DD 291
img_dirent_inode_35: DD 292
img_dirent_inode_36: DD 293
img_dirent_inode_37: DD 296
img_dirent_inode_38: DD 298
img_dirent_inode_39: DD 295
img_dirent_inode_40: DD 297
img_dirent_inode_41: DD 294
img_dirent_inode_42: DD 314
img_dirent_inode_43: DD 313
img_dirent_inode_44: DD 300
img_dirent_inode_45: DD 299
img_dirent_inode_46: DD 302
img_dirent_inode_47: DD 306
img_dirent_inode_48: DD 304
img_dirent_inode_49: DD 303
img_dirent_inode_50: DD 307
img_dirent_inode_51: DD 305
img_dirent_inode_52: DD 310
img_dirent_inode_53: DD 309
img_dirent_inode_54: DD 308
img_dirent_inode_55: DD 301
img_dirent_inode_56: DD 311
img_dirent_inode_57: DD 312
img_dirent_inode_58: DD 315
img_dirent_inode_59: DD 318
img_dirent_inode_60: DD 316
img_dirent_inode_61: DD 317
img_dirent_inode_62: DD 320
img_dirent_inode_63: DD 319
img_dirent_type: DD 2
img_dirent_type_1: DD 1
img_dirent_type_2: DD 1
img_dirent_type_3: DD 2
img_dirent_type_4: DD 1
img_dirent_type_5: DD 2
img_dirent_type_6: DD 2
img_dirent_type_7: DD 2
img_dirent_type_8: DD 1
img_dirent_type_9: DD 2
img_dirent_type_10: DD 2
img_dirent_type_11: DD 1
img_dirent_type_12: DD 1
img_dirent_type_13: DD 2
img_dirent_type_14: DD 2
img_dirent_type_15: DD 1
img_dirent_type_16: DD 2
img_dirent_type_17: DD 1
img_dirent_type_18: DD 2
img_dirent_type_19: DD 1
img_dirent_type_20: DD 1
img_dirent_type_21: DD 1
img_dirent_type_22: DD 1
img_dirent_type_23: DD 1
img_dirent_type_24: DD 1
img_dirent_type_25: DD 1
img_dirent_type_26: DD 1
img_dirent_type_27: DD 1
img_dirent_type_28: DD 1
img_dirent_type_29: DD 1
img_dirent_type_30: DD 1
img_dirent_type_31: DD 1
img_dirent_type_32: DD 1
img_dirent_type_33: DD 1
img_dirent_type_34: DD 1
img_dirent_type_35: DD 1
img_dirent_type_36: DD 1
img_dirent_type_37: DD 1
img_dirent_type_38: DD 1
img_dirent_type_39: DD 1
img_dirent_type_40: DD 1
img_dirent_type_41: DD 1
img_dirent_type_42: DD 1
img_dirent_type_43: DD 1
img_dirent_type_44: DD 1
img_dirent_type_45: DD 1
img_dirent_type_46: DD 1
img_dirent_type_47: DD 1
img_dirent_type_48: DD 1
img_dirent_type_49: DD 1
img_dirent_type_50: DD 1
img_dirent_type_51: DD 1
img_dirent_type_52: DD 1
img_dirent_type_53: DD 1
img_dirent_type_54: DD 1
img_dirent_type_55: DD 1
img_dirent_type_56: DD 1
img_dirent_type_57: DD 1
img_dirent_type_58: DD 1
img_dirent_type_59: DD 1
img_dirent_type_60: DD 1
img_dirent_type_61: DD 1
img_dirent_type_62: DD 1
img_dirent_type_63: DD 1
img_dirent_name_id: DD 0
img_dirent_name_id_1: DD 1
img_dirent_name_id_2: DD 2
img_dirent_name_id_3: DD 3
img_dirent_name_id_4: DD 4
img_dirent_name_id_5: DD 5
img_dirent_name_id_6: DD 6
img_dirent_name_id_7: DD 7
img_dirent_name_id_8: DD 8
img_dirent_name_id_9: DD 9
img_dirent_name_id_10: DD 10
img_dirent_name_id_11: DD 11
img_dirent_name_id_12: DD 12
img_dirent_name_id_13: DD 13
img_dirent_name_id_14: DD 14
img_dirent_name_id_15: DD 15
img_dirent_name_id_16: DD 16
img_dirent_name_id_17: DD 17
img_dirent_name_id_18: DD 18
img_dirent_name_id_19: DD 19
img_dirent_name_id_20: DD 20
img_dirent_name_id_21: DD 21
img_dirent_name_id_22: DD 22
img_dirent_name_id_23: DD 23
img_dirent_name_id_24: DD 24
img_dirent_name_id_25: DD 25
img_dirent_name_id_26: DD 26
img_dirent_name_id_27: DD 27
img_dirent_name_id_28: DD 28
img_dirent_name_id_29: DD 29
img_dirent_name_id_30: DD 30
img_dirent_name_id_31: DD 31
img_dirent_name_id_32: DD 32
img_dirent_name_id_33: DD 33
img_dirent_name_id_34: DD 34
img_dirent_name_id_35: DD 35
img_dirent_name_id_36: DD 36
img_dirent_name_id_37: DD 37
img_dirent_name_id_38: DD 38
img_dirent_name_id_39: DD 39
img_dirent_name_id_40: DD 40
img_dirent_name_id_41: DD 41
img_dirent_name_id_42: DD 42
img_dirent_name_id_43: DD 43
img_dirent_name_id_44: DD 44
img_dirent_name_id_45: DD 45
img_dirent_name_id_46: DD 46
img_dirent_name_id_47: DD 47
img_dirent_name_id_48: DD 48
img_dirent_name_id_49: DD 49
img_dirent_name_id_50: DD 50
img_dirent_name_id_51: DD 51
img_dirent_name_id_52: DD 52
img_dirent_name_id_53: DD 53
img_dirent_name_id_54: DD 54
img_dirent_name_id_55: DD 55
img_dirent_name_id_56: DD 56
img_dirent_name_id_57: DD 57
img_dirent_name_id_58: DD 58
img_dirent_name_id_59: DD 59
img_dirent_name_id_60: DD 60
img_dirent_name_id_61: DD 61
img_dirent_name_id_62: DD 62
img_dirent_name_id_63: DD 63

img_extent_count: DD 53
img_extent_inode: DD 268
img_extent_inode_1: DD 269
img_extent_inode_2: DD 270
img_extent_inode_3: DD 271
img_extent_inode_4: DD 272
img_extent_inode_5: DD 273
img_extent_inode_6: DD 274
img_extent_inode_7: DD 275
img_extent_inode_8: DD 276
img_extent_inode_9: DD 277
img_extent_inode_10: DD 278
img_extent_inode_11: DD 279
img_extent_inode_12: DD 280
img_extent_inode_13: DD 281
img_extent_inode_14: DD 282
img_extent_inode_15: DD 283
img_extent_inode_16: DD 284
img_extent_inode_17: DD 285
img_extent_inode_18: DD 286
img_extent_inode_19: DD 287
img_extent_inode_20: DD 288
img_extent_inode_21: DD 289
img_extent_inode_22: DD 290
img_extent_inode_23: DD 291
img_extent_inode_24: DD 292
img_extent_inode_25: DD 293
img_extent_inode_26: DD 294
img_extent_inode_27: DD 295
img_extent_inode_28: DD 296
img_extent_inode_29: DD 297
img_extent_inode_30: DD 298
img_extent_inode_31: DD 299
img_extent_inode_32: DD 300
img_extent_inode_33: DD 301
img_extent_inode_34: DD 302
img_extent_inode_35: DD 303
img_extent_inode_36: DD 304
img_extent_inode_37: DD 305
img_extent_inode_38: DD 306
img_extent_inode_39: DD 307
img_extent_inode_40: DD 308
img_extent_inode_41: DD 309
img_extent_inode_42: DD 310
img_extent_inode_43: DD 311
img_extent_inode_44: DD 312
img_extent_inode_45: DD 313
img_extent_inode_46: DD 314
img_extent_inode_47: DD 315
img_extent_inode_48: DD 316
img_extent_inode_49: DD 317
img_extent_inode_50: DD 318
img_extent_inode_51: DD 319
img_extent_inode_52: DD 320
img_extent_block_off: DD 13631488
img_extent_block_off_1: DD 13635584
img_extent_block_off_2: DD 13639680
img_extent_block_off_3: DD 13647872
img_extent_block_off_4: DD 13651968
img_extent_block_off_5: DD 13660160
img_extent_block_off_6: DD 13668352
img_extent_block_off_7: DD 13684736
img_extent_block_off_8: DD 13717504
img_extent_block_off_9: DD 39121212
img_extent_block_off_10: DD 13733888
img_extent_block_off_11: DD 13750272
img_extent_block_off_12: DD 39119550
img_extent_block_off_13: DD 39119051
img_extent_block_off_14: DD 13754368
img_extent_block_off_15: DD 13815808
img_extent_block_off_16: DD 13824000
img_extent_block_off_17: DD 105906176
img_extent_block_off_18: DD 13918208
img_extent_block_off_19: DD 13922304
img_extent_block_off_20: DD 13938688
img_extent_block_off_21: DD 13996032
img_extent_block_off_22: DD 14000128
img_extent_block_off_23: DD 39115777
img_extent_block_off_24: DD 39115513
img_extent_block_off_25: DD 14041088
img_extent_block_off_26: DD 39114856
img_extent_block_off_27: DD 39113984
img_extent_block_off_28: DD 14049280
img_extent_block_off_29: DD 14127104
img_extent_block_off_30: DD 39156458
img_extent_block_off_31: DD 14135296
img_extent_block_off_32: DD 14151680
img_extent_block_off_33: DD 39154635
img_extent_block_off_34: DD 14155776
img_extent_block_off_35: DD 14159872
img_extent_block_off_36: DD 14163968
img_extent_block_off_37: DD 14180352
img_extent_block_off_38: DD 14192640
img_extent_block_off_39: DD 14200832
img_extent_block_off_40: DD 14204928
img_extent_block_off_41: DD 39150739
img_extent_block_off_42: DD 14213120
img_extent_block_off_43: DD 39149763
img_extent_block_off_44: DD 39149133
img_extent_block_off_45: DD 14221312
img_extent_block_off_46: DD 14245888
img_extent_block_off_47: DD 14254080
img_extent_block_off_48: DD 39147909
img_extent_block_off_49: DD 14266368
img_extent_block_off_50: DD 39145490
img_extent_block_off_51: DD 14270464
img_extent_block_off_52: DD 14278656
img_extent_size: DD 4096
img_extent_size_1: DD 4096
img_extent_size_2: DD 8192
img_extent_size_3: DD 4096
img_extent_size_4: DD 8192
img_extent_size_5: DD 8192
img_extent_size_6: DD 16384
img_extent_size_7: DD 32768
img_extent_size_8: DD 16384
img_extent_size_9: DD 1338
img_extent_size_10: DD 16384
img_extent_size_11: DD 4096
img_extent_size_12: DD 1004
img_extent_size_13: DD 297
img_extent_size_14: DD 61440
img_extent_size_15: DD 8192
img_extent_size_16: DD 94208
img_extent_size_17: DD 139264
img_extent_size_18: DD 4096
img_extent_size_19: DD 16384
img_extent_size_20: DD 57344
img_extent_size_21: DD 4096
img_extent_size_22: DD 40960
img_extent_size_23: DD 980
img_extent_size_24: DD 64
img_extent_size_25: DD 8192
img_extent_size_26: DD 200
img_extent_size_27: DD 659
img_extent_size_28: DD 77824
img_extent_size_29: DD 8192
img_extent_size_30: DD 1064
img_extent_size_31: DD 16384
img_extent_size_32: DD 4096
img_extent_size_33: DD 1129
img_extent_size_34: DD 4096
img_extent_size_35: DD 4096
img_extent_size_36: DD 16384
img_extent_size_37: DD 12288
img_extent_size_38: DD 8192
img_extent_size_39: DD 4096
img_extent_size_40: DD 8192
img_extent_size_41: DD 1982
img_extent_size_42: DD 8192
img_extent_size_43: DD 528
img_extent_size_44: DD 424
img_extent_size_45: DD 24576
img_extent_size_46: DD 8192
img_extent_size_47: DD 12288
img_extent_size_48: DD 324
img_extent_size_49: DD 4096
img_extent_size_50: DD 1993
img_extent_size_51: DD 8192
img_extent_size_52: DD 4096

img_name_count: DD 64
img_name_offset: DD 0
img_name_offset_1: DD 4
img_name_offset_2: DD 17
img_name_offset_3: DD 26
img_name_offset_4: DD 31
img_name_offset_5: DD 39
img_name_offset_6: DD 43
img_name_offset_7: DD 45
img_name_offset_8: DD 53
img_name_offset_9: DD 74
img_name_offset_10: DD 79
img_name_offset_11: DD 82
img_name_offset_12: DD 88
img_name_offset_13: DD 104
img_name_offset_14: DD 107
img_name_offset_15: DD 111
img_name_offset_16: DD 122
img_name_offset_17: DD 129
img_name_offset_18: DD 138
img_name_offset_19: DD 142
img_name_offset_20: DD 146
img_name_offset_21: DD 150
img_name_offset_22: DD 162
img_name_offset_23: DD 170
img_name_offset_24: DD 175
img_name_offset_25: DD 182
img_name_offset_26: DD 193
img_name_offset_27: DD 205
img_name_offset_28: DD 218
img_name_offset_29: DD 226
img_name_offset_30: DD 231
img_name_offset_31: DD 242
img_name_offset_32: DD 247
img_name_offset_33: DD 252
img_name_offset_34: DD 265
img_name_offset_35: DD 278
img_name_offset_36: DD 287
img_name_offset_37: DD 301
img_name_offset_38: DD 319
img_name_offset_39: DD 334
img_name_offset_40: DD 356
img_name_offset_41: DD 377
img_name_offset_42: DD 406
img_name_offset_43: DD 421
img_name_offset_44: DD 426
img_name_offset_45: DD 451
img_name_offset_46: DD 457
img_name_offset_47: DD 483
img_name_offset_48: DD 505
img_name_offset_49: DD 523
img_name_offset_50: DD 549
img_name_offset_51: DD 563
img_name_offset_52: DD 583
img_name_offset_53: DD 608
img_name_offset_54: DD 631
img_name_offset_55: DD 644
img_name_offset_56: DD 670
img_name_offset_57: DD 679
img_name_offset_58: DD 694
img_name_offset_59: DD 704
img_name_offset_60: DD 710
img_name_offset_61: DD 720
img_name_offset_62: DD 726
img_name_offset_63: DD 733
img_name_len: DD 4
img_name_len_1: DD 13
img_name_len_2: DD 9
img_name_len_3: DD 5
img_name_len_4: DD 8
img_name_len_5: DD 4
img_name_len_6: DD 2
img_name_len_7: DD 8
img_name_len_8: DD 21
img_name_len_9: DD 5
img_name_len_10: DD 3
img_name_len_11: DD 6
img_name_len_12: DD 16
img_name_len_13: DD 3
img_name_len_14: DD 4
img_name_len_15: DD 11
img_name_len_16: DD 7
img_name_len_17: DD 9
img_name_len_18: DD 4
img_name_len_19: DD 4
img_name_len_20: DD 4
img_name_len_21: DD 12
img_name_len_22: DD 8
img_name_len_23: DD 5
img_name_len_24: DD 7
img_name_len_25: DD 11
img_name_len_26: DD 12
img_name_len_27: DD 13
img_name_len_28: DD 8
img_name_len_29: DD 5
img_name_len_30: DD 11
img_name_len_31: DD 5
img_name_len_32: DD 5
img_name_len_33: DD 13
img_name_len_34: DD 13
img_name_len_35: DD 9
img_name_len_36: DD 14
img_name_len_37: DD 18
img_name_len_38: DD 15
img_name_len_39: DD 22
img_name_len_40: DD 21
img_name_len_41: DD 29
img_name_len_42: DD 15
img_name_len_43: DD 5
img_name_len_44: DD 25
img_name_len_45: DD 6
img_name_len_46: DD 26
img_name_len_47: DD 22
img_name_len_48: DD 18
img_name_len_49: DD 26
img_name_len_50: DD 14
img_name_len_51: DD 20
img_name_len_52: DD 25
img_name_len_53: DD 23
img_name_len_54: DD 13
img_name_len_55: DD 26
img_name_len_56: DD 9
img_name_len_57: DD 15
img_name_len_58: DD 10
img_name_len_59: DD 6
img_name_len_60: DD 10
img_name_len_61: DD 6
img_name_len_62: DD 7
img_name_len_63: DD 9
img_name_pool: DB "SPO8Validation.mdreport.mdtoolsMakefiledemovmanalysisdevices_filezilla.xmltestsastmain.cspo8.target.pdslcfgdocsdevices.xmlcodegenREADME.mdviewir.hir.cparser.tab.clex.yy.cast.clexer.last_maker.hparser.tab.hparser.outputparser.yast.hast_maker.ccfg.hcfg.clinear_code.clinear_code.hsmall.txtbtrfs_image.mdbtrfs_ftp_demo.asmtimer_probe.asmbtrfs_ftp_commands.txtbtrfs_unsupported.asmbtrfs_ftp_commands.remote.txtvm_inspector.pyvm.pycheck_btrfs_ftp_output.pyasm.pycheck_remote_ftp_client.shprepare_btrfs_image.shftp_data_adapter.ccheck_remote_ftp_report.shrun_remote.batgen_btrfs_ftp_asm.pyrun_remote_interactive.shrun_remote_filezilla.shrun_remote.shcheck_btrfs_unsupported.pyrun_vm.shrun_vm_tests.shcfg_dgml.cdgml.hcfg_dgml.hdgml.cspec.mdspec.json"
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
  ; Новое управляющее FTP-соединение начинается из корня.
  ; Это держит семантику FTP внутри VM, а внешний адаптер остаётся
  ; только мостом TCP <-> SimplePipe.
  LOAD img_root_inode
  STORE v_current_dir
  CALL pwd_set_root, 0
  POP
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

; pwd_rebuild_for_inode(inode) — восстанавливает текстовый PWD по inode
; каталога. Идём от каталога к корню через DIR_ITEM, складываем name_id
; в стек v_copy_queue, затем печатаем имена в обратном порядке.
pwd_rebuild_for_inode:
  STORE v_path_inode
  ENTER 0
  LOAD v_path_inode
  LOAD img_root_inode
  EQ
  JZ pwd_rebuild_collect
  CALL pwd_set_root, 0
  POP
  PUSH_CONST k0
  LEAVE
  RETF

pwd_rebuild_collect:
  PUSH_CONST k0
  STORE v_copy_tail

pwd_rebuild_collect_loop:
  LOAD v_path_inode
  LOAD img_root_inode
  EQ
  JZ pwd_rebuild_find_parent
  JMP pwd_rebuild_emit

pwd_rebuild_find_parent:
  PUSH_CONST k0
  STORE v_scan_i
pwd_rebuild_scan_loop:
  LOAD v_scan_i
  LOAD img_dirent_count
  LT
  JZ pwd_rebuild_fallback_root

  PUSH_ADDR img_dirent_inode
  LOAD v_scan_i
  INDEX
  LOAD_IND
  LOAD v_path_inode
  EQ
  JZ pwd_rebuild_scan_next

  PUSH_ADDR img_dirent_type
  LOAD v_scan_i
  INDEX
  LOAD_IND
  PUSH_CONST k_btrfs_ft_dir
  EQ
  JZ pwd_rebuild_scan_next

  PUSH_ADDR img_dirent_name_id
  LOAD v_scan_i
  INDEX
  LOAD_IND
  STORE v_name_id
  PUSH_ADDR v_copy_queue
  LOAD v_copy_tail
  INDEX
  LOAD v_name_id
  STORE_IND
  LOAD v_copy_tail
  PUSH_CONST k1
  ADD
  STORE v_copy_tail

  PUSH_ADDR img_dirent_parent
  LOAD v_scan_i
  INDEX
  LOAD_IND
  STORE v_path_inode
  JMP pwd_rebuild_collect_loop

pwd_rebuild_scan_next:
  LOAD v_scan_i
  PUSH_CONST k1
  ADD
  STORE v_scan_i
  JMP pwd_rebuild_scan_loop

pwd_rebuild_fallback_root:
  CALL pwd_set_root, 0
  POP
  PUSH_CONST k0
  LEAVE
  RETF

pwd_rebuild_emit:
  CALL pwd_set_root, 0
  POP
pwd_rebuild_emit_loop:
  LOAD v_copy_tail
  PUSH_CONST k0
  GT
  JZ pwd_rebuild_done
  LOAD v_copy_tail
  PUSH_CONST k1
  SUB
  STORE v_copy_tail
  PUSH_ADDR v_copy_queue
  LOAD v_copy_tail
  INDEX
  LOAD_IND
  CALL pwd_append_name, 1
  POP
  JMP pwd_rebuild_emit_loop

pwd_rebuild_done:
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; cmd_cwd — изменяет текущий каталог.
; Аргумент может быть относительным или абсолютным путём с несколькими
; компонентами. Поиск выполняется сканированием записей Btrfs DIR_ITEM.
; =====================================================================
cmd_cwd:
  ENTER 0
  LOAD v_lookup_count
  PUSH_CONST k1
  ADD
  STORE v_lookup_count

  CALL fs_resolve_arg_path, 0
  JZ cmd_cwd_missing
  LOAD v_found_type
  PUSH_CONST k_btrfs_ft_dir
  EQ
  JZ cmd_cwd_missing
  LOAD v_found_inode
  STORE v_current_dir
  LOAD v_current_dir
  CALL pwd_rebuild_for_inode, 1
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
  LOAD v_current_dir
  STORE v_find_parent
  LOAD v_arg_off
  PUSH_CONST k0
  EQ
  JZ cmd_list_resolve_arg
  JMP cmd_list_start_output

cmd_list_resolve_arg:
  CALL fs_resolve_arg_path, 0
  JZ cmd_list_missing
  LOAD v_found_type
  PUSH_CONST k_btrfs_ft_dir
  EQ
  JZ cmd_list_missing
  LOAD v_found_inode
  STORE v_find_parent

cmd_list_start_output:
  PUSH_ADDR s_150_list
  CALL emit_ztext, 1
  POP
  PUSH_CONST k1
  STORE v_sink

  ; Сканируем DIR_ITEM дерева FS: parent == v_find_parent.
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
  LOAD v_find_parent
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
  CALL data_stream_close, 0
  POP
  PUSH_CONST k0
  STORE v_sink
  PUSH_ADDR s_226
  CALL emit_ztext, 1
  POP
  PUSH_CONST k0
  LEAVE
  RETF

cmd_list_missing:
  PUSH_ADDR s_550
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
  LOAD v_current_dir
  STORE v_find_parent
  LOAD v_arg_off
  PUSH_CONST k0
  EQ
  JZ cmd_nlst_resolve_arg
  JMP cmd_nlst_start_output

cmd_nlst_resolve_arg:
  CALL fs_resolve_arg_path, 0
  JZ cmd_nlst_missing
  LOAD v_found_type
  PUSH_CONST k_btrfs_ft_dir
  EQ
  JZ cmd_nlst_missing
  LOAD v_found_inode
  STORE v_find_parent

cmd_nlst_start_output:
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
  LOAD v_find_parent
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
  CALL data_stream_close, 0
  POP
  PUSH_CONST k0
  STORE v_sink
  PUSH_ADDR s_226
  CALL emit_ztext, 1
  POP
  PUSH_CONST k0
  LEAVE
  RETF

cmd_nlst_missing:
  PUSH_ADDR s_550
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

  CALL fs_resolve_arg_path, 0
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
  CALL fs_resolve_arg_path, 0
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
  CALL fs_resolve_arg_path, 0
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
  CALL data_stream_close, 0
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

  CALL fs_resolve_arg_path, 0
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
; path_at_term — возвращает 1, если v_arg_cmp_off указывает на конец
; FTP-аргумента: NUL, пробел, CR или LF.
; =====================================================================
path_at_term:
  ENTER 0
  PUSH_ADDR v_cmd_buf
  LOAD v_arg_cmp_off
  INDEXB
  LOADB_IND
  STORE v_eq_ca
  LOAD v_eq_ca
  PUSH_CONST k0
  EQ
  JZ path_at_term_space
  PUSH_CONST k1
  LEAVE
  RETF
path_at_term_space:
  LOAD v_eq_ca
  PUSH_CONST k32
  EQ
  JZ path_at_term_cr
  PUSH_CONST k1
  LEAVE
  RETF
path_at_term_cr:
  LOAD v_eq_ca
  PUSH_CONST k13
  EQ
  JZ path_at_term_lf
  PUSH_CONST k1
  LEAVE
  RETF
path_at_term_lf:
  LOAD v_eq_ca
  PUSH_CONST k10
  EQ
  JZ path_at_term_false
  PUSH_CONST k1
  LEAVE
  RETF
path_at_term_false:
  PUSH_CONST k0
  LEAVE
  RETF

; path_skip_slashes — пропускает один или несколько '/' в v_arg_cmp_off.
path_skip_slashes:
  ENTER 0
path_skip_slashes_loop:
  PUSH_ADDR v_cmd_buf
  LOAD v_arg_cmp_off
  INDEXB
  LOADB_IND
  PUSH_CONST c_slash
  EQ
  JZ path_skip_slashes_done
  LOAD v_arg_cmp_off
  PUSH_CONST k1
  ADD
  STORE v_arg_cmp_off
  JMP path_skip_slashes_loop
path_skip_slashes_done:
  PUSH_CONST k0
  LEAVE
  RETF

; path_prepare_next — переносит v_arg_cmp_off на следующий компонент пути.
; Вход: v_path_next указывает на байт после текущего компонента.
; Выход: v_path_has_more = 1, если дальше есть ещё компонент.
path_prepare_next:
  ENTER 0
  LOAD v_path_next
  STORE v_arg_cmp_off
  CALL path_skip_slashes, 0
  POP
  CALL path_at_term, 0
  JZ path_prepare_more
  PUSH_CONST k0
  STORE v_path_has_more
  PUSH_CONST k0
  LEAVE
  RETF
path_prepare_more:
  PUSH_CONST k1
  STORE v_path_has_more
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; arg_component_eq(target_addr) — сравнивает текущий компонент пути
; в v_cmd_buf[v_arg_cmp_off] с NUL-терминированной строкой target.
; Компонент завершается '/', NUL, пробелом, CR или LF.
; =====================================================================
arg_component_eq:
  STORE v_eq_b
  ENTER 0
  PUSH_CONST k0
  STORE v_eq_i

arg_component_eq_loop:
  LOAD v_eq_b
  LOAD v_eq_i
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
  LOAD v_eq_cb
  PUSH_CONST k0
  EQ
  JZ arg_component_eq_compare

  LOAD v_eq_ca
  PUSH_CONST c_slash
  EQ
  JZ arg_component_eq_check_term
  PUSH_CONST k1
  LEAVE
  RETF
arg_component_eq_check_term:
  LOAD v_arg_cmp_off
  LOAD v_eq_i
  ADD
  STORE v_path_next
  LOAD v_path_next
  STORE v_arg_cmp_off
  CALL path_at_term, 0
  STORE v_path_has_more
  LOAD v_path_next
  LOAD v_eq_i
  SUB
  STORE v_arg_cmp_off
  LOAD v_path_has_more
  JZ arg_component_eq_false
  PUSH_CONST k1
  LEAVE
  RETF

arg_component_eq_compare:
  LOAD v_eq_ca
  LOAD v_eq_cb
  EQ
  JZ arg_component_eq_false
  LOAD v_eq_i
  PUSH_CONST k1
  ADD
  STORE v_eq_i
  JMP arg_component_eq_loop

arg_component_eq_false:
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; fs_find_dirent_in_parent_by_component — ищет DIR_ITEM в каталоге
; v_find_parent по текущему компоненту пути v_arg_cmp_off.
; =====================================================================
fs_find_dirent_in_parent_by_component:
  ENTER 0
  PUSH_CONST k0
  STORE v_scan_i

fs_find_dirent_component_loop:
  LOAD v_scan_i
  LOAD img_dirent_count
  LT
  JZ fs_find_dirent_component_missing

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
  CALL fs_arg_component_eq_name, 1
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
  JMP fs_find_dirent_component_loop

fs_find_dirent_component_missing:
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; fs_resolve_arg_path — разрешает аргумент FTP-команды как путь.
; Поддерживает абсолютные и относительные пути, '.', '..' и несколько
; компонентов. При успехе заполняет v_found_inode/v_found_type/v_name_id.
; =====================================================================
fs_resolve_arg_path:
  ENTER 0
  LOAD v_arg_off
  PUSH_CONST k0
  EQ
  JZ fs_resolve_prepare
  PUSH_CONST k0
  LEAVE
  RETF

fs_resolve_prepare:
  PUSH_CONST k0
  STORE v_arg_absolute
  LOAD v_current_dir
  STORE v_find_parent
  LOAD v_arg_off
  STORE v_arg_cmp_off

  PUSH_ADDR v_cmd_buf
  LOAD v_arg_cmp_off
  INDEXB
  LOADB_IND
  PUSH_CONST c_slash
  EQ
  JZ fs_resolve_after_root
  PUSH_CONST k1
  STORE v_arg_absolute
  LOAD img_root_inode
  STORE v_find_parent
  CALL path_skip_slashes, 0
  POP

fs_resolve_after_root:
  CALL path_at_term, 0
  JZ fs_resolve_loop
  LOAD v_find_parent
  STORE v_found_inode
  PUSH_CONST k_btrfs_ft_dir
  STORE v_found_type
  PUSH_CONST k1
  LEAVE
  RETF

fs_resolve_loop:
  PUSH_ADDR p_dot
  CALL arg_component_eq, 1
  JZ fs_resolve_check_dotdot
  LOAD v_arg_cmp_off
  PUSH_CONST k1
  ADD
  STORE v_path_next
  CALL path_prepare_next, 0
  POP
  LOAD v_path_has_more
  JZ fs_resolve_return_parent
  JMP fs_resolve_loop

fs_resolve_check_dotdot:
  PUSH_ADDR p_dotdot
  CALL arg_component_eq, 1
  JZ fs_resolve_lookup_component
  LOAD v_find_parent
  CALL fs_parent_of_inode, 1
  STORE v_find_parent
  LOAD v_arg_cmp_off
  PUSH_CONST k2
  ADD
  STORE v_path_next
  CALL path_prepare_next, 0
  POP
  LOAD v_path_has_more
  JZ fs_resolve_return_parent
  JMP fs_resolve_loop

fs_resolve_lookup_component:
  CALL fs_find_dirent_in_parent_by_component, 0
  JZ fs_resolve_missing
  LOAD v_arg_cmp_off
  LOAD v_name_len
  ADD
  STORE v_path_next
  CALL path_prepare_next, 0
  POP
  LOAD v_path_has_more
  JZ fs_resolve_done

  LOAD v_found_type
  PUSH_CONST k_btrfs_ft_dir
  EQ
  JZ fs_resolve_missing
  LOAD v_found_inode
  STORE v_find_parent
  JMP fs_resolve_loop

fs_resolve_return_parent:
  LOAD v_find_parent
  STORE v_found_inode
  PUSH_CONST k_btrfs_ft_dir
  STORE v_found_type
  PUSH_CONST k1
  LEAVE
  RETF

fs_resolve_done:
  PUSH_CONST k1
  LEAVE
  RETF

fs_resolve_missing:
  PUSH_CONST k0
  LEAVE
  RETF

; =====================================================================
; fs_parent_of_current — совместимая обёртка над fs_parent_of_inode.
; =====================================================================
fs_parent_of_current:
  ENTER 0
  LOAD v_current_dir
  CALL fs_parent_of_inode, 1
  LEAVE
  RETF

; fs_parent_of_inode(inode) — находит родительский каталог inode
; по DIR_ITEM с типом BTRFS_FT_DIR. Для корня возвращает корень.
fs_parent_of_inode:
  STORE v_path_inode
  ENTER 0
  LOAD v_path_inode
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
  LOAD v_path_inode
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
; fs_arg_component_eq_name(name_id) — сравнивает текущий компонент пути
; v_arg_cmp_off с именем DIR_ITEM. После имени допускается '/', NUL,
; пробел, CR или LF.
; =====================================================================
fs_arg_component_eq_name:
  STORE v_name_id
  ENTER 0
  LOAD v_name_id
  CALL name_load_info, 1
  POP
  PUSH_CONST k0
  STORE v_eq_i

fs_arg_component_name_loop:
  LOAD v_eq_i
  LOAD v_name_len
  LT
  JZ fs_arg_component_name_check_end
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
  JZ fs_arg_component_name_false
  LOAD v_eq_i
  PUSH_CONST k1
  ADD
  STORE v_eq_i
  JMP fs_arg_component_name_loop

fs_arg_component_name_check_end:
  PUSH_ADDR v_cmd_buf
  LOAD v_arg_cmp_off
  LOAD v_name_len
  ADD
  INDEXB
  LOADB_IND
  STORE v_eq_ca
  LOAD v_eq_ca
  PUSH_CONST c_slash
  EQ
  JZ fs_arg_component_name_check_term
  PUSH_CONST k1
  LEAVE
  RETF
fs_arg_component_name_check_term:
  LOAD v_arg_cmp_off
  LOAD v_name_len
  ADD
  STORE v_path_next
  LOAD v_path_next
  STORE v_arg_cmp_off
  CALL path_at_term, 0
  STORE v_path_has_more
  LOAD v_path_next
  LOAD v_name_len
  SUB
  STORE v_arg_cmp_off
  LOAD v_path_has_more
  JZ fs_arg_component_name_false
  PUSH_CONST k1
  LEAVE
  RETF

fs_arg_component_name_false:
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
; data_stream_write_byte(byte) / data_stream_flush() / data_stream_close()
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

data_stream_close:
  ENTER 0
  CALL data_stream_flush, 0
  POP
  PUSH_CONST k0
  LEAVE
  RETF
