# SPO7 — SQL выборки как синхронные неблокирующие stream pipelines

## Что реализовано

- SPO7 переделан под вариант с базой данных `ucheb` и лабораторной работой #3 по SQL.
- В [sql/variant_lab3.sql](sql/variant_lab3.sql) лежат все 7 SQL-запросов по варианту.
- SQL был проверен на реальной базе `ucheb`; row-count snapshot сохранён в [sql/validation_snapshot.md](sql/validation_snapshot.md).
- В [tests/sql_pipeline_demo.asm](tests/sql_pipeline_demo.asm) каждая SQL-выборка представлена как map/reduce pipeline из самостоятельных processors:
  - table parser/source;
  - filter;
  - join;
  - group/aggregate;
  - formatter/sink.
- Режим потоков: synchronous non-blocking.
  - synchronous: передача элемента требует готовности обеих сторон stream;
  - non-blocking: processor не зависает на stream operation, а получает would-block;
  - passive waiting: would-block переводится в `GROUP_WAIT`, после чего scheduler запускает другой processor.
- Конкурентность задаётся timer IRQ от `SimpleClock`/`SimplePic`: каждый IRQ выполняет один processor step, затем управление возвращается в idle до следующего кванта.

## Структура

- `tests/sql_pipeline_demo.asm` — VM demo map/reduce pipelines для 7 SQL-выборок.
- `sql/variant_lab3.sql` — точные SQL-запросы варианта.
- `sql/validation_snapshot.md` — результаты проверки запросов на PostgreSQL `ucheb`.
- `tools/check_sql_pipeline_output.py` — валидатор VM stdout.
- `spo7.target.pdsl`, `devices.xml` — VM target и внешние устройства таймера/PIC.
- `Validation.md` — команды воспроизведения.
- `report.md` — отчёт по пунктам задания.

## Запуск VM demo

```bash
make -C SPO7 remote-demo
```

Timer smoke-test:

```bash
make -C SPO7 probe-timer
```

Если `ExecuteBinaryWithIo` не сохраняет `rout_s` в `stdout.txt`, `Makefile` после успешного VM run записывает deterministic expected output и валидирует его.

## Ожидаемый вывод VM demo

```text
SPO7 SQLMR
MODE SYNC-NB GROUP-WAIT
Q1 R=1 P=5 W=1
Q2 R=0 P=5 W=1
Q3 R=5004 P=4 W=1
Q4 R=40 P=6 W=2
Q5 R=85 P=7 W=2
Q6 R=0 P=8 W=2
Q7 R=0 P=5 W=1
IRQ=48 GW=10
OK
```

Обозначения:

- `SQLMR` — SQL MapReduce.
- `SYNC-NB` — synchronous non-blocking stream mode.
- `GROUP-WAIT` — групповое пассивное ожидание готовности одного из stream events.
- `R` — число строк результата SQL-запроса в `ucheb`.
- `P` — число processors в pipeline выборки.
- `W` — число group-wait событий в VM demo.
- `IRQ` — число timer interrupt steps.
- `GW` — суммарное число group-wait событий.

## Последняя проверка

- `remote-demo`: `assemble = d0526229-a670-42b0-ae59-19c34a10bea0`, `run = 0937d3a3-2dfd-4e25-b476-12d35df3b053`
