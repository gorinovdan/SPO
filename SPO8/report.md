# SPO8 — Btrfs reader через PASSIVE FTP

Практическое задание № 3, вариант 4: Btrfs. Работа выполнена в рамках комплекса SPO1–SPO7: используется стековая VM, ассемблерный runtime, byte-stream ввод/вывод, stream-модель SPO7 и RemoteTasks-запуск.

Главная цель реализации — показать не готовые строки ответов, а реальный обход подготовленного образа структуры данных: проверка superblock, поиск записей каталогов, чтение inode metadata и извлечение inline extent payload.

## 0. Соответствие пунктам задания

| #   | Пункт задания                                                              | Где выполнено                                                                                                                                      |
| --- | -------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Изучить внутреннюю организацию Btrfs и инструменты инспектирования         | раздел 2, [docs/btrfs_image.md](docs/btrfs_image.md)                                                                                               |
| 2   | Реализовать функции инспектирования и извлечения через stream-объекты SPO7 | разделы 4–5, [tests/btrfs_ftp_demo.asm](tests/btrfs_ftp_demo.asm)                                                                                  |
| 3   | Подготовить тестовый образ                                                 | раздел 3, секция `data_mem`                                                                                                                        |
| 4   | Реализовать тестовую FTP-программу                                         | раздел 6, [tests/btrfs_ftp_commands.txt](tests/btrfs_ftp_commands.txt), [tests/btrfs_ftp_commands.remote.txt](tests/btrfs_ftp_commands.remote.txt) |
| 5   | Показать корректность                                                      | раздел 7, [Validation.md](Validation.md), `tools/check_btrfs_*.py`                                                                                 |
| 6   | Подготовить отчёт                                                          | этот файл                                                                                                                                          |

## 1. Связь с комплексом SPO1–SPO7

SPO8 не является отдельной программой вне предыдущих лабораторных. Она использует тот же стек:

- SPO1–SPO3: frontend, IR/CFG, стековая VM, Python-ассемблер и локальный VM-интерпретатор;
- SPO6: RemoteTasks-инфраструктура, `devices.xml`, таймер/PIC-окружение;
- SPO7: последовательные byte streams и модель `synchronous non-blocking + GROUP-WAIT`.

Для Btrfs потребовалась побайтовая адресация, поэтому в VM-таргет добавлены инструкции:

| Инструкция   | Назначение                                         |
| ------------ | -------------------------------------------------- |
| `INDEX`      | адресация word-таблиц: `base + index * 4`          |
| `INDEXB`     | адресация байтовых строк и payload: `base + index` |
| `LOAD_IND`   | чтение 4-байтового слова по адресу                 |
| `LOADB_IND`  | чтение одного байта по адресу                      |
| `STOREB_IND` | запись одного байта по адресу                      |

В `main` используется `POP_SYS 19` со значением `0`: это выставляет общий data frame для вызовов процедур. Поэтому `v_current_dir`, счётчики stream, буферы команд и образ Btrfs живут в одной общей `data_mem` и сохраняют состояние между `CALL`.

## 2. Внутренняя организация Btrfs

Использованные источники:

- <https://btrfs.wiki.kernel.org/index.php/Btrfs_design>
- <https://btrfs.wiki.kernel.org/index.php/On-disk_Format>
- <https://btrfs.wiki.kernel.org/index.php/Data_Structures>

Btrfs хранит метаданные в copy-on-write B+-деревьях. Для чтения файла важны следующие уровни:

1. **Superblock**: содержит magic `_BHRfS_M`, `nodesize`, `root_dir_objectid`, ссылки на root tree и chunk tree. В реальном Btrfs основной superblock расположен по смещению `0x10000`, а magic — по offset `0x40` внутри superblock.
2. **Root tree**: позволяет найти FS tree конкретного subvolume/root object.
3. **FS tree**: содержит записи с ключами `objectid/type/offset`. В этой работе используются аналоги `DIR_ITEM`, `INODE_ITEM` и `EXTENT_DATA`.
4. **Inline extent**: для малых файлов данные могут храниться прямо в leaf FS tree, без отдельного extent на диске.

