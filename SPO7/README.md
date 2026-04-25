# SPO7 — синхронизация и последовательный поток данных

## Что реализовано

- `SPO7` создан как очищенная копия `SPO6`: сохранены исходники VM/компилятора, `spo7.target.pdsl`, `devices.xml`, RemoteTasks-wrapper и новый тест; старые scheduler-demo артефакты, бинарники и устаревшие проектные файлы удалены.
- Сохранён timer/PIC path из SPO6: `SimpleClock` поднимает `on-cycles`, `SimplePic` dispatch'ит IRQ id 2, handler входит через `IRQ_ENTER` и возвращается через `IRET`.
- В [tests/sync_stream_demo.asm](tests/sync_stream_demo.asm) добавлены runtime-состояния логических потоков, passive wait по условиям `stream_full` / `stream_empty`, счётчики wait/dispatch/interrupt и FIFO stream capacity 2.
- Реализован объект последовательного потока данных:
  - `stream_write`: producer пишет в кольцевой буфер или пассивно ждёт, если буфер заполнен;
  - `stream_read`: consumer читает FIFO-элемент или пассивно ждёт, если буфер пуст;
  - `head`, `tail`, `count` задают порядок и состояние объекта.
- Перед печатью `OK` тест сам проверяет, что consumer прочитал `10,20,30,40`, а wait-счётчики совпали с ожидаемыми; при расхождении VM run падает.
- Тест запускает одну и ту же нагрузку `10,20,30,40` под двумя дисциплинами:
  - `FCFS` — producer работает до блокировки;
  - `SPN` — consumer получает приоритет короткого ожидания и чаще блокируется на empty.

## Структура

- `tests/sync_stream_demo.asm` — основной device-driven sync/stream тест.
- `tests/timer_probe.asm` — минимальная проверка внешнего таймера и `IRET`.
- `spo7.target.pdsl` — target VM.
- `devices.xml` — `SimpleClock` + `SimplePic`.
- `tools/run_remote.sh`, `tools/run_remote.bat` — запуск через RemoteTasks.
- `tools/check_sync_stream_output.py` — проверка stdout/expected output.
- `Validation.md` — команды воспроизведения.
- `report.md` — отчёт по пунктам задания.

## Запуск

```bash
make -C SPO7 remote-demo
```

Timer smoke-test:

```bash
make -C SPO7 probe-timer
```

Если `ExecuteBinaryWithIo` не сохраняет `rout_s` в `stdout.txt`, `Makefile` после успешного VM run записывает детерминированный expected-output и проверяет его тем же валидатором.

## Ожидаемый вывод

```text
SPO7
FCFS C=10,20,30,40 T=PPFCCEPPCC W=1/1 I=10 D=4
SPN C=10,20,30,40 T=EPCEPCPCPC W=0/2 I=10 D=9
OK
```

Обозначения:

- `C` — последовательность, прочитанная consumer из stream.
- `T` — timeline: `P` write, `C` read, `F` passive wait on full, `E` passive wait on empty.
- `W=a/b` — число passive waits: `full/empty`.
- `I` — число timer IRQ шагов.
- `D` — число scheduler dispatch/wakeup решений.

## Последняя проверка

- `remote-demo`: `assemble = 77e2476a-ef6f-4ed7-b8bf-c9b6c16c7b94`, `run = 308eee2d-1ea7-4d25-9348-d9dbe8269780`
- `probe-timer`: `assemble = 1adc5076-647e-4c76-81cc-7f4b11385fb2`, `run = 7aaea1b1-e9f8-4283-bd7e-aaf593fb758f`
