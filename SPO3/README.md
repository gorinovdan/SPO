# SPO3 — линейный код для стековой ВМ

## Что реализовано
- Формирование линейного кода (ассемблерного листинга) по CFG.
- Описание виртуальной машины и набор мнемоник (stack-based VM).
- Ассемблер и эмулятор для проверки результата.
- Опциональный экспорт AST/CFG (наследуется из SPO2).

## Структура проекта
- `codegen/linear_code.h`, `codegen/linear_code.c` — генерация линейного кода.
- `vm/spec.md`, `vm/spec.json` — описание ВМ и набора инструкций.
- `tools/asm.py`, `tools/vm.py` — ассемблер и эмулятор.
- `tools/run_vm.sh` — сборка, ассемблирование и запуск.
- `main.c` — CLI: парсинг → CFG → линейный код.

## Сборка
Нужны `flex`, `bison`, компилятор C (gcc/clang) и Python 3.

```bash
make -C SPO3 build
```

## Запуск
Генерация листинга:
```bash
./SPO3/app -o ./SPO3/results/output.asm ./SPO3/tests/spo3_demo.txt
```

Генерация листинга и запуск на ВМ:
```bash
./SPO3/tools/run_vm.sh ./SPO3/tests/spo3_demo.txt ./SPO3/results/output.asm ./SPO3/results/output.bin
```

Опциональный вывод графов:
```bash
./SPO3/app --cfg --cfg-dir ./SPO3/results -o ./SPO3/results/output.asm ./SPO3/tests/spo3_demo.txt
```

## Тестовые команды
```bash
make -C SPO3 vm-test
make -C SPO3 vm-demo
make -C SPO3 vm-input
```

## Выходные файлы
- `output.asm` — ассемблерный листинг (секция констант, данных и кода).
- `output.bin` — бинарный модуль ВМ (после ассемблирования).
- `*.dgml` — опциональные AST/CFG графы.

## Примеры
- Исходники: `SPO3/tests/spo3_demo.txt`, `SPO3/tests/array_demo.txt`
- Готовые артефакты: `SPO3/results/*`

## Примечания
- Для массива параметры передаются по ссылке, элементы индексируются через `INDEX`/`RANGE_OP`.
- Если тип аргумента не указан, по умолчанию используется размер 4 байта.
