# Проверка SPO8

Все команды выполняются из корня репозитория `SPO`.

## Контур

Проверяется именно RemoteTasks-контур:

- `prepare_btrfs_image.sh` создаёт настоящий Btrfs-образ из каталога `SPO8`;
- `BlockDevice` открывает `spo8_btrfs_block.img`;
- управляющий FTP-поток идёт через `SimplePipe` VM и C-адаптер, который принимает повторные control-подключения FileZilla, но не разбирает пути и не синхронизирует `CWD`;
- пассивный FTP-поток идёт через второй `SimplePipe` и тот же C-адаптер;
- FTP-сервер выполняется внутри VM-программы [tests/btrfs_ftp_demo.asm](tests/btrfs_ftp_demo.asm).

## Основной сценарий

Файл сценария: [tests/btrfs_ftp_commands.remote.txt](tests/btrfs_ftp_commands.remote.txt).

```text
SYST
NOOP
HELP
PASV
TYPE I
PWD
LIST
CWD SPO8
PWD
LIST
CWD demo
LIST
RETR small.txt
CWD ..
COPY demo
CWD tools
LIST
SIZE run_vm_tests.sh
RETR run_vm_tests.sh
CWD /
LIST
CWD ghost
RETR missing.txt
QUIT
```

Сценарий проверяет:

- определение Btrfs по суперблоку;
- вывод `/` и `/SPO8`;
- переходы `CWD`;
- листинг директорий;
- чтение файла из Btrfs extent через `RETR`;
- явное копирование директории через `COPY demo`;
- `SIZE`;
- отрицательные ответы `550 not found`.

## Локальная VM

```bash
make -C SPO8 local-demo
make -C SPO8 local-unsupported
```

Ожидаемые результаты:

```text
Btrfs FTP output OK
Btrfs unsupported-FS output OK
```

## RemoteTasks

```bash
make -C SPO8 remote-demo
make -C SPO8 remote-unsupported
```

Последний успешный прогон:

```text
assemble=<uuid>
run=interactive-pipe
Btrfs FTP output OK
```

Негативная проверка:

```text
assemble=<uuid>
run=interactive-pipe
Btrfs unsupported-FS output OK
```

## FileZilla

Ручной запуск:

```bash
make -C SPO8 remote-filezilla
```

Параметры клиента:

```text
Хост: 127.0.0.1
Порт: 2121
Протокол: FTP
Шифрование: только обычный FTP без TLS
Тип входа: анонимный
Режим передачи: пассивный
Timeout: 120 секунд или больше
```

Проверить вручную:

```text
/
LIST
CWD SPO8
LIST
CWD demo
RETR small.txt
CWD ../tools
LIST
```

Для быстрой демонстрации копирования использовать `/SPO8/demo/small.txt`.
Для проверки более крупного файла есть отдельный сценарий:

```bash
make -C SPO8 remote-ftp-report-smoke
```

Автоматический smoke-тест тем же контуром:

```bash
make -C SPO8 remote-ftp-smoke
```

Проверка скачивания `/SPO8/report.md`:

```bash
make -C SPO8 remote-ftp-report-smoke
```

Ожидаемый результат:

```text
Проверка RETR /SPO8/report.md через RemoteTasks пройдена
```

Последний успешный результат:

```text
Быстрая FTP-проверка через RemoteTasks пройдена
assemble=<uuid>
control=127.0.0.1:2121 data=127.0.0.1:2020
listing=.../SPO8/results/remote_filezilla_listing.txt
retr=.../SPO8/results/remote_filezilla_small.txt
```

`remote_filezilla_listing.txt` содержит каталог `SPO8`, а `remote_filezilla_small.txt` содержит:

```text
SPO8 Btrfs FTP demo file.
Read through RemoteTasks BlockDevice.
```

## Ожидаемый финал положительного сценария

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

Числа inode и счётчики могут немного измениться после изменения состава файлов `SPO8`, потому что образ каждый раз создаётся заново.
