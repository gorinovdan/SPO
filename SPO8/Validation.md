# Validation SPO8

Все команды выполняются из корня репозитория `SPO`.

## Задание

Практическое задание №3, вариант 4: поддержка операций извлечения данных из Btrfs-образа с интерфейсом в стиле PASSIVE FTP.

Реализация — в `SPO8/tests/btrfs_ftp_demo.asm` (положительный сценарий) и `SPO8/tests/btrfs_unsupported.asm` (негативный сценарий: FS не поддерживается).

Основной сценарий команд:

```text
SYST
NOOP
HELP
PASV
TYPE I
PWD
LIST
CWD docs
PWD
LIST
RETR info.txt
RETR help.txt
CWD ..
PWD
CWD pictures
LIST
RETR notes.txt
CWD /
RETR readme.txt
RETR missing.txt
CWD ghost
QUIT
```

Для локальной VM он хранится в `SPO8/tests/btrfs_ftp_commands.txt` как ASCII-коды по одному числу на строку. Для RemoteTasks `ExecuteBinaryWithInput` используется тот же сценарий обычным текстом: `SPO8/tests/btrfs_ftp_commands.remote.txt`.

## Локальная VM

Положительный сценарий:

```bash
make -C SPO8 local-demo
```

Под капотом:

```bash
python3 SPO8/tools/asm.py -s SPO8/vm/spec.json \
  -i SPO8/tests/btrfs_ftp_demo.asm \
  -o SPO8/results/btrfs_ftp_demo.local.ptptb

python3 SPO8/tools/vm.py -s SPO8/vm/spec.json \
  -i SPO8/results/btrfs_ftp_demo.local.ptptb \
  --max-steps 200000 \
  < SPO8/tests/btrfs_ftp_commands.txt \
  > SPO8/results/btrfs_ftp_demo.local.stdout.txt

python3 SPO8/tools/check_btrfs_ftp_output.py \
  SPO8/results/btrfs_ftp_demo.local.stdout.txt
```

Ожидаемый результат: `Btrfs FTP output OK`. `results/btrfs_ftp_demo.local.stdout.txt` совпадает с эталоном `results/btrfs_ftp_demo.stdout.txt`.

Негативный сценарий (FS не поддерживается):

```bash
make -C SPO8 local-unsupported
```

Ожидаемый результат: `Btrfs unsupported-FS output OK`. Эталон — `results/btrfs_unsupported.stdout.txt`.

## Удалённая VM

```bash
make -C SPO8 remote-demo
make -C SPO8 remote-unsupported
```

`tools/run_remote.sh` использует RemoteTasks-task `ExecuteBinaryWithInput`, скачивает реальный `stdout.txt` и затем запускает те же валидаторы. Из-за проблем системного DNS с `remote-tasks.portable-project.ru` в macOS-окружении используется прямой transport `-sh 5.19.208.160 -sp 10001 -okssl`; его можно переопределить переменной `RT_REMOTE_FLAGS`. Если RemoteTasks недоступен или не вернул stdout, цель `make` завершается ошибкой; ожидаемый вывод не подставляется локально. Таймаут удалённых вызовов задаётся переменной `RT_TIMEOUT` (по умолчанию 120 секунд).

Последний успешный прогон:

- `remote-demo`: `assemble=d482be37-39e6-40fe-8694-b2dc3f0e057c`, `run=2622de26-f264-41d1-92bc-a24bda3413a8`;
- `remote-unsupported`: `assemble=dba3f942-f167-46e4-8faf-2489ec1a21d7`, `run=e7d3a76d-93fc-4f31-a66f-740bd0a8fc6c`.

## Проверенные выводы

Положительный сценарий — `results/btrfs_ftp_demo.stdout.txt`:

```text
SPO8 BTRFS FTP
FS OK magic=_BHRfS_M root_dir=6 nodesize=4096
220 SPO8 Btrfs image ready
> SYST
215 UNIX Type: L8
> NOOP
200 NOOP ok
> HELP
214-Supported commands:
214 PASV PWD LIST CWD RETR SYST NOOP HELP TYPE QUIT
> PASV
227 Entering Passive Mode (0,0,0,0,0,1)
> TYPE I
200 Type set
> PWD
257 "/"
> LIST
150 directory stream follows
d 258 0 docs
d 260 0 pictures
f 257 19 readme.txt
226 transfer complete
> CWD docs
250 CWD ok
> PWD
257 "/docs"
> LIST
150 directory stream follows
f 259 19 info.txt
f 261 12 help.txt
226 transfer complete
> RETR info.txt
150 inode=259 size=19 extent=inline
BTRFS TREE WALK OK
226 transfer complete
> RETR help.txt
150 inode=261 size=12 extent=inline
RETR works.
226 transfer complete
> CWD ..
250 CWD ok
> PWD
257 "/"
> CWD pictures
250 CWD ok
> LIST
150 directory stream follows
f 262 17 notes.txt
226 transfer complete
> RETR notes.txt
150 inode=262 size=17 extent=inline
subtree readable
226 transfer complete
> CWD /
250 CWD ok
> RETR readme.txt
150 inode=257 size=19 extent=inline
Hello from SPO8 FS
226 transfer complete
> RETR missing.txt
550 not found
> CWD ghost
550 not found
> QUIT
221 bye
STATS cmd=22 lookup=13 stream=1166 gw=167
OK
```

Негативный сценарий — `results/btrfs_unsupported.stdout.txt`:

```text
SPO8 BTRFS FTP
500 unsupported filesystem
OK_NEG
```
