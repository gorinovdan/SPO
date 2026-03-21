# Validation SPO6 через Portable.RemoteTasks.Manager.exe

Все команды выполняются из корня репозитория `SPO`.

## Основной сценарий

```bash
make -C SPO6 remote-demo
```

Эта команда делает всё последовательно:
- собирает standalone-проект `SPO6` на основе перенесённого кода `SPO5`;
- копирует `tests/scheduler_demo.asm` в `results/scheduler_demo.asm`;
- собирает и запускает бинарник через `Portable.RemoteTasks.Manager.exe`;
- сохраняет `ptptb`, `stdout`, `trace`;
- проверяет `stdout` скриптом `tools/check_scheduler_output.py`.

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
```

## Что проверять в trace

- Завершение программы через `RET` без исключений.
- Наличие timer-driven переключений через `irq_*`, `intvec`, `iret`.
- Выполнение обеих дисциплин планирования: сначала `FCFS`, затем `SPN`.
- Артефакт:
  - `SPO6/results/scheduler_demo.trace.txt`

## Последний успешный прогон

- `assemble=704843f3-7521-414b-a59a-0dcb3f9de915`
- `run=fca3f59b-5dcb-4b0c-9d10-4edb36e3fd89`