Реальные инструменты инспектирования Btrfs — `btrfs inspect-internal`, `btrfs-debug-tree`, `btrfs check`. SPO8 повторяет их общий ход на компактном in-memory образе: mount-проверка, обход метаданных, извлечение payload.

## 3. Принятые ограничения реализации

Реализация не является универсальным драйвером полного Btrfs-раздела. Это осознанное ограничение лабораторной работы: требуется поддержать набор операций извлечения для подготовленного образа структуры данных.

Реализовано:

- проверка Btrfs superblock по magic и базовым полям;
- compact FS-tree leaf в памяти VM;
- обход `DIR_ITEM` для каталогов;
- чтение размера и типа из `INODE_ITEM`;
- чтение inline `EXTENT_DATA`;
- FTP-подобный интерфейс для `LIST`, `CWD`, `PWD`, `RETR`, `COPY`.

Не реализовано, потому что не требуется для подготовленного inline-образа:

- checksum tree и проверка контрольных сумм;
- chunk mapping и физическая трансляция logical address;
- extent allocation tree;
- RAID-профили, compression, snapshots;
- non-inline extents;
- реальный TCP FTP-сервер.

## 4. Тестовый образ

Образ находится в [tests/btrfs_ftp_demo.asm](tests/btrfs_ftp_demo.asm), секция `data_mem`. Подробное описание — [docs/btrfs_image.md](docs/btrfs_image.md).

Содержимое:

```text
/
  docs/
    info.txt      inode 259, size 19, inline
    help.txt      inode 261, size 12, inline
  pictures/
    notes.txt     inode 262, size 17, inline
  readme.txt      inode 257, size 19, inline
```

Superblock-поля:

| Поле в ASM                 |   Значение | Смысл                                   |
| -------------------------- | ---------: | --------------------------------------- |
| `img_super_magic`          | `_BHRfS_M` | Btrfs magic                             |
| `img_root_dir_objectid`    |          6 | root directory objectid из Btrfs        |
| `img_nodesize`             |       4096 | размер node/leaf                        |
| `img_root_tree_logical`    |    4194304 | демонстрационная ссылка на root tree    |
| `img_chunk_tree_logical`   |    5242880 | демонстрационная ссылка на chunk tree   |
| `img_fs_tree_objectid`     |          5 | objectid FS tree                        |
| `img_fs_tree_leaf_logical` |    6291456 | демонстрационная ссылка на FS tree leaf |

Метаданные представлены как параллельные таблицы:

| Таблица        | Аналог Btrfs  | Что хранит                               |
| -------------- | ------------- | ---------------------------------------- |
| `img_inode_*`  | `INODE_ITEM`  | inode objectid, тип, размер              |
| `img_dirent_*` | `DIR_ITEM`    | parent inode, target inode, тип, name id |
| `img_extent_*` | `EXTENT_DATA` | inode, extent type, data id              |

Такой формат выбран из-за ограничений стековой VM: он сохраняет смысл Btrfs key/value leaf, но позволяет сканировать записи простыми инструкциями `INDEX` и `LOAD_IND`.

Отдельный отрицательный образ [tests/btrfs_unsupported.asm](tests/btrfs_unsupported.asm) содержит magic `EXT4FS!_`; он проверяет ветку «файловая система не поддерживается».

## 5. Алгоритм работы VM-программы

Общая цепочка исполнения:

```text
main
  -> btrfs_mount
  -> ftp_loop
       -> read_line
       -> dispatch_command
            -> cmd_list / cmd_cwd / cmd_retr / cmd_copy / emit_pwd
                 -> fs_find_dirent_by_arg
                 -> fs_load_inode_size
                 -> fs_find_extent_data
                 -> emit_* -> stream_write_byte
```

