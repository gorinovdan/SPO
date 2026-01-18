# SPO3 — формирование линейного кода

## Что реализовано
- Генерация линейного кода (ассемблерного листинга) по CFG.
- Описание ВМ и набора инструкций для целевой архитектуры.
- Проверка листингов через утилиту запуска из `tools` (RemoteTasks).
- Опциональный экспорт AST/CFG (наследуется из SPO2).

## Структура проекта
- `codegen/linear_code.h`, `codegen/linear_code.c` — генерация линейного кода.
- `vm/spec.md`, `vm/spec.json` — описание ВМ и набора инструкций.
- `tools/run.bat` — сборка/запуск листинга через RemoteTasks.
- `main.c` — CLI: парсинг → CFG → линейный код.
- `Validation.md` — примеры всех запусков.

## Сборка
Нужны `flex`, `bison`, компилятор C (gcc/clang). Для Windows можно использовать `app.exe`.

```bash
make -C SPO3 build
```

## Запуск (через RemoteTasks)
Все примеры ниже выполняются из корня репозитория в PowerShell.

Общий шаблон:
```powershell
.\SPO3\app.exe -o .\SPO3\results\<name>.asm .\SPO3\tests\<name>.txt
.\tools\run.bat .\SPO3\results\<name>.asm .\tools\vm_input.txt exec `
  .\SPO3\results\<name>.ptptb .\SPO3\results\<name>.stdout.txt .\SPO3\results\<name>.trace.txt
```

Опциональный вывод графов:
```powershell
.\SPO3\app.exe --cfg --cfg-dir .\SPO3\results -o .\SPO3\results\output.asm .\SPO3\tests\spo3_demo.txt
```

## Примеры запусков
Полный набор примеров находится в `SPO3/Validation.md`. Ключевые сценарии:

### spo3_demo.txt
```powershell
.\SPO3\app.exe -o .\SPO3\results\spo3_demo.asm .\SPO3\tests\spo3_demo.txt
.\tools\run.bat .\SPO3\results\spo3_demo.asm .\tools\vm_input.txt exec `
  .\SPO3\results\spo3_demo.ptptb .\SPO3\results\spo3_demo.stdout.txt .\SPO3\results\spo3_demo.trace.txt
```

### array_demo.txt
```powershell
.\SPO3\app.exe -o .\SPO3\results\array_demo.asm .\SPO3\tests\array_demo.txt
.\tools\run.bat .\SPO3\results\array_demo.asm .\tools\vm_input.txt exec `
  .\SPO3\results\array_demo.ptptb .\SPO3\results\array_demo.stdout.txt .\SPO3\results\array_demo.trace.txt
```
Ожидаемый вывод в `SPO3\results\array_demo.stdout.txt`:
```
05 04
```

### vm_instructions.asm
```powershell
.\tools\run.bat .\SPO3\tests\vm_instructions.asm .\tools\vm_input.txt exec `
  .\SPO3\results\vm_instructions.ptptb .\SPO3\results\vm_instructions.stdout.txt .\SPO3\results\vm_instructions.trace.txt
```
Ожидаемый вывод в `SPO3\results\vm_instructions.stdout.txt`:
```
OK
```

### calculator.txt
```powershell
.\SPO3\app.exe -o .\SPO3\results\calculator.asm .\SPO3\tests\calculator.txt
.\tools\run.bat .\SPO3\results\calculator.asm .\SPO3\tests\calculator_input.txt exec `
  .\SPO3\results\calculator.ptptb .\SPO3\results\calculator.stdout.txt .\SPO3\results\calculator.trace.txt
```
Ожидаемый вывод в `SPO3\results\calculator.stdout.txt`:
```
4
```

## Выходные файлы
- `*.asm` — ассемблерный листинг.
- `*.ptptb` — бинарный модуль после сборки в RemoteTasks.
- `*.stdout.txt` — вывод программы.
- `*.trace.txt` — трассировка исполнения.
- `*.dgml` — опциональные AST/CFG графы.

## Примечания
- `tools\run.bat` использует `SPO3\spo3.target.pdsl` и `archName vm32`.
- Для функций (кроме `main`) требуется `RETF`.
- Если `SPO3\app.exe` отсутствует, соберите проект вручную (gcc с ключом `-fcommon`).
