# SPO8 — Btrfs через RemoteTasks VmDevices

Практическое задание № 3, вариант 4 — `Btrfs`.

SPO8 поднимает FTP-сервер внутри VM, запущенной через `Portable.RemoteTasks.Manager.exe` и `VmDevices`. Образ — настоящий Btrfs-файл `spo8_btrfs_block.img`, который собирается из дерева `SPO8` через `mkfs.btrfs`, `mount`, копирование и `umount`.

## Основной контур

- `tools/prepare_btrfs_image.sh` создаёт Btrfs-образ каталога `SPO8`.
- `tools/gen_btrfs_ftp_asm.py` строит индекс `INODE_ITEM`/`DIR_ITEM`/`EXTENT_DATA` из дампа дерева настоящего образа.
- `tests/btrfs_ftp_demo.asm` реализует FTP-команды, проверку суперблока и чтение файлов через `BlockDevice`.
- `devices.xml` запускает сценарий через stdio `SimplePipe`.
- `devices_filezilla.xml` подключает VM к внутренним портам FTP-адаптера и к `BlockDevice`.
- `tools/ftp_data_adapter.c` принимает внешний FTP control-порт `127.0.0.1:2121`, пассивный data-порт `127.0.0.1:2020` и последовательно прокидывает команды в FTP-сервер VM; это не сервер Btrfs и не источник файловых данных.

## Запуск

```bash
make -C SPO8 local-demo
make -C SPO8 remote-demo
make -C SPO8 remote-unsupported
make -C SPO8 remote-ftp-smoke
```

Ручной запуск для FileZilla:

```bash
make -C SPO8 remote-filezilla
```

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

Проверенный файл для скачивания: `/SPO8/demo/small.txt`.
`/SPO8/report.md` также проверен: VM читает его из `BlockDevice`
порциями по 512 байт и отдаёт через пассивный FTP-поток. Повторные
control-подключения FileZilla принимает C-адаптер, поэтому открытие файла
не зависает на ожидании второго `220`.

## Что смотреть

- [report.md](report.md) — полный отчёт по заданию.
- [Validation.md](Validation.md) — команды проверки.
- [docs/btrfs_image.md](docs/btrfs_image.md) — как собирается и индексируется Btrfs-образ.
- [spo8.target.pdsl](spo8.target.pdsl) — инструкции `PIPE_IN`, `PIPE_OUT`, `DATA_BUF_BYTE`, `DATA_FLUSH`, `DATA_COPY_BLOCK`, `BLOCK_READ_BYTE`, `BLOCK_READ_BUF`, `BLOCK_BUF_BYTE`, `BLOCK_WRITE_BYTE`.
