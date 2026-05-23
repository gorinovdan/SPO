# Btrfs-образ SPO8

SPO8 использует настоящий Btrfs-образ `spo8_btrfs_block.img`. Он не собирается вручную из байтов в ASM и не подменяется host-директорией во время FTP-сессии.

## Сборка

Образ создаёт [../tools/prepare_btrfs_image.sh](../tools/prepare_btrfs_image.sh):

```text
dd if=/dev/zero of=spo8_btrfs_block.img bs=1M count=160
mkfs.btrfs -f -L SPO8_REAL spo8_btrfs_block.img
mount -o loop spo8_btrfs_block.img /mnt/spo8
rsync ./SPO8/ /mnt/spo8/SPO8/
umount /mnt/spo8
```

На Linux используются локальные `mkfs.btrfs`, `mount`, `btrfs inspect-internal`. На macOS те же команды выполняются в привилегированном контейнере Alpine с `btrfs-progs`.

Из копирования исключены `results`, сам `spo8_btrfs_block.img`, исполняемые артефакты сборки и служебные каталоги. Это нужно, чтобы образ не включал сам себя и не зависел от старых результатов прогонов.

## Что лежит внутри

В корне образа находится каталог `/SPO8`, внутри — исходные файлы лабораторной:

```text
/
  SPO8/
    Makefile
    README.md
    Validation.md
    demo/small.txt
    docs/btrfs_image.md
    tests/
    tools/
    vm/
    ...
```

Контрольный файл для быстрой проверки FTP-клиентом:

```text
/SPO8/demo/small.txt
```

## Извлечение метаданных

После размонтирования скрипт сохраняет дампы:

```text
results/btrfs_real_super.txt
results/btrfs_real_chunk.txt
results/btrfs_real_tree.txt
results/btrfs_source_files.txt
```

[../tools/gen_btrfs_ftp_asm.py](../tools/gen_btrfs_ftp_asm.py) строит из них статический индекс для VM:

- `INODE_ITEM` даёт inode, тип и размер;
- `DIR_ITEM` даёт связь «каталог -> имя -> inode»;
- `EXTENT_DATA` даёт физическое смещение данных файла;
- chunk tree переводит логические адреса Btrfs в физические смещения файла-образа.

Содержимое файлов не вшивается в ASM. При `RETR` и `COPY` VM читает данные из `BlockDevice` по смещению extent: сначала диапазон попадает в `block_buffer` через `BLOCK_READ_BUF`, затем `DATA_COPY_BLOCK` переносит порцию в пассивный FTP-поток. `BLOCK_BUF_BYTE` оставлен для совместимого побайтового чтения буфера.

## Проверка суперблока

`btrfs_mount` в ASM читает из `BlockDevice`:

| Поле | Смещение |
|---|---:|
| магическое значение `_BHRfS_M` | `0x10000 + 0x40` |
| root objectid | `0x10000 + 0x80` |
| nodesize | `0x10000 + 0x94` |

Если магическое значение не совпадает или поля некорректны, программа печатает:

```text
500 unsupported filesystem
```

## Связь с FTP

`LIST` использует индекс `DIR_ITEM`/`INODE_ITEM`.

`RETR` и `COPY` идут по цепочке:

```text
имя из FTP-команды
  -> DIR_ITEM
  -> inode
  -> INODE_ITEM.size
  -> EXTENT_DATA.physical_offset
  -> BLOCK_READ_BUF
  -> BLOCK_BUF_BYTE
  -> DATA_BUF_BYTE/DATA_FLUSH
```

Так преподавателю можно показать, что данные берутся из Btrfs-образа, а не из файлов host OS.
