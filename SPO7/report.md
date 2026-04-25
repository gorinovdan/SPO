# SPO7 Report

## 0. Итоговая оценка реализации

SPO7 вариант: режим `синхронный, неблокирующий`, SQL-выборки по лабораторной работе #3 для базы `ucheb`, stream/map-reduce декомпозиция и group-wait passive waiting.

Сделано:

- составлены 7 SQL-запросов в [variant_lab3.sql](/Users/lasat/Documents/Study/SPO/SPO7/sql/variant_lab3.sql);
- SQL проверен на `psql -h pg -d ucheb`;
- каждая выборка разложена на processors pipeline;
- VM demo [sql_pipeline_demo.asm](/Users/lasat/Documents/Study/SPO/SPO7/tests/sql_pipeline_demo.asm) моделирует конкурентное выполнение processors через timer IRQ;
- non-blocking stream operation при would-block переводится в `GROUP_WAIT`;
- результат VM demo сравнен с row counts реальной PostgreSQL-выборки.

## 1. Объекты синхронизации и внутренняя логика

Основной объект синхронизации synchronous byte stream между processors.

Семантика:

- `read(stream)` в неблокирующем режиме не ждёт данные бесконечно; если данных нет, возвращает would-block;
- `write(stream)` в неблокирующем режиме не ждёт читателя бесконечно; если downstream не готов, возвращает would-block;
- synchronous stream не хранит большую очередь: передача элемента считается успешной, когда producer и consumer согласованы;
- group wait ждёт группу событий, например “готов любой входной stream” или “готов любой выходной stream”.

Внутренняя логика в VM demo:

- `v_stage_counts[q]` задаёт число processors в pipeline выборки `q`;
- `v_wait_counts[q]` задаёт число simulated would-block событий;
- каждый would-block увеличивает `v_group_waits` и `v_dispatches`;
- scheduler не блокирует всю машину, а отдаёт следующий timer slice другому processor step.

## 2. Модификация планировщика

Планировщик сохранён timer-driven, как в SPO6:

1. `SimpleClock` создаёт timer IRQ.
2. `SimplePic` передаёт управление в `rt_timer_handler`.
3. `IRQ_ENTER` сохраняет interrupted context и переводит CPU в kernel context.
4. Handler выполняет один processor step.
5. Если stream operation вернула would-block, фиксируется `GROUP_WAIT`.
6. `IRET` возвращает управление в idle-loop до следующего IRQ.

Вытеснение обеспечивается внешним таймером: processor не выполняется “до конца”, а получает короткий квант на каждый IRQ. Это показывает конкурентность pipeline: разные stages могут продвигаться независимо, а ожидание stream readiness пассивное.

Количество processors можно менять через descriptor arrays:

- `v_stage_counts` — сколько processors запускается для каждой выборки;
- `v_wait_counts` — сколько group-wait событий ожидается для конкретной topology.

## 3. Последовательные byte streams

Каждый relational operator представлен как processor:

- source/parser читает raw table stream;
- filter пропускает только записи по условию;
- join принимает два входных stream и порождает joined stream;
- group/aggregate собирает группы и считает агрегаты;
- formatter пишет результат в output stream.

В терминах map-reduce:

- map stages: parser, projection, filter, mark conversion;
- shuffle/join stages: join по ключу, repartition по group key;
- reduce stages: `COUNT`, `AVG`, `HAVING`, duplicate elimination через `GROUP BY`;
- sink stage: formatter.

Все stages общаются только через последовательные byte streams и параметры: имена входов/выходов, ключи соединения, константы фильтров, номер группы, дата, expected comparison value.

## 4. SQL-запросы и декомпозиция по варианту

Точные SQL-запросы находятся в [variant_lab3.sql](/Users/lasat/Documents/Study/SPO/SPO7/sql/variant_lab3.sql).

| Query | SQL смысл                                                   |                                                              Pipeline processors | SQL rows |
| ----- | ----------------------------------------------------------- | -------------------------------------------------------------------------------: | -------: |
| Q1    | `Н_ТИПЫ_ВЕДОМОСТЕЙ RIGHT JOIN Н_ВЕДОМОСТИ`, фильтры по `ИД` |          type parser, sheet parser, type filter, sheet filter, right join/format |        1 |
| Q2    | `Н_ЛЮДИ INNER JOIN Н_ОБУЧЕНИЯ INNER JOIN Н_УЧЕНИКИ`         |           people parser, edu parser, students parser, filters, inner join/format |        0 |
| Q3    | число пар `ФАМИЛИЯ, ИМЯ` без `DISTINCT`                     |                     people parser, key mapper, group by reducer, count formatter |     5004 |
| Q4    | планы с ровно 2 группами на кафедре ВТ                      |               groups parser, plans parser, dept filter, join, group/count/having |       40 |
| Q5    | средние оценки группы 4100 выше средней группы 1101         | students/people/sheets parsers, mark mapper, joins, AVG reducers, compare/format |       85 |
| Q6    | зачисленные до `2012-09-01` на 1 курс заочной формы, с `IN` |        students/people/edu/plans/form parsers, IN subquery, filters, join/format |        0 |
| Q7    | число отличников группы 3100                                |     students/sheets parsers, mark mapper, group by student, `MIN(mark)=5`, count |        0 |

Q2, Q6 и Q7 дают пустой результат на реальной базе с точными константами варианта. Это зафиксировано в [validation_snapshot.md](/Users/lasat/Documents/Study/SPO/SPO7/sql/validation_snapshot.md), а VM demo отражает это как `R=0`.

## 5. Результаты выполнения

Команда:

```bash
make -C SPO7 remote-demo
```

Последний успешный VM run:

- `assemble = d0526229-a670-42b0-ae59-19c34a10bea0`
- `run      = 0937d3a3-2dfd-4e25-b476-12d35df3b053`

VM output:

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

Где:

- `R` — число строк SQL-результата в PostgreSQL `ucheb`;
- `P` — число processors в pipeline;
- `W` — число group-wait событий;
- `IRQ=48` — число timer-driven квантов;
- `GW=10` — суммарное число passive group waits.

## 6. Отчёт и воспроизводимость

Команды запуска VM и SQL вынесены в [Validation.md](/Users/lasat/Documents/Study/SPO/SPO7/Validation.md). Краткое описание структуры находится в [README.md](/Users/lasat/Documents/Study/SPO/SPO7/README.md).

Проверки:

- `make -C SPO7 remote-demo`;
- `python3 SPO7/tools/check_sql_pipeline_output.py SPO7/results/sql_pipeline_demo.stdout.txt`;
- `psql -h pg -d ucheb -f SPO7/sql/variant_lab3.sql`.

## 7. Выводы

В SPO7 SQL-выборки представлены как набор конкурентных processors, связанных synchronous non-blocking byte streams. Синхронизация происходит на границах stream operations: если stage не может прочитать или записать элемент, он не ждёт активно, а отдаёт управление через group wait. Это соответствует требованию пассивного ожидания в неблокирующем режиме и позволяет менять pipeline parallelism через количество processors.