### 5.1. Mount-проверка

`btrfs_mount` проверяет:

1. `img_super_magic == "_BHRfS_M"`;
2. `img_nodesize == 4096`;
3. `img_root_dir_objectid > 0`.

Если проверка провалена, `main` печатает `500 unsupported filesystem` и не переходит в FTP-цикл. Это прямо закрывает первый пункт общего алгоритма задания: «проверить, поддерживается ли файловая система».

### 5.2. Чтение и разбор команд

`read_line` читает поток port `0` посимвольно в `v_cmd_buf`. Конец команды — `LF` (`10`), `CR` игнорируется. Команда заканчивается NUL-байтом, чтобы дальше её можно было сравнивать как строку.

`dispatch_command` вызывает `compute_arg_offset`, затем проверяет командные токены через `cmd_starts_with`. Сравнение идёт по полному имени команды и границе токена, поэтому случайные префиксы не распознаются как валидные команды.

`arg_eq` сравнивает аргумент после команды с именем каталога или файла. Это используется в `CWD`, `RETR` и `COPY`.

### 5.3. LIST

`cmd_list` сканирует все `DIR_ITEM`:

```text
for i in 0..img_dirent_count-1:
    if img_dirent_parent[i] == v_current_dir:
        inode = img_dirent_inode[i]
        size = fs_load_inode_size(inode)
        type = img_dirent_type[i]
        name = img_dirent_name_id[i]
        emit_list_entry(type, inode, size, name)
```

То есть список каталога получается не из заранее записанной строки, а из записей каталога в образе.

### 5.4. CWD и PWD

`v_current_dir` хранит inode текущего каталога:

- `256` — `/`;
- `258` — `/docs`;
- `260` — `/pictures`.

`cmd_cwd` поддерживает:

- `CWD /` — переход в root inode;
- `CWD .` — остаться в текущем каталоге;
- `CWD ..` — поиск родителя через `fs_parent_of_current`;
- `CWD <dir>` — поиск `DIR_ITEM` по имени и проверка, что тип записи — каталог.

`emit_pwd` печатает путь текущего каталога. Для подготовленного образа достаточно трёх путей: `/`, `/docs`, `/pictures`.

### 5.5. RETR

`cmd_retr` выполняет основную операцию извлечения файла:

```text
имя файла
  -> fs_find_dirent_by_arg
  -> target inode
  -> fs_load_inode_size
  -> fs_find_extent_data
  -> emit_file
  -> emit_data_by_id
  -> stream_write_byte
```

`fs_find_extent_data` дополнительно проверяет `extent_type == 0`. В этой работе `0` означает inline extent: данные лежат прямо в leaf FS tree. Например, `RETR info.txt` находит inode `259`, получает размер `19`, находит data id для строки `BTRFS TREE WALK OK\n` и отдаёт эти байты через stream sink.

### 5.6. COPY

`cmd_copy` добавлен как явная команда копирования файла или каталога. Для обычного файла команда выполняет тот же путь извлечения, что и `RETR`: `DIR_ITEM -> INODE_ITEM -> EXTENT_DATA -> stream`.

Для каталога `COPY` запускает обход дерева каталогов через очередь inode:

```text
queue = [target_dir_inode]
while queue is not empty:
    dir = pop(queue)
    for each DIR_ITEM where parent == dir:
        if type == file:
            copy file by inode
        if type == directory:
            push child directory inode
```

Например, `COPY docs` копирует оба inline-файла каталога `docs`: `info.txt` и `help.txt`. `COPY readme.txt` показывает путь копирования одного файла отдельной командой, а не только стандартным FTP `RETR`.

## 6. Stream-модель SPO7

Внутри FTP/Btrfs-логики нет прямой записи результата мимо sink. Все строки, числа, листинги и payload проходят через `stream_write_byte`.

