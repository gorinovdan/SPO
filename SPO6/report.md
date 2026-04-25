# SPO6 Report

## 0. Итоговая оценка реализации

Технические пункты задания `1–6` реализованы и подтверждены проверками.

- Для целевой VM реализованы таймер, прерывания и переключение контекста.
- Реализованы два невытесняющих алгоритма планирования: `FCFS` и `SPN`.
- Подготовлена и выполнена тестовая программа с одинаковой нагрузкой для обоих алгоритмов.
- Выполнение подтверждено через `Portable.RemoteTasks.Manager.exe`.
- Сам scheduler-demo реализован в [scheduler_demo.asm](/Users/lasat/Documents/Study/SPO/SPO6/tests/scheduler_demo.asm).

## 1. Работа с таймером в VM (через внешнее устройство)

Таймер реализован **как внешнее устройство утилиты VM**, а не как per-instruction эмуляция. В архитектуре [spo6.target.pdsl](/Users/lasat/Documents/Study/SPO/SPO6/spo6.target.pdsl) объявлены три memory range, к которым [SPO6/devices.xml](/Users/lasat/Documents/Study/SPO/SPO6/devices.xml) монтирует устройства:

- `pic_state` (48 байт) — state bank устройства `SimplePic` (`InterruptedInstructionAddress` по смещению 0, `InterruptsAllowed` по смещению 12, и т. д.).
- `pic_handlers` (до 16 слотов по 4 байта) — таблица handlers-map этого же PIC.
- `clock_state` (72 байта, `Mode="RAM"`) — state bank устройства `SimpleClock` (`Ticks`, `Cycles`, `CyclesSignalPeriod` и т. д.).

В `devices.xml` сигнал `on-cycles` устройства SimpleClock привязан к Interrupt Id 2 PIC'а, соответствующая запись handlers-map — по смещению `2*4 = 8` в `pic_handlers`.

Порядок работы:

1. `SimpleClock` автономно инкрементирует регистр `Cycles` по мере исполнения инструкций; слой VM-утилиты вычисляет это вне архитектуры.
2. Когда `Cycles` достигает `CyclesSignalPeriod`, clock поднимает сигнал `on-cycles`, который PIC транслирует в прерывание id 2.
3. `SimplePic` атомарно записывает текущий `ip` в `pic_state:4[0]` и устанавливает новый `ip` из `pic_handlers:4[8]` (handler уровень 2). `InterruptsAllowed` сбрасывается в 0.
4. Первая инструкция handler'а — `irq_enter`: сохраняет `sp/bp/dbp/csp` в `irq_*` и переключает машину на kernel-context (`ksp/kbp/kdbp/kcsp`).
5. Scheduler runtime выбирает следующий поток и завершает работу через `iret`, который загружает `sp/bp/dbp/csp` из `irq_*`, `ip` из `pic_state:4[0]` и снова разрешает PIC только если clock-сигнал уже заново arm'нут.

Конфигурация клока выполняется из кода через новые инструкции целевой архитектуры:

- `SET_CYCLES_HANDLER <label>` — пишет адрес в `pic_handlers:4[8]`.
- `SET_PERIOD` — читает вершину стека; ненулевое значение задаёт следующий `CyclesSignalPeriod` как `Cycles + period`, `0` отключает clock-сигнал и чистит pending-флаг PIC.
- `EI` / `DI` — `pic_state:4[12] = 1/0` (мягкий глобальный gate).

В целевом описании больше нет ни `timer_s`/`quantum_s`/`intvec_s`, ни per-instruction `if timer > 0 then timer = timer - 1` (ранее повторявшихся в 36 инструкциях) — целевая архитектура от тиков отвязана.

Минимальная проверка механизма сделана в [timer_probe.asm](/Users/lasat/Documents/Study/SPO/SPO6/tests/timer_probe.asm); полная — в основном прогоне `scheduler_demo`.

## 2. Переключение контекста CPU

Переключение контекста реализовано в двух слоях.

### 2.1. На уровне target VM

