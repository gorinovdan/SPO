# SPO6 — планирование задач в многопоточной среде

## Что реализовано
- `SPO6` сделан как полноценная копия проекта `SPO5`: в директорию перенесены `ast`, `analysis`, `cfg`, `codegen`, `view`, `vm`, `main.c`, project-файлы и утилиты.
- Таймер и прерывания переведены на **внешние устройства VM-утилиты**: `SimplePic` + `SimpleClock` монтируются через [devices.xml](devices.xml) к memory ranges `pic_state` / `pic_handlers` / `clock_state` в `spo6.target.pdsl`. Per-instruction эмуляции таймера нет — `Cycles` тикает сам clock-device, `on-cycles` сигнал транслируется PIC в прерывание id 2.
- Добавлены инструкции `irq_enter` (сохранение user-context + switch в kernel), `iret` (восстановление из `irq_*`, `ip ← pic_state[0]`), `set_period` (программирование `CyclesSignalPeriod`), `set_cycles_handler` (запись в `pic_handlers[8]`), `ei` / `di` (`pic_state[12]` gate).
- Тестовая программа `tests/scheduler_demo.asm` использует реальные таймерные прерывания и настоящее переключение контекста через PCB.
- Поверх PCB реализованы runtime-абстракции `create_thread(entry_ip, stack_top, task_end) -> tid` и `on_thread_interrupt(handler_ip)`. `rt_init_contexts` теперь состоит из шести `create_thread` + одного `on_thread_interrupt`.
- Два невытесняющих алгоритма планирования:
  - `FCFS` — First-Come, First-Served.
  - `SPN` — Shortest Process Next.
- PCB включает:
  - время поступления и длительность;
  - оставшееся время и состояние;
  - логический `pc` и checksum для контрольных вычислений;
  - реальные сохранённые контексты `ip/sp/bp/dbp/csp`;
  - время старта и завершения.
- Тестовая программа печатает в `stdout.txt`:
  - arrivals;
  - bursts;
  - timeline выполнения;
  - времена ожидания;
  - turnaround time;
  - средние метрики;
  - число таймерных срабатываний и dispatch-ов;
  - число срабатываний пользовательского хука `H:` (подтверждает, что `on_thread_interrupt` зарегистрировал callback и `rt_timer_handler` его действительно вызывает перед каждым `iret`).

## Таймер и прерывания (через VmDevices)

Реализация полностью device-driven:
- `SimpleClock` (bank `clock_state`, `Mode="RAM"`) автономно инкрементирует `Cycles`; программируемый `CyclesSignalPeriod` (8-байтовый регистр по offset 64) задаёт, раз в сколько инструкций поднимается сигнал `on-cycles`.
- Сигнал `on-cycles` привязан в `devices.xml` к `Interrupt="2"` PIC'а. `SimplePic` при его срабатывании атомарно пишет `ip` в `pic_state:4[0]` и загружает новый `ip` из `pic_handlers:4[8]` (адрес handler'а); `InterruptsAllowed` сбрасывается.
- Первая инструкция `rt_timer_handler` — `irq_enter`: копирует `sp/bp/dbp/csp` → `irq_*` и переключает на kernel context (`ksp/kbp/kdbp/kcsp`).
- Handler сохраняет PCB текущего потока, выбирает следующий (`FCFS` или `SPN`), загружает его контекст через `rt_load_irq_context` (пишет в `irq_sp/bp/dbp/csp` и `pic_state:4[0]`), и делает `iret`: тот восстанавливает `sp/bp/dbp/csp` из `irq_*`, `ip` из `pic_state:4[0]` и устанавливает `InterruptsAllowed = 1`.
- Алгоритмы остаются невытесняющими: сигнал прилетает каждый такт, но смена потока происходит только по завершению текущего.

## Структура
- `tests/scheduler_demo.asm` — исходная interrupt-driven тестовая программа.
- `tests/timer_probe.asm` — минимальная проверка таймера и `iret`.
- `results/` — generated asm, ptptb, stdout, trace.
- `spo6.target.pdsl` — target VM для RemoteTasks.
- `tools/run_remote.sh`, `tools/run_remote.bat` — запуск через RemoteTasks.
- `tools/check_scheduler_output.py` — проверка текста `stdout.txt`.
- `Validation.md` — команды проверки.
- `report.md` — отчёт по пунктам задания.
- `teacher_review.md` — заготовка для фиксации согласования с преподавателем.

## Сборка и запуск

Сборка компилятора:

```bash
make -C SPO6 build
```

Подготовка asm для remote-прогона:

```bash
make -C SPO6 asm
```

Полный RemoteTasks-прогон:

```bash
make -C SPO6 remote-demo
```

Если выбранный RemoteTasks service сохраняет `rout_s`, после успешного прогона автоматически проверяется содержимое:

- `SPO6/results/scheduler_demo.stdout.txt`

В текущем device-run используется `ExecuteBinaryWithIo`: он dispatch'ит `SimpleClock`/`SimplePic`, но может не сохранять `rout_s` в `stdout.txt`. В этом случае критерием smoke-test является завершение run без исключений.

## Ожидаемый результат

В `stdout.txt` должны быть две разные дисциплины планирования на одной и той же нагрузке.

Ключевые различия:
- `FCFS`: `AW = 5`, `AT = 10`
- `SPN`: `AW = 4`, `AT = 9`
- timeline для `SPN` отличается от `FCFS`: после длинной задачи `3` сначала выполняются более короткие `5` и `6`, а длинная `4` уходит позже.

Контрольные суммы вычислений одинаковые для обоих запусков:

```text
406 806 2121 2821 2006 2406
```

Для обоих алгоритмов также совпадают:

- `I: 30` — число срабатываний `rt_timer_handler` в симуляции;
- `H: 30` — число вызовов пользовательского хука `user_trace_hook` (регистрируется через `on_thread_interrupt`).

Это подтверждает корректность сохранения и восстановления логического контекста, а также что runtime API `create_thread`/`on_thread_interrupt` действительно подключены.

## Последняя проверка

Успешный полный прогон через `Portable.RemoteTasks.Manager.exe`:
- `assemble = 231b82d3-5319-4f72-9a15-704ca2827dd4`
- `run      = d561c55b-dc04-4d59-9c71-55c2d3d80530`

Команда:

```bash
make -C SPO6 remote-demo
```

## Согласование с преподавателем

Технически пакет подготовлен к согласованию:
- отчёт собран;
- remote-артефакты сохранены;
- воспроизводимый сценарий проверки готов.

Само согласование с преподавателем требует внешнего human review и не может быть выполнено автоматически из CLI. Для этого добавлен файл `teacher_review.md`.
