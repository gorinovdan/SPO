# SPO2 — граф потока управления (CFG)

## Что реализовано
- Построение графа потока управления по AST, полученному в SPO1.
- Построение дерева операций (IR) для выражений и присваиваний в каждом базовом блоке.
- Экспорт CFG и графа вызовов в DGML.
- Тестовая программа с поддержкой нескольких входных файлов и опционального каталога вывода.

## Структура проекта
- `analysis/ir.h`, `analysis/ir.c` — узлы IR и преобразование выражений AST → IR.
- `cfg/cfg.h`, `cfg/cfg.c` — структуры CFG и построение графа.
- `view/cfg_dgml.h`, `view/cfg_dgml.c` — вывод CFG/IR в DGML.
- `view/dgml.*` — экспорт AST (используется для сравнения).
- `main.c` — CLI-инструмент, сбор AST + CFG + call graph.

## Сборка
Нужны `flex`, `bison` и компилятор C (gcc/clang).

```bash
make -C SPO2 build
```

## Запуск
```bash
./SPO2/app [-o output_dir] <input_files...>
```

Пример:
```bash
./SPO2/app -o ./SPO2/results ./SPO2/tests/input.txt ./SPO2/tests/control_flow_big.txt
```

Поддерживается режим совместимости:
```bash
./SPO2/app <input_files...> <output_dir>
```

## Выходные файлы
- `ast.<source>.dgml` — дерево разбора.
- `<source>.<function>.dgml` — CFG для каждой подпрограммы.
- `fun.calls.graph.dgml` — граф вызовов.
- `cfg.dgml` — сводный граф по всем подпрограммам.

Ошибки анализатора выводятся в `stderr` с координатами строки/столбца.

## Примеры
- Входные тесты: `SPO2/tests/input.txt`, `SPO2/tests/control_flow_big.txt`
- Готовые результаты: `SPO2/results`

## Примечания
- Для Windows можно использовать проект Visual Studio: `SPO2/SPO.vcxproj`.