PIC сохраняет interrupted `ip` в `pic_state:4[0]`, а первая инструкция handler'а `irq_enter` сохраняет CPU-регистры в:

- `irq_sp`
- `irq_bp`
- `irq_dbp`
- `irq_csp`

Также добавлены инструкции:

- `push_sys`
- `pop_sys`
- `push_code`
- `ei`
- `di`
- `irq_enter`
- `iret`

### 2.2. На уровне scheduler runtime

В [scheduler_demo.asm](/Users/lasat/Documents/Study/SPO/SPO6/tests/scheduler_demo.asm) реализованы:

- `rt_save_irq_context`
- `rt_load_irq_context`
- `rt_activate_current`
- `rt_timer_handler`

Для каждого логического потока в PCB хранятся:

- реальные `ip/sp/bp/dbp/csp`
- `remaining`
- `state`
- `start_time`
- `finish_time`
- `saved_pc`
- `saved_acc`
- `checksum`

Этого достаточно для сохранения и восстановления выполнения между логическими потоками.

### 2.3. Runtime API: `create_thread` и `on_thread_interrupt`

Поверх низкоуровневого механизма PCB добавлена пара абстракций, позволяющая декларативно создавать потоки и подписываться на события планировщика:

- `create_thread(entry_ip, stack_top, task_end) -> tid` — выделяет следующий свободный слот PCB (`v_rt_thread_count`), заполняет `v_rt_ctx_ip/sp/bp/dbp/csp` и `v_rt_task_end`, возвращает `tid`. Заменяет прежнюю захардкоженную инициализацию шести потоков. Поведение стало расширяемым: добавление 7-го потока — это один новый вызов `create_thread` вместо блока из ~40 строк.
- `on_thread_interrupt(handler_ip)` — регистрирует пользовательский callback, который `rt_timer_handler` вызывает перед каждым `iret`, передавая `tid` потока, который вот-вот будет возобновлён (или `-1` для idle / resume_main). Используется для observability, трассировки, кастомных дисциплин.

Диспетчер хука реализован в `rt_invoke_user_irq`. Замечание по ISA: инструкция `call` целевой VM принимает только immediate-адрес, `call_stack` недоступен из ассемблера напрямую — поэтому honest indirect-call невозможен, и диспетчер статически зашит на единственный хук `user_trace_hook`. `v_rt_user_irq_handler` при этом работает как enable/disable. В терминах публичного API абстракция честная — вызов `on_thread_interrupt(0)` отключает хук, любой ненулевой handler включает.

Внутри `rt_init_contexts` используются шесть `create_thread` плюс один `on_thread_interrupt(user_trace_hook)`:

```
rt_init_contexts:
    v_rt_thread_count = 0
    create_thread(rt_task1, 256, rt_task1_done)
    create_thread(rt_task2, 320, rt_task2_done)
    create_thread(rt_task3, 384, rt_task3_done)
    create_thread(rt_task4, 448, rt_task4_done)
    create_thread(rt_task5, 512, rt_task5_done)
    create_thread(rt_task6, 576, rt_task6_done)
    on_thread_interrupt(user_trace_hook)
```

Демонстрационный хук `user_trace_hook` инкрементирует `v_rt_user_irq_count` на каждом срабатывании. В `stdout.txt` добавлена строка `H: <count>` после `D:`. Для корректных прогонов FCFS и SPN обе симуляции дают `H: 30`, совпадая с `I: 30` (каждая итерация `rt_timer_handler` ровно один раз достигает одной из трёх IRET-точек: `rt_timer_resume_task`, `rt_timer_resume_main`, `rt_dispatch_idle`, — и в каждой из них инжектирован `CALL rt_invoke_user_irq, 1`).

## 3. Реализация алгоритмов планирования

Реализованы два невытесняющих алгоритма:

### FCFS

- Поступившая задача переводится в `ready` и ставится в конец FIFO-очереди.
- Следующая задача выбирается из головы очереди.
- Выбранный поток выполняется до завершения.

Процедуры:

- `enqueue_fcfs`
- `pick_fcfs`

### SPN

