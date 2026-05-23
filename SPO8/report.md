# SPO8: Btrfs через RemoteTasks и пассивный FTP

Практическое задание № 3, вариант 4 — `Btrfs`. Реализация запускается как VM-программа через `Portable.RemoteTasks.Manager.exe`, `ExecuteBinaryWithIo` и устройства из `VmDevices`. Внешний FTP-сервер не используется: FTP-диалог, проверка Btrfs, обход каталогов и чтение файлов выполняет ASM-программа [tests/btrfs_ftp_demo.asm](tests/btrfs_ftp_demo.asm).

## 1. Постановка задачи

По заданию нужно было взять программный комплекс первого семестра СПО и добавить операции извлечения данных для структуры варианта. Для варианта 4 структура — файловая система Btrfs.

Общий алгоритм выполнен так:

1. VM читает суперблок из блочного устройства и проверяет магическое значение `_BHRfS_M`.
2. Если образ поддерживается, VM переходит в диалоговый FTP-цикл.
3. FTP-цикл поддерживает команды, нужные обычным клиентам: `USER`, `PASS`, `FEAT`, `PASV`, `EPSV`, `PWD`, `CWD`, `CDUP`, `LIST`, `NLST`, `SIZE`, `MDTM`, `RETR`, `COPY`, `TYPE`, `SYST`, `NOOP`, `HELP`, `QUIT`.
4. `LIST` показывает имена и атрибуты директорий, `RETR` копирует файл, `COPY` явно демонстрирует копирование файла или директории, `PWD/CWD/CDUP` управляют текущей директорией.
5. Образ строится как настоящий Btrfs-файл через `mkfs.btrfs`, `mount`, копирование дерева `SPO8` и `umount`.

## 2. Источники по Btrfs

В реализации использованы основные элементы on-disk формата Btrfs:

- суперблок по смещению `0x10000`;
- магическое значение `_BHRfS_M` по смещению `0x40` внутри суперблока;
- chunk tree для перевода логических адресов Btrfs в физические смещения файла-образа;
- FS tree с ключами вида `(objectid type offset)`;
- элементы `INODE_ITEM`, `DIR_ITEM`, `DIR_INDEX`, `EXTENT_DATA`;
- типы файлов `BTRFS_FT_REG_FILE` и `BTRFS_FT_DIR`;
- обычные и inline extents.

Ссылки из задания:

- `https://btrfs.wiki.kernel.org/index.php/Btrfs_design`;
- `https://btrfs.wiki.kernel.org/index.php/On-disk_Format`;
- `https://btrfs.wiki.kernel.org/index.php/Data_Structures`.

## 3. Подготовка образа

Образ создаёт [tools/prepare_btrfs_image.sh](tools/prepare_btrfs_image.sh). На Linux скрипт использует локальные `btrfs-progs`; на macOS автоматически запускает привилегированный контейнер Alpine с `btrfs-progs`. Контейнер нужен только как среда с `mkfs.btrfs` и `mount`, не как часть FTP-сервера.

Последовательность соответствует схеме преподавателя:

```text
dd if=/dev/zero of=spo8_btrfs_block.img bs=1M count=160
mkfs.btrfs -f -L SPO8_REAL spo8_btrfs_block.img
mount -o loop spo8_btrfs_block.img /mnt/spo8
rsync ./SPO8/ /mnt/spo8/SPO8/
umount /mnt/spo8
```

В образ попадает дерево проекта `SPO8`:

```text
/
  SPO8/
    Makefile
    README.md
    Validation.md
    analysis/
    ast/
    cfg/
    codegen/
    demo/small.txt
    docs/
    tests/
    tools/
    view/
    vm/
    ...
```

Из копирования исключены только генерируемые и рекурсивные артефакты: `results`, `spo8_btrfs_block.img`, `app`, `app.exe`, `app.dSYM`, `.git`, `.DS_Store`. Без этого образ включал бы сам себя и предыдущие результаты запуска.

После `umount` скрипт сохраняет служебные дампы:

- `results/btrfs_real_super.txt`;
- `results/btrfs_real_chunk.txt`;
- `results/btrfs_real_tree.txt`;
- `results/btrfs_source_files.txt`.

Текущий образ: `167772160` байт, метка `SPO8_REAL`, `nodesize=16384`, магическое значение `_BHRfS_M`.

## 4. Индекс Btrfs-дерева

[tools/gen_btrfs_ftp_asm.py](tools/gen_btrfs_ftp_asm.py) читает дампы `btrfs inspect-internal dump-tree` и генерирует таблицы в [results/btrfs_ftp_demo.asm](results/btrfs_ftp_demo.asm) между маркерами:

