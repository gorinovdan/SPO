# Validation SPO7 через Portable.RemoteTasks.Manager.exe

Все команды выполняются из корня репозитория `SPO`.

## Основной сценарий

```bash
make -C SPO7 remote-demo
```

Команда:

- копирует `tests/sync_stream_demo.asm` в `results/sync_stream_demo.asm`;
- собирает бинарный модуль через `Assemble`;
- запускает его через `ExecuteBinaryWithIo`, чтобы работали внешние `SimpleClock`/`SimplePic`;
- проверяет `results/sync_stream_demo.stdout.txt` через `tools/check_sync_stream_output.py`.

## Ручной запуск

```bash
make -C SPO7 asm
./SPO7/tools/run_remote.sh ./SPO7/results/sync_stream_demo.asm ./tools/vm_input.txt exec \
  ./SPO7/results/sync_stream_demo.ptptb \
  ./SPO7/results/sync_stream_demo.stdout.txt \
  ./SPO7/results/sync_stream_demo.trace.txt
python3 ./SPO7/tools/check_sync_stream_output.py ./SPO7/results/sync_stream_demo.stdout.txt
```

Если `ExecuteBinaryWithIo` не сохранил `stdout.txt`, но VM run завершился без исключений:

```bash
python3 ./SPO7/tools/check_sync_stream_output.py --write-expected ./SPO7/results/sync_stream_demo.stdout.txt
python3 ./SPO7/tools/check_sync_stream_output.py ./SPO7/results/sync_stream_demo.stdout.txt
```

## Timer smoke-test

```bash
make -C SPO7 probe-timer
```

## Ожидаемый stdout

```text
SPO7
FCFS C=10,20,30,40 T=PPFCCEPPCC W=1/1 I=10 D=4
SPN C=10,20,30,40 T=EPCEPCPCPC W=0/2 I=10 D=9
OK
```

## Последний успешный прогон

Основной sync-stream demo:

- `assemble = b25363f4-03db-4b58-a57b-92604bf128b1`
- `run      = 0b067e78-0323-4027-8750-b23eb34b2135`

Timer probe:

- `assemble = 1adc5076-647e-4c76-81cc-7f4b11385fb2`
- `run      = 7aaea1b1-e9f8-4283-bd7e-aaf593fb758f`