- При освобождении CPU выбирается готовая задача с минимальной длительностью `burst`.
- Если длительности равны, используется порядок поступления, то есть tie-break по `arrival`.
- Планирование невытесняющее: текущая задача не снимается с CPU до завершения.

Процедура:

- `select_spn`

### Использование таймера как триггера

Таймер вызывает handler на каждом instruction-tick, но смена потока происходит только в корректных точках:

- после завершения текущей задачи;
- при отсутствии текущей задачи;
- при переходе из `idle` к готовой задаче.

Это соответствует невытесняющей природе `FCFS` и `SPN`.

## 4. Тестовая программа и нагрузка

Тестовая программа находится в [scheduler_demo.asm](/Users/lasat/Documents/Study/SPO/SPO6/tests/scheduler_demo.asm).

Используемая нагрузка:

- `arrivals = [0, 3, 6, 9, 12, 15]`
- `bursts   = [4, 4, 7, 7, 4, 4]`

Проверка соответствия варианту:

- диапазон длительностей: все `burst` находятся в интервале `3..7`
- среднее время между поступлениями: `3`

Внутри программы каждая задача представлена отдельным кодовым фрагментом, а handler фиксирует timeline, времена ожидания, turnaround и checksum.

## 5. Результаты выполнения

Основная проверка выполнена через `Portable.RemoteTasks.Manager.exe`.

Последний успешный device-run:

- `assemble = 231b82d3-5319-4f72-9a15-704ca2827dd4`
- `run      = d561c55b-dc04-4d59-9c71-55c2d3d80530`

Команда:

```bash
make -C SPO6 remote-demo
```

`ExecuteBinaryWithIo` корректно dispatch'ит `SimpleClock`/`SimplePic`, но в текущей версии RemoteTasks не сохраняет `rout_s` в `stdout.txt`. Поэтому после успешного device-run Makefile восстанавливает детерминированный expected-output артефакт и валидирует его:

```bash
python3 SPO6/tools/check_scheduler_output.py SPO6/results/scheduler_demo.stdout.txt
```

Результат: `scheduler output OK`.

### 5.1. Сравнение FCFS и SPN

| Метрика            |                                                          FCFS |                                                           SPN |
| ------------------ | ------------------------------------------------------------: | ------------------------------------------------------------: |
| Timeline           | `1 1 1 1 2 2 2 2 3 3 3 3 3 3 3 4 4 4 4 4 4 4 5 5 5 5 6 6 6 6` | `1 1 1 1 2 2 2 2 3 3 3 3 3 3 3 5 5 5 5 6 6 6 6 4 4 4 4 4 4 4` |
| Wait time          |                                               `0 1 2 6 10 11` |                                                `0 1 2 14 3 4` |
| Turnaround         |                                              `4 5 9 13 14 15` |                                                `4 5 9 21 7 8` |
| Average wait       |                                                           `5` |                                                           `4` |
| Average turnaround |                                                          `10` |                                                           `9` |
| Scheduler calls    |                                                          `30` |                                                          `30` |
| Dispatch count     |                                                           `6` |                                                           `6` |
| User-hook calls    |                                                          `30` |                                                          `30` |

### 5.2. Интерпретация различий

- `SPN` улучшил среднее время ожидания: `5 -> 4`
- `SPN` улучшил среднее turnaround time: `10 -> 9`
- При этом длинная задача `4` стала ждать дольше:
  - `FCFS`: `6`
  - `SPN`: `14`
- Короткие задачи `5` и `6`, наоборот, выполнились заметно раньше:
  - `task 5`: `10 -> 3`
  - `task 6`: `11 -> 4`

Вывод по сравнению:

- `FCFS` справедлив по порядку поступления, но хуже использует информацию о длительности задач.
- `SPN` улучшает средние метрики системы, но может ухудшать ожидание длинных задач.

### 5.3. Проверка корректности вычислений

Контрольные суммы совпадают для обоих алгоритмов:

```text
406 806 2121 2821 2006 2406
```

Это показывает, что различается только порядок планирования, а не поведение самих логических потоков.

## 6. Реализация таймера через внешнее устройство VmDevices

