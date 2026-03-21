# Проверка SPO5

Все команды выполняются из корня репозитория.

## Сборка

```bash
make -C SPO5 build
```

## Базовая регрессия по ВМ

```bash
make -C SPO5 vm-test
```

Ожидаемый вывод:

```text
797510
```

Это локальная форма строк `79 75 10` (`'O'`, `'K'`, `'\n'`) в Python-VM, потому что `OUT` выводит числовые значения ячеек.

## Новый интеграционный сценарий по SPO5

```bash
make -C SPO5 vm-types
```

Ожидаемый вывод:

```text
111105
```

## Проверка инспектора

```bash
make -C SPO5 inspect-types
```

Ожидаемый вывод содержит:

```text
local base: Shape{value=5}
local fancy: FancyShape{value=7, extra=4}
local view: FancyShape{value=7, extra=4}
local iface: FancyShape{value=7, extra=4}
```

## Регрессия по старому функционалу

```bash
./SPO5/tools/run_vm.sh ./SPO5/tests/array_demo.txt ./SPO5/results/array_demo.asm ./SPO5/results/array_demo.bin
./SPO5/tools/run_vm.sh ./SPO5/tests/spo3_demo.txt ./SPO5/results/spo3_demo.asm ./SPO5/results/spo3_demo.bin
```

Для `array_demo.txt` локальная VM печатает:

```text
54
```

## Подготовка к RemoteTasks

1. Сгенерировать asm:

```powershell
.\SPO5\app.exe -o .\SPO5\results\types_demo.asm .\SPO5\tests\types_demo.txt
```

2. Запустить через `Portable.RemoteTasks.Manager.exe`:

```powershell
.\SPO5\tools\run_remote.bat .\SPO5\results\types_demo.asm .\tools\vm_input.txt exec `
  .\SPO5\results\types_demo.ptptb .\SPO5\results\types_demo.stdout.txt .\SPO5\results\types_demo.trace.txt
```

Используемый target:

```text
SPO5/spo5.target.pdsl
```

### Повторный запуск на macOS/Linux

Тот же сценарий можно выполнить через `mono`:

```bash
make -C SPO5 remote-types
```

или:

```bash
./SPO5/tools/run_remote.sh ./SPO5/results/types_demo.asm ./tools/vm_input.txt exec \
  ./SPO5/results/types_demo.remote.ptptb \
  ./SPO5/results/types_demo.remote.stdout.txt \
  ./SPO5/results/types_demo.remote.trace.txt
```

### Что считать корректным результатом RemoteTasks

- `stdout.txt` у целевой VM содержит не строковое десятичное представление, а сырые байты порта `OUT`.
- Для `types_demo` файл `types_demo.remote.stdout.txt` содержит один байт `0x01`.
- Корректность проверки подтверждается по `trace.txt`: в конце выполнения видно `rout_s := 0x1b201`, то есть программа вычислила значение `111105`.