```asm
; BEGIN GENERATED BTRFS TABLES
; END GENERATED BTRFS TABLES
```

Генерируются:

- `img_inode_*` — objectid, тип и размер из `INODE_ITEM`;
- `img_dirent_*` — parent inode, target inode, тип и имя из `DIR_ITEM`;
- `img_extent_*` — inode, физическое смещение данных и размер из `EXTENT_DATA`;
- `img_name_pool` — пул имён для `LIST`, `CWD`, `RETR`, `COPY`.

Важно: байты файлов не вшиваются в ASM. Для `RETR` и `COPY` VM берёт физическое смещение extent из таблицы и читает реальные байты из `spo8_btrfs_block.img` через `BlockDevice`.

## 5. Устройства RemoteTasks

Сценарный запуск использует [devices.xml](devices.xml):

- `SimplePipe` `stdio` — управляющий поток FTP-команд и ответов;
- `BlockDevice` `btrfs-image` — файл `spo8_btrfs_block.img`;
- `SimplePic` и `SimpleClock` — окружение VM из предыдущих лабораторных.

Режим FileZilla использует [devices_filezilla.xml](devices_filezilla.xml):

- `ftp-control`: `tcp://127.0.0.1:3121`, внутренний управляющий порт C-адаптера;
- внешний FTP control-порт для FileZilla: `127.0.0.1:2121`;
- `ftp-data`: `tcp://127.0.0.1:3020`, внутренний data-порт C-адаптера;
- внешний пассивный FTP data-порт для FileZilla: `127.0.0.1:2020`;
- `BlockDevice`: тот же `spo8_btrfs_block.img`.

[spo8.target.pdsl](spo8.target.pdsl) добавляет банки и инструкции:

| Инструкция | Назначение |
|---|---|
| `PIPE_IN` | чтение байта управляющего `SimplePipe` |
| `PIPE_OUT` | запись байта управляющего `SimplePipe` |
| `DATA_BUF_BYTE` | запись байта в буфер пассивного потока данных |
| `DATA_FLUSH` | отправка накопленного data-буфера |
| `DATA_COPY_BLOCK` | перенос порции `block_buffer` в пассивный FTP-поток |
| `BLOCK_READ_BYTE` | чтение байта из `BlockDevice` |
| `BLOCK_READ_BUF` | чтение диапазона из `BlockDevice` в буфер устройства |
| `BLOCK_BUF_BYTE` | чтение байта из заполненного буфера `BlockDevice` |
| `BLOCK_WRITE_BYTE` | запись байта в `BlockDevice` |

`tools/ftp_data_adapter.c` — не внешний FTP-сервер и не источник файловых данных. Это сетевой мост для FileZilla: управляющие соединения FileZilla на `127.0.0.1:2121` последовательно прокидываются в один управляющий `SimplePipe` VM на `127.0.0.1:3121`; пассивный data-порт `127.0.0.1:2020` прокидывается в data-`SimplePipe` VM на `127.0.0.1:3020` и закрывается после каждой передачи. Все FTP-команды, обход Btrfs и чтение файлов выполняются в VM.

## 6. Логика VM-программы

Основная реализация находится в [tests/btrfs_ftp_demo.asm](tests/btrfs_ftp_demo.asm).

Ключевые процедуры:

- `main` — настраивает общий `data_mem`, сбрасывает FTP-состояние, вызывает `btrfs_mount`, затем `ftp_loop`;
- `btrfs_mount` — читает магическое значение Btrfs, `nodesize` и objectid корня из `BlockDevice`;
- `ftp_loop` — читает строки FTP-команд через `PIPE_IN`;
- `dispatch_command` — разбирает команду и вызывает обработчик;
- `cmd_list`, `cmd_nlst` — сканируют `DIR_ITEM` текущей директории;
- `cmd_cwd`, `cmd_cdup`, `emit_pwd` — ведут текущий каталог и путь;
- `cmd_retr` — находит файл по `DIR_ITEM`, получает размер из `INODE_ITEM`, extent из `EXTENT_DATA` и отдаёт байты;
- `cmd_copy` — для файла работает как `RETR`, для директории рекурсивно обходит очередь каталогов;
- `stream_write_byte` — единая точка вывода, переключает управляющий поток и поток данных по `v_sink`;
- `emit_block_data` — читает содержимое файла из `BlockDevice` порциями до 512 байт и отдаёт их в пассивный FTP-поток.

## 7. FTP и FileZilla

Сервер работает как обычный FTP без TLS и использует пассивный режим передачи данных.