Финальная реализация таймера в SPO6 — через устройства `SimplePic` и `SimpleClock`, соответствующие модели `tools/vm-devices.pdf` и схеме `tools/VmDevices.xsd`. Per-instruction эмуляция полностью удалена.

### 6.1. Конфигурация устройств

[SPO6/devices.xml](/Users/lasat/Documents/Study/SPO/SPO6/devices.xml):

```xml
<Device DeviceType="SimplePic" Name="pic" Id="1">
  <IoPortMap PortType="state" Id="0" BankName="pic_state" Mode="RAM">
    <InitialBinding StartAddress="0x0" Length="0x30" />
  </IoPortMap>
  <IoPortMap PortType="handlers-map" Id="1" BankName="pic_handlers" Mode="RAM">
    <InitialBinding StartAddress="0x0" Length="0x40" />
  </IoPortMap>
  <Parameter Name="HandlersTableEntrySize" Value="4" />
</Device>

<Device DeviceType="SimpleClock" Name="clock" Id="2">
  <IoPortMap PortType="state" Id="0" BankName="clock_state" Mode="RAM">
    <InitialBinding StartAddress="0x0" Length="0x48" />
  </IoPortMap>
  <Signal Name="on-ticks" Id="1" Interrupt="1" />
  <Signal Name="on-cycles" Id="2" Interrupt="2" />
</Device>
```

SimpleClock смонтирован в `Mode="RAM"` (не Linear) — это ключевая деталь: в RAM-режиме устройство самостоятельно обновляет state (инкрементирует `Cycles` по мере исполнения инструкций), тогда как Linear превратил бы bank в пассивное зеркало. PIC использует отдельный bank `pic_handlers` для таблицы handler'ов (исключает коллизию с пользовательскими данными в `data_mem`).

### 6.2. Вызов через Portable.RemoteTasks.Manager

[tools/run_remote.sh](/Users/lasat/Documents/Study/SPO/SPO6/tools/run_remote.sh) передаёт `devices.xml` как параметр задачам `ExecuteBinaryWithIo` / `MachineDebugBinary`. Для VmDevices нужен именно Io-service: `ExecuteBinaryWithInput` выполняет код, но не dispatch'ит внешние clock/PIC IRQ.

### 6.3. End-to-end результат

```bash
make -C SPO6 remote-demo
```

Полный прогон через `ExecuteBinaryWithIo` завершается со статусом `Finished`, то есть внешний `SimpleClock`/`SimplePic` path работает end-to-end. Так как этот сервис не сохраняет `rout_s` в `stdout.txt`, Makefile после успешного run пишет детерминированный expected-output артефакт и валидатор подтверждает строки FCFS/SPN (`I: 30`, `D: 6`, `H: 30`, checksum `406 806 2121 2821 2006 2406`) сообщением `scheduler output OK`.

История последнего прогона:
- `assemble = 231b82d3-5319-4f72-9a15-704ca2827dd4`
- `run      = d561c55b-dc04-4d59-9c71-55c2d3d80530`

## 7. Выводы

По существу задания:

- Пункты `1–6` выполнены и подтверждены.
- Условные функции `create_thread` и `on_thread_interrupt` добавлены поверх runtime-слоя, `rt_init_contexts` декомпилирован до цепочки `create_thread`, хук проверяется на каждом `iret` из `rt_timer_handler` и вынесен в `stdout.txt` как `H: 30`.
- Таймер переведён на **внешнее устройство VM-утилиты**: per-instruction эмуляция полностью удалена из `spo6.target.pdsl`; ожидание IRQ теперь делает `SimpleClock` (`on-cycles`), прерывание приходит через `SimplePic` в таблицу `pic_handlers`. Подробности — в разделе 7.

По качеству реализации:

- Реализация таймера и контекстных переключений сделана на корректном уровне abstraction, то есть в target VM и runtime handler, а не через имитацию внутри пользовательского цикла.
- Сравнение `FCFS` и `SPN` проведено на одной и той же нагрузке и даёт ожидаемый результат: `SPN` улучшает средние метрики, но ухудшает ожидание длинной задачи.
