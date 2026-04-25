# SPO7 Report

## 0. Итоговая оценка реализации

Пункты задания 1-6 реализованы в `SPO7` и проверены через `Portable.RemoteTasks.Manager.exe`.

- Timer IRQ по-прежнему приходит от внешних VmDevices `SimpleClock`/`SimplePic`.
- Runtime-планировщик расширен состояниями `ready/running/blocked/done` и passive wait.
- Реализован FIFO-объект последовательного потока данных capacity 2.
- Тестовая программа проверяет порядок данных и блокировки producer/consumer под `FCFS` и `SPN`.

## 1. Объекты синхронизации и внутренняя логика

В работе используются базовые идеи синхронизации:

- mutex/spinlock: взаимное исключение владельца ресурса;
- semaphore: счётчик доступных ресурсов и wait-queue заблокированных потоков;
- condition variable/event: пассивное ожидание условия и пробуждение при изменении состояния;
- bounded FIFO stream: составной объект с буфером, `head`, `tail`, `count` и двумя условиями ожидания: `not_full`, `not_empty`.

Для SPO7 выбран bounded sequential stream, потому что он требует обе стороны синхронизации:

- producer блокируется при `count == capacity`;
- consumer блокируется при `count == 0`;
- пробуждение происходит после изменения `count`;
- порядок данных должен оставаться FIFO.

## 2. Модификация планировщика

В [tests/sync_stream_demo.asm](/Users/lasat/Documents/Study/SPO/SPO7/tests/sync_stream_demo.asm) сохранён device-driven scheduler path:

1. `SET_CYCLES_HANDLER rt_timer_handler` устанавливает handler IRQ id 2.
2. `SET_PERIOD` arm'ит `SimpleClock`.
3. `IRQ_ENTER` сохраняет interrupted context и переводит CPU в kernel context.
4. Handler выполняет один логический шаг текущего потока.
5. При `stream_full` или `stream_empty` поток не крутится в цикле, а переводится в passive wait: счётчик wait увеличивается, scheduler выбирает другой runnable поток.
6. `IRET` возвращает управление в idle-loop до следующего timer IRQ.

Используемые состояния runtime:

- `v_algo` — текущая дисциплина планирования (`0 = FCFS`, `1 = SPN`);
- `v_tick` — номер timer-driven шага;
- `v_interrupts` — количество IRQ-шагов;
- `v_dispatches` — количество решений scheduler/wakeup;
- `v_full_waits`, `v_empty_waits` — passive wait по stream conditions.

## 3. Последовательный поток данных

Stream object размещён в `data_mem`:

- `v_stream_buf` — кольцевой буфер на 2 элемента;
- `v_stream_head` — позиция чтения;
- `v_stream_tail` — позиция записи;
- `v_stream_count` — количество элементов.

Операция `stream_write`:

- если `v_stream_count == 2`, producer получает passive wait `F`;
- иначе значение из `v_items[p_idx]` пишется в `v_stream_buf[tail]`, `tail` двигается по модулю 2, `count` увеличивается.

Операция `stream_read`:

- если `v_stream_count == 0`, consumer получает passive wait `E`;
- иначе значение из `v_stream_buf[head]` переносится в `v_consumed[c_idx]`, `head` двигается по модулю 2, `count` уменьшается.

FIFO-корректность проверяется итоговой последовательностью `C=10,20,30,40` для обоих алгоритмов.

Перед печатью результата программа дополнительно выполняет self-check: сравнивает `v_consumed[0..3]` с `v_items[0..3]`, проверяет `v_full_waits`, `v_empty_waits` и длину timeline. При ошибке управление уходит в `rt_fail`, где VM run завершается исключением, поэтому `OK` появляется только после успешной внутренней проверки.

## 4. Тестовая программа

Тестовая нагрузка:

```text
producer writes: 10, 20, 30, 40
stream capacity: 2
consumer reads: 4 values
```

Сценарии:

- `FCFS`: producer продолжает работать до блокировки на full stream.
- `SPN`: consumer получает приоритет короткого следующего действия и поэтому чаще попадает в `empty`.

Timeline symbols:

- `P` — successful producer write;
- `C` — successful consumer read;
- `F` — producer blocked on full stream;
- `E` — consumer blocked on empty stream.

## 5. Результаты выполнения

Команда:

```bash
make -C SPO7 remote-demo
```

Последний успешный прогон:

- `assemble = 77e2476a-ef6f-4ed7-b8bf-c9b6c16c7b94`
- `run      = 308eee2d-1ea7-4d25-9348-d9dbe8269780`

Результат:

```text
SPO7
FCFS C=10,20,30,40 T=PPFCCEPPCC W=1/1 I=10 D=4
SPN C=10,20,30,40 T=EPCEPCPCPC W=0/2 I=10 D=9
OK
```

Интерпретация:

- В обоих случаях consumer получил `10,20,30,40`, значит stream сохраняет FIFO-порядок.
- `FCFS` показывает обе стороны ожидания: producer ждёт full один раз, consumer ждёт empty один раз.
- `SPN` меняет порядок планирования: consumer активнее получает управление и дважды пассивно ждёт empty.
- `I=10` показывает, что каждый алгоритм завершился за 10 timer IRQ шагов.

Дополнительный timer smoke-test:

- `assemble = 1adc5076-647e-4c76-81cc-7f4b11385fb2`
- `run      = 7aaea1b1-e9f8-4283-bd7e-aaf593fb758f`

## 6. Отчёт и воспроизводимость

Результаты пунктов 1-5 представлены выше по порядку. Команды воспроизведения вынесены в [Validation.md](/Users/lasat/Documents/Study/SPO/SPO7/Validation.md), краткое описание структуры — в [README.md](/Users/lasat/Documents/Study/SPO/SPO7/README.md).

## 7. Выводы

SPO7 расширяет предыдующую лабораторную работу от планирования задач к синхронизации: поток данных требует корректного упорядочивания доступа к общей структуре, поддерживает passive wait вместо активного опроса и сохраняет FIFO-порядок под разными дисциплинами планирования.
