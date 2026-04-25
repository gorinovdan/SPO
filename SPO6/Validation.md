# Validation SPO6 через Portable.RemoteTasks.Manager.exe

Все команды выполняются из корня репозитория `SPO`.

## Основной сценарий

```bash
make -C SPO6 remote-demo
```

Эта команда делает всё последовательно:
- собирает standalone-проект `SPO6` на основе перенесённого кода `SPO5`;
- копирует `tests/scheduler_demo.asm` в `results/scheduler_demo.asm`;
- собирает и запускает бинарник через `Portable.RemoteTasks.Manager.exe` / `ExecuteBinaryWithIo`;
- сохраняет `ptptb`; `ExecuteBinaryWithIo` обрабатывает VmDevices, но не всегда сохраняет `rout_s` в `stdout.txt`.

## Ручной запуск

### 1. Сборка и подготовка asm

```bash
make -C SPO6 asm
```

### 2. RemoteTasks на macOS/Linux через `mono`

```bash
./SPO6/tools/run_remote.sh ./SPO6/results/scheduler_demo.asm ./tools/vm_input.txt exec \
  ./SPO6/results/scheduler_demo.ptptb \
  ./SPO6/results/scheduler_demo.stdout.txt \
  ./SPO6/results/scheduler_demo.trace.txt
```

### 3. Проверка результата

```bash
python3 ./SPO6/tools/check_scheduler_output.py ./SPO6/results/scheduler_demo.stdout.txt
```

Проверку stdout выполняйте только если выбранный RemoteTasks service реально сохранил `stdout.txt`. Для device-run критичный признак — завершение `ExecuteBinaryWithIo` без исключений.

## RemoteTasks на Windows

```powershell
copy .\SPO6\tests\scheduler_demo.asm .\SPO6\results\scheduler_demo.asm
.\SPO6\tools\run_remote.bat .\SPO6\results\scheduler_demo.asm .\tools\vm_input.txt exec `
  .\SPO6\results\scheduler_demo.ptptb .\SPO6\results\scheduler_demo.stdout.txt .\SPO6\results\scheduler_demo.trace.txt
python .\SPO6\tools\check_scheduler_output.py .\SPO6\results\scheduler_demo.stdout.txt
```

## Ожидаемый `stdout.txt`

```text
FCFS
A: 0 3 6 9 12 15
B: 4 4 7 7 4 4
T: 1 1 1 1 2 2 2 2 3 3 3 3 3 3 3 4 4 4 4 4 4 4 5 5 5 5 6 6 6 6
W: 0 1 2 6 10 11
R: 4 5 9 13 14 15
AW: 5
AT: 10
C: 406 806 2121 2821 2006 2406
I: 30
D: 6
H: 30

SPN
A: 0 3 6 9 12 15
B: 4 4 7 7 4 4
T: 1 1 1 1 2 2 2 2 3 3 3 3 3 3 3 5 5 5 5 6 6 6 6 4 4 4 4 4 4 4
W: 0 1 2 14 3 4
R: 4 5 9 21 7 8
AW: 4
AT: 9
C: 406 806 2121 2821 2006 2406
I: 30
D: 6
H: 30
```

Ключевые строки:
- `I` — число вызовов `rt_timer_handler` (timer IRQ на каждую инструкцию пользовательского потока);
- `D` — число диспатчей (`rt_activate_current` + `mark_dispatch`);
- `H` — число вызовов пользовательского хука, зарегистрированного через `on_thread_interrupt` (должно совпадать с `I`, так как хук вызывается перед каждым `iret` из `rt_timer_handler`).

## Что проверять в debug/trace

- Завершение программы через `RET` без исключений.
- Timer-driven переключения идут через устройства: инструкция `set_cycles_handler` пишет адрес handler'а в `pic_handlers:4[8]`, `set_period` программирует следующий `CyclesSignalPeriod` как `Cycles + period`, `iret` выставляет `pic_state:4[12] = 1`, когда clock armed. Каждое срабатывание IRQ начинается с `irq_enter` и заканчивается `iret` (читающим `ip` из `pic_state:4[0]`).
- Вызов `create_thread` ровно 6 раз в начале каждой симуляции (из `rt_init_contexts`).
- Вызов `on_thread_interrupt` 1 раз в начале каждой симуляции (регистрирует `user_trace_hook`).
- Вызов `rt_invoke_user_irq` перед каждым `iret` из `rt_timer_handler`.
- Выполнение обеих дисциплин планирования: сначала `FCFS`, затем `SPN`.
- Если выбранный RemoteTasks service сохраняет trace, артефакт:
  - `SPO6/results/scheduler_demo.trace.txt`

## Последний успешный прогон

- `assemble = 231b82d3-5319-4f72-9a15-704ca2827dd4`
- `run      = d561c55b-dc04-4d59-9c71-55c2d3d80530`