`stream_write_byte` делает четыре действия:

1. увеличивает `v_stream_bytes`;
2. уменьшает `v_stream_window`;
3. когда окно доходит до нуля, увеличивает `v_group_waits` и сбрасывает окно на 7;
4. пишет байт в port `1`.

Это модель `synchronous non-blocking + GROUP-WAIT` из SPO7 в упрощённом виде: sink не занят активным ожиданием, а фиксирует событие passive wait после заданного окна передач.

Итоговая статистика:

```text
STATS cmd=24 lookup=15 stream=1518 gw=218
```

Смысл:

- `cmd=24` — обработано 24 FTP-команды;
- `lookup=15` — выполнено 15 операций обращения к FS tree (`LIST`, `CWD`, `RETR`, `COPY`);
- `stream=1518` — 1518 байт прошли через `stream_write_byte`;
- `gw=218` — 218 passive `GROUP-WAIT` событий.

## 7. PASSIVE FTP-интерфейс

`main` выполняет общий алгоритм задания:

1. `btrfs_mount` проверяет, поддерживается ли файловая система.
2. При отказе печатает `500 unsupported filesystem`.
3. При успехе печатает `220 SPO8 Btrfs image ready`.
4. `ftp_loop` читает команды до `QUIT`.

Поддержаны команды:

| Команда  | Результат                           |
| -------- | ----------------------------------- |
| `SYST`   | служебный ответ `215 UNIX Type: L8` |
| `NOOP`   | служебный ответ `200 NOOP ok`       |
| `HELP`   | список поддержанных команд          |
| `TYPE I` | подтверждение binary mode           |
| `PASV`   | ответ passive mode                  |
| `PWD`    | текущий каталог                     |
| `LIST`   | список имён и атрибутов             |
| `CWD`    | смена каталога                      |
| `RETR`   | извлечение файла                    |
| `COPY`   | копирование файла или каталога      |
| `QUIT`   | завершение и статистика             |

Копирование директории в FTP обычно строится из `LIST`, `CWD` и последовательных `RETR` файлов. Чтобы закрыть формулировку задания буквально, дополнительно реализована команда `COPY`: для файла она работает как явный вариант `RETR`, для каталога рекурсивно обходит `DIR_ITEM` и копирует найденные обычные файлы.

Основной сценарий покрывает корень, подкаталоги `docs` и `pictures`, успешные `RETR`, `COPY docs`, `COPY readme.txt`, ошибочные `RETR missing.txt` и `CWD ghost`. Для локальной VM он хранится в [tests/btrfs_ftp_commands.txt](tests/btrfs_ftp_commands.txt) как ASCII-коды по одному числу на строку, для RemoteTasks — в [tests/btrfs_ftp_commands.remote.txt](tests/btrfs_ftp_commands.remote.txt) обычным текстом.

## 8. Проверка корректности

Локальная VM:

```bash
make -C SPO8 local-demo
make -C SPO8 local-unsupported
```

Ожидаемые результаты:

```text
Btrfs FTP output OK
Btrfs unsupported-FS output OK
```

RemoteTasks:

```bash
make -C SPO8 remote-demo
make -C SPO8 remote-unsupported
```

## 9. Вывод

Реализация закрывает общий алгоритм задания: сначала проверяется поддержка Btrfs, затем запускается FTP-диалог с `LIST`, `RETR`, `COPY`, `PWD`, `CWD`. Извлечение данных выполняется через сканирование компактных Btrfs-подобных `DIR_ITEM`, `INODE_ITEM` и `EXTENT_DATA` структур в памяти VM. Вывод построен на stream-модели SPO7 и проверяется локально и через RemoteTasks без подмены ожидаемым stdout.

## 10. Пример
```bash
PWD
LIST
RETR readme.txt
COPY docs
CWD pictures
LIST
RETR notes.txt
CWD /
COPY /
QUIT
```
