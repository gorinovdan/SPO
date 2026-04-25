# Validation SPO7

Все команды выполняются из корня репозитория `SPO`.

## VM demo

```bash
make -C SPO7 remote-demo
```

Команда:

- копирует `tests/sql_pipeline_demo.asm` в `results/sql_pipeline_demo.asm`;
- собирает бинарный модуль через `Portable.RemoteTasks.Manager.exe`;
- запускает его через `ExecuteBinaryWithIo`, чтобы работали `SimpleClock`/`SimplePic`;
- проверяет результат через `tools/check_sql_pipeline_output.py`.

Последний успешный прогон:

- `assemble = d0526229-a670-42b0-ae59-19c34a10bea0`
- `run      = 0937d3a3-2dfd-4e25-b476-12d35df3b053`

## SQL validation

Подключение к базе:

```bash
ssh -p 2222 s338960@se.ifmo.ru
psql -h pg -d ucheb
```

Запуск SQL-файла с локальной машины:

```bash
scp -P 2222 SPO7/sql/variant_lab3.sql s338960@se.ifmo.ru:/tmp/spo7_variant_lab3.sql
ssh -p 2222 s338960@se.ifmo.ru \
  "psql -h pg -d ucheb -v ON_ERROR_STOP=1 -f /tmp/spo7_variant_lab3.sql"
```

Проверенные row counts:

```text
Q1=1
Q2=0
Q3=5004
Q4=40
Q5=85
Q6=0
Q7=0
```

## Timer smoke-test

```bash
make -C SPO7 probe-timer
```

Ранее проверенный timer probe:

- `assemble = 09ad4ab8-847b-4f8f-9c45-361a201d5b32`
- `run      = a45f0af3-db71-4c44-87f3-8daa8d72ce03`
