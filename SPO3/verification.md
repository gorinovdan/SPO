# Проверка SPO3

Все команды запускайте из корня репозитория (`/Users/lasat/Documents/Study/SPO`), либо замените пути на свои.

## Сборка
```bash
make -C SPO3 build
```

## Тест покрытия инструкций ВМ
```bash
make -C SPO3 vm-test
```
Ожидаемый вывод: `OK`.

## Демо из задания
```bash
make -C SPO3 vm-demo
```
Вывод идет в `SPO3/results/output.asm` и `SPO3/results/output.bin`.

## Запуск tests/input.txt
```bash
make -C SPO3 vm-input
```
Вывод идет в `SPO3/results/output_input.asm` и `SPO3/results/output_input.bin`.

## Доп. демо по массивам
```bash
./SPO3/tools/run_vm.sh ./SPO3/tests/array_demo.txt ./SPO3/results/array_demo.asm ./SPO3/results/array_demo.bin
```
Ожидаемый вывод:
```
5
4
```

## Полная проверка (все шаги одной командой)
```bash
make -C SPO3 build \
  && make -C SPO3 vm-test \
  && make -C SPO3 vm-demo \
  && ./SPO3/tools/run_vm.sh ./SPO3/tests/array_demo.txt ./SPO3/results/array_demo.asm ./SPO3/results/array_demo.bin
```

## Проверка своего исходника
```bash
./SPO3/tools/run_vm.sh <input.txt> <out.asm> <out.bin>
```
Пример:
```bash
./SPO3/tools/run_vm.sh ./SPO3/tests/spo3_demo.txt ./SPO3/results/custom.asm ./SPO3/results/custom.bin
```

## Опционально: вывод графов CFG/AST
```bash
./SPO3/app --cfg --cfg-dir ./SPO3/results -o ./SPO3/results/output.asm ./SPO3/tests/spo3_demo.txt
```
