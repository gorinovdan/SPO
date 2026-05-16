# SPO8 Btrfs Test Image

Тестовый образ хранится в [tests/btrfs_ftp_demo.asm](../tests/btrfs_ftp_demo.asm) в секции `data_mem` и инспектируется VM-программой через байтовые операции `INDEXB / LOADB_IND / STOREB_IND` (расширения [spo8.target.pdsl](../spo8.target.pdsl)).

Образ сделан компактным, но не сценарным: команды `LIST`, `CWD` и `RETR` сканируют записи FS-tree leaf, а не выбирают заранее прошитые ответы. Источник: [Btrfs On-disk Format](https://btrfs.wiki.kernel.org/index.php/On-disk_Format), [Btrfs Data Structures](https://btrfs.wiki.kernel.org/index.php/Data_Structures).

## Реальный Btrfs vs тестовый образ

В реальном Btrfs `superblock` находится по фиксированному смещению `0x10000` от начала тома. Поле magic — по offset `0x40` относительно начала superblock и хранит ASCII `_BHRfS_M`. Superblock также описывает дерево корней (`root_tree_logical`), дерево чанков (`chunk_tree_logical`), `nodesize`, `root_dir_objectid`, контрольные суммы и UUID.

Дерево корней содержит `ROOT_ITEM` записи, по которым можно найти FS tree (дерево файловой системы), дерево extent-аллокаций и т.п. FS tree состоит из `INODE_ITEM`, `INODE_REF`, `DIR_ITEM`, `DIR_INDEX` и `EXTENT_DATA` записей в B+-дереве (узлы `BTRFS_HEADER` + `KEY (objectid, type, offset)`).

Тестовый образ содержит поля Btrfs, которые нужны для команд `LIST`/`RETR`/`CWD`:

- superblock (magic, root_dir_objectid, nodesize, root_tree_logical, chunk_tree_logical, fs_tree_objectid, fs_tree_leaf_logical);
- ссылки на FS tree;
- inode-номера файлов и директорий (`INODE_ITEM`);
- directory items (`DIR_ITEM`) с парами «имя → inode»;
- inline-extent данные (`EXTENT_DATA` тип 0).

Намеренно опущены: чексуммы, UUID, RAID-профили, chunk mapping, дерево квот, snapshot’ы. Они не нужны для чтения inline-extent в одном leaf и существенно усложнили бы образ без улучшения демонстрации.

В ASM эти структуры представлены параллельными таблицами:

- `img_dirent_*` — compact `DIR_ITEM` records: parent objectid, target inode, file type, name id;
- `img_inode_*` — compact `INODE_ITEM` records: objectid, type, size;
- `img_extent_*` — compact `EXTENT_DATA` records: inode, extent type, payload id.

## Superblock

| Поле | Значение в образе | Тип в реальном Btrfs |
|---|---|---|
| `magic` (offset 0x40) | `_BHRfS_M` | 8 байт ASCII |
| `root_dir_objectid` | 6 | `__le64` |
| `nodesize` | 4096 | `__le32` |
| `root_tree_logical` | 4194304 (0x400000) | `__le64` byte-nr |
| `chunk_tree_logical` | 5242880 (0x500000) | `__le64` byte-nr |
| `fs_tree_objectid` | 5 | `__le64` |
| `fs_tree_leaf_logical` | 6291456 (0x600000) | `__le64` byte-nr |

Процедура `btrfs_mount` подтверждает три обязательных условия поддержки FS:

1. `magic == "_BHRfS_M"` — побайтовое сравнение через `ztext_eq`;
2. `nodesize == 4096`;
3. `root_dir_objectid > 0`.

При несовпадении выдаётся `500 unsupported filesystem` и FTP-диалог не запускается. Эта ветка демонстрируется отдельным тестом [tests/btrfs_unsupported.asm](../tests/btrfs_unsupported.asm) с искажённым magic `EXT4FS!_`.

## FS Tree

Образ описывает следующее дерево файловой системы:

```text
inode 256: /                              (root_dir_objectid → запись BTRFS_FIRST_FREE_OBJECTID)
inode 258: /docs/                         (DIR_ITEM из root)
inode 260: /pictures/                     (DIR_ITEM из root)
inode 257: /readme.txt   size=19 inline   (DIR_ITEM из root, EXTENT_DATA)
inode 259: /docs/info.txt size=19 inline  (DIR_ITEM из docs, EXTENT_DATA)
inode 261: /docs/help.txt size=12 inline  (DIR_ITEM из docs, EXTENT_DATA)
inode 262: /pictures/notes.txt size=17 inline (DIR_ITEM из pictures, EXTENT_DATA)
```

### Directory items

| Каталог | Имя | Целевой inode | Тип |
|---|---|---|---|
| `/` | `docs` | 258 | `BTRFS_FT_DIR` |
| `/` | `pictures` | 260 | `BTRFS_FT_DIR` |
| `/` | `readme.txt` | 257 | `BTRFS_FT_REG_FILE` |
| `/docs` | `info.txt` | 259 | `BTRFS_FT_REG_FILE` |
| `/docs` | `help.txt` | 261 | `BTRFS_FT_REG_FILE` |
| `/pictures` | `notes.txt` | 262 | `BTRFS_FT_REG_FILE` |

### File extents

| inode | size | extent | данные |
|---|---|---|---|
| 257 | 19 | inline | `Hello from SPO8 FS\n` |
| 259 | 19 | inline | `BTRFS TREE WALK OK\n` |
| 261 | 12 | inline | `RETR works.\n` |
| 262 | 17 | inline | `subtree readable\n` |

## Соответствие командам FTP и stream-объектам SPO7

| FTP | Btrfs-операция | Объекты SPO7-stream |
|---|---|---|
| `PASV` | переход в passive output stream | `stream_write_byte` (sink, port=1) |
| `PWD` | печать текущего каталога | sink |
| `LIST` | обход `DIR_ITEM` текущего каталога | source → formatter → sink |
| `CWD` | смена `v_current_dir` через resolve `DIR_ITEM` | lookup |
| `RETR` | обход `DIR_ITEM` → `INODE_ITEM` → `EXTENT_DATA` | source → sink |
| `SYST` | служебная FTP-команда (215) | sink |
| `NOOP` | служебная FTP-команда (200) | sink |
| `HELP` | список поддерживаемых команд (214) | sink |
| `TYPE` | переключение типа передачи (200) | sink |
| `QUIT` | выгрузка статистики | sink |

Все обходы идут через единый sink `stream_write_byte`, который ведёт счётчик `v_stream_bytes` и фиксирует `v_group_waits` каждые `v_stream_window=7` байт — это та же модель passive group wait, что и в SPO7 (`SYNC-NB GROUP-WAIT`).

## Согласование строк команд и путей

Разбор FTP-команд и аргументов идёт побайтовым сравнением (`cmd_starts_with`, `arg_eq`) с эталонными NUL-терминированными строками в секциях `m_*` (имена команд) и `p_*`/`n_*` (пути и имена файлов). Это исключает случайное совпадение по первой букве и обрабатывает разделители `\0`, ` `, `\r`, `\n` после токена.
