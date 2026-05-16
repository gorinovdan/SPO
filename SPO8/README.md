# SPO8 — Btrfs reader through PASSIVE FTP

Практическое задание №3, вариант 4 — `Btrfs`. Реализовано в рамках комплекса SPO1–SPO7.

## Что реализовано

- [tests/btrfs_ftp_demo.asm](tests/btrfs_ftp_demo.asm) — VM-программа: держит тестовый Btrfs-образ в `data_mem`, проверяет superblock, обходит FS tree, отдаёт ответы по FTP.
- Команды PASSIVE FTP: `SYST`, `NOOP`, `HELP`, `PASV`, `TYPE`, `PWD`, `LIST`, `CWD`, `RETR`, `QUIT`.
- Каталоги/файлы извлекаются из Btrfs-структур: superblock magic, root tree/FS tree references, compact FS-tree leaf с `DIR_ITEM`, `INODE_ITEM` и inline `EXTENT_DATA`.
- Вывод идёт через единый sink `stream_write_byte` — та же модель `synchronous non-blocking + GROUP-WAIT`, что и в [SPO7](../SPO7/README.md).
- Негативный путь «FS не поддерживается» — отдельный тест [tests/btrfs_unsupported.asm](tests/btrfs_unsupported.asm).
- Python используется только как ассемблер/интерпретатор VM (наследие [SPO3](../SPO3/README.md)) и валидатор stdout. Логика Btrfs/FTP/stream живёт в ASM/VM.

## Структура каталога

- [tests/btrfs_ftp_demo.asm](tests/btrfs_ftp_demo.asm) — основной runtime Btrfs/FTP.
- [tests/btrfs_ftp_commands.txt](tests/btrfs_ftp_commands.txt) — input byte stream для локальной VM (ASCII-коды по одному на строку).
- [tests/btrfs_ftp_commands.remote.txt](tests/btrfs_ftp_commands.remote.txt) — тот же сценарий для RemoteTasks `ExecuteBinaryWithInput` обычным текстом.
- [tests/btrfs_unsupported.asm](tests/btrfs_unsupported.asm) — негативный сценарий с искажённым magic.
- [tools/check_btrfs_ftp_output.py](tools/check_btrfs_ftp_output.py) — валидатор основного stdout.
- [tools/check_btrfs_unsupported.py](tools/check_btrfs_unsupported.py) — валидатор негативного stdout.
- [spo8.target.pdsl](spo8.target.pdsl), [devices.xml](devices.xml) — VM-таргет с инструкциями `INDEXB / LOADB_IND / STOREB_IND` и устройствами таймера/PIC из SPO7.
- [results/](results/) — закреплённые stdout-эталоны.
- [docs/btrfs_image.md](docs/btrfs_image.md) — описание тестового образа и соответствие реальному Btrfs.
- [Validation.md](Validation.md) — команды воспроизведения.
- [report.md](report.md) — отчёт по 6 пунктам задания.

## Запуск

Локальная VM (быстро, без удалённого окружения):

```bash
make -C SPO8 local-demo          # основной FTP-сценарий
make -C SPO8 local-unsupported   # негативный путь — FS не поддерживается
```

Удалённая VM (RemoteTasks через `tools/run_remote.sh`; используется прямой host/port transport `5.19.208.160:10001`, stdout не подменяется эталоном):

```bash
make -C SPO8 remote-demo
make -C SPO8 remote-unsupported
```

Ожидаемый вывод основного сценария — см. [results/btrfs_ftp_demo.stdout.txt](results/btrfs_ftp_demo.stdout.txt).

## Как читается образ

Контракт `btrfs_mount`: совпадение magic `_BHRfS_M`, `nodesize == 4096`, `root_dir_objectid > 0`. При нарушении — `500 unsupported filesystem` и выход без входа в FTP-цикл (пункт 1 общего алгоритма задания).

Дальше команды разбираются `dispatch_command`, сканируют таблицы FS-tree leaf (`img_dirent_*`, `img_inode_*`, `img_extent_*`) через `INDEX / LOAD_IND` и читают строковые/inline-данные через байтовые операции `INDEXB / LOADB_IND`. Все ответы пишутся через единый sink `stream_write_byte`. Sink ведёт `v_stream_bytes`, фиксирует `v_group_waits` каждые 7 байт — наследие stream-модели SPO7.
