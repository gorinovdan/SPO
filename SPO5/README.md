# SPO5 — пользовательские типы, override и интерфейсы

## Что реализовано
- Пользовательские типы `type` с полями и методами.
- Прямое наследование членов через `extends`.
- Интерфейсы `interface` и реализация через `implements`.
- Переопределение методов через `override`.
- Членный доступ `obj.field` и вызовы `obj.method(...)`.
- Типизированные локальные объявления `name of Type;` и `name of Type = expr;`.
- Генерация линейного кода с виртуальной диспетчеризацией через сгенерированные dispatcher-подпрограммы.
- Метаданные типов и символов в `[section data_meta]`.
- Локальный инспектор `tools/vm_inspector.py`, умеющий выводить поля значений пользовательских типов.

## Поддерживаемый синтаксис

```text
interface Printer
    def describe() of int;
end

type Shape
    value of int;

    def describe() of int
        result = self.value;
    end
end

type FancyShape extends Shape implements Printer
    extra of int;

    override def describe() of int
        result = self.value + self.extra;
    end
end
```

Локальные типизированные переменные:

```text
shape of Shape;
printer of Printer;
printer = shape;
```

## Структура проекта
- `ast/*` — AST и парсер расширенного языка.
- `analysis/ir.*` — IR для полей, методов и типизированных объявлений.
- `cfg/*` — семантическая модель типов, наследования, интерфейсов, dispatcher-ов и CFG.
- `codegen/*` — генерация линейного кода и метаданных `data_meta`.
- `tools/asm.py`, `tools/vm.py` — локальный ассемблер и VM с поддержкой `data_meta`.
- `tools/vm_inspector.py` — консольный инспектор.
- `tools/run_remote.bat` — запуск через `tools/Portable.RemoteTasks.Manager.exe` и `spo5.target.pdsl`.
- `tools/run_remote.sh` — тот же сценарий для macOS/Linux через `mono`.

## Сборка

```bash
make -C SPO5 build
```

## Локальная проверка

Интеграционный demo с `override + interface`:

```bash
make -C SPO5 vm-types
```

Ожидаемый вывод:

```text
111105
```

Инспектор по тому же demo:

```bash
make -C SPO5 inspect-types
```

Ожидаемые строки включают:

```text
local base: Shape{value=5}
local fancy: FancyShape{value=7, extra=4}
local view: FancyShape{value=7, extra=4}
local iface: FancyShape{value=7, extra=4}
```

Регрессия по старым сценариям:

```bash
./SPO5/tools/run_vm.sh ./SPO5/tests/array_demo.txt ./SPO5/results/array_demo.asm ./SPO5/results/array_demo.bin
./SPO5/tools/run_vm.sh ./SPO5/tests/spo3_demo.txt ./SPO5/results/spo3_demo.asm ./SPO5/results/spo3_demo.bin
make -C SPO5 vm-test
```

## RemoteTasks

Подготовлен отдельный target-файл:

- `SPO5/spo5.target.pdsl`

Готовый bat-скрипт для Windows:

```powershell
.\SPO5\tools\run_remote.bat .\SPO5\results\types_demo.asm .\tools\vm_input.txt exec `
  .\SPO5\results\types_demo.ptptb .\SPO5\results\types_demo.stdout.txt .\SPO5\results\types_demo.trace.txt
```

Предварительно сгенерируйте asm:

```powershell
.\SPO5\app.exe -o .\SPO5\results\types_demo.asm .\SPO5\tests\types_demo.txt
```

Для macOS/Linux доступен прямой запуск того же `.exe` через `mono`:

```bash
make -C SPO5 remote-types
```

Или вручную:

```bash
mono ./tools/Portable.RemoteTasks.Manager.exe ...
./SPO5/tools/run_remote.sh ./SPO5/results/types_demo.asm ./tools/vm_input.txt exec \
  ./SPO5/results/types_demo.remote.ptptb \
  ./SPO5/results/types_demo.remote.stdout.txt \
  ./SPO5/results/types_demo.remote.trace.txt
```

Важно: remote `stdout.txt` у целевой VM хранит сырые байты, а не форматированное десятичное число. Для `types_demo` в trace видно вычисленное значение `0x1b201`, то есть `111105`, а в `stdout.txt` попадает младший байт `0x01`.