Параметры FileZilla:

```text
Хост: 127.0.0.1
Порт: 2121
Протокол: FTP
Шифрование: только обычный FTP без TLS
Тип входа: анонимный
Режим передачи: пассивный
Timeout: 120 секунд или больше
```

`PASV` возвращает:

```text
227 Entering Passive Mode (127,0,0,1,7,228)
```

Порт данных: `7 * 256 + 228 = 2020`.

Проверенный путь для FileZilla/curl:

```text
/
  SPO8/
    demo/
      small.txt
```

Также через FileZilla можно просматривать `tools`, `tests`, `docs`, `vm` и другие директории, потому что они находятся в настоящем Btrfs-образе.

Содержимое файлов читается из настоящего `BlockDevice`, но не побайтно:
`emit_block_data` выполняет `BLOCK_READ_BUF` порциями по 512 байт, затем
`DATA_COPY_BLOCK` переносит эту порцию в пассивный FTP-поток. `/SPO8/report.md`
проверен отдельным smoke-тестом; для быстрой демонстрации всё равно удобнее
использовать `/SPO8/demo/small.txt`.

## 8. Запуск

Локальная VM:

```bash
make -C SPO8 local-demo
make -C SPO8 local-unsupported
```

RemoteTasks:

```bash
make -C SPO8 remote-demo
make -C SPO8 remote-unsupported
```

Интерактивная задача RemoteTasks:

```bash
make -C SPO8 remote-interactive
```

FileZilla:

```bash
make -C SPO8 remote-filezilla
```

Автоматическая проверка FileZilla-контура через FTP-клиент `curl`:

```bash
make -C SPO8 remote-ftp-smoke
```

## 9. Проверка

Последние успешные проверки 16 мая 2026:

| Команда | Результат |
|---|---|
| `make -C SPO8 local-demo` | `Btrfs FTP output OK` |
| `make -C SPO8 remote-demo` | `assemble=<uuid>`, `run=interactive-pipe`, `Btrfs FTP output OK` |
| `make -C SPO8 remote-unsupported` | `assemble=<uuid>`, `Btrfs unsupported-FS output OK` |
| `make -C SPO8 remote-ftp-smoke` | `assemble=<uuid>`, `Быстрая FTP-проверка через RemoteTasks пройдена`, `LIST /` содержит `SPO8`, `RETR /SPO8/demo/small.txt` успешен |
| `make -C SPO8 remote-ftp-report-smoke` | `Проверка RETR /SPO8/report.md через RemoteTasks пройдена` |

Окончание положительного RemoteTasks-сценария:

```text
150 recursive directory copy follows
COPY file small.txt
150 inode=292 size=64 extent=btrfs
226 transfer complete
226 copy complete
...
550 not found
550 not found
221 bye
STATS cmd=24 lookup=16 stream=3281 gw=469
OK
```

Негативный сценарий:

```text
SPO8 BTRFS FTP
500 unsupported filesystem
OK_NEG
```

## 10. Что показывать на защите

1. [tools/prepare_btrfs_image.sh](tools/prepare_btrfs_image.sh): показать `dd`, `mkfs.btrfs`, `mount`, копирование `SPO8`, `umount`.
2. [devices_filezilla.xml](devices_filezilla.xml): показать `tcp://127.0.0.1:3121`, второй `SimplePipe` для канала данных и `BlockDevice`.
3. [spo8.target.pdsl](spo8.target.pdsl): показать инструкции `PIPE_IN`, `PIPE_OUT`, `DATA_BUF_BYTE`, `DATA_FLUSH`, `DATA_COPY_BLOCK`, `BLOCK_READ_BYTE`, `BLOCK_READ_BUF`, `BLOCK_BUF_BYTE`.
4. [tests/btrfs_ftp_demo.asm](tests/btrfs_ftp_demo.asm): показать `btrfs_mount`, `cmd_list`, `cmd_cwd`, `cmd_retr`, `cmd_copy`.
5. Запустить `make -C SPO8 remote-ftp-smoke`: это доказывает, что обычный FTP-клиент подключается к серверу, поднятому через RemoteTasks.
6. Запустить `make -C SPO8 remote-filezilla`, открыть FileZilla и вручную зайти в `/SPO8/demo`, скачать `small.txt`, затем показать листинг `/SPO8/tools`.

Главный тезис: Btrfs-образ настоящий и создан штатными инструментами Btrfs; FTP-сервер работает внутри VM через RemoteTasks; FileZilla подключается к этому VM-серверу, а не к внешнему Python-серверу и не к host-директории напрямую.
