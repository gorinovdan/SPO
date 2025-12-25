# Validation SPO3 через Portable.RemoteTasks.Manager.exe

Все команды ниже предполагают запуск из корня репозитория `SPO` в PowerShell.
Промежуточные файлы сохраняются в `SPO3\results` (asm, ptptb, stdout, trace).

## Общий шаблон
1. Скомпилировать исходник SPO3 в asm:
```powershell
.\SPO3\app.exe -o .\SPO3\results\<name>.asm .\SPO3\tests\<name>.txt
```
2. Собрать asm и запустить бинарник через RemoteTasks:
```powershell
.\tools\run.bat .\SPO3\results\<name>.asm .\tools\vm_input.txt exec `
  .\SPO3\results\<name>.ptptb .\SPO3\results\<name>.stdout.txt .\SPO3\results\<name>.trace.txt
```

Для asm-тестов пропускается шаг компиляции `SPO3\app`.

## Тесты из `SPO3\tests`

### spo3_demo.txt
```powershell
.\SPO3\app.exe -o .\SPO3\results\spo3_demo.asm .\SPO3\tests\spo3_demo.txt
.\tools\run.bat .\SPO3\results\spo3_demo.asm .\tools\vm_input.txt exec `
  .\SPO3\results\spo3_demo.ptptb .\SPO3\results\spo3_demo.stdout.txt .\SPO3\results\spo3_demo.trace.txt
```

### input.txt
```powershell
.\SPO3\app.exe -o .\SPO3\results\input.asm .\SPO3\tests\input.txt
.\tools\run.bat .\SPO3\results\input.asm .\tools\vm_input.txt exec `
  .\SPO3\results\input.ptptb .\SPO3\results\input.stdout.txt .\SPO3\results\input.trace.txt
```

### array_demo.txt
```powershell
.\SPO3\app.exe -o .\SPO3\results\array_demo.asm .\SPO3\tests\array_demo.txt
.\tools\run.bat .\SPO3\results\array_demo.asm .\tools\vm_input.txt exec `
  .\SPO3\results\array_demo.ptptb .\SPO3\results\array_demo.stdout.txt .\SPO3\results\array_demo.trace.txt
```
Ожидаемый вывод в `SPO3\results\array_demo.stdout.txt`:
```
05 04 (сырые байты вывода)
```

### control_flow_big.txt
```powershell
.\SPO3\app.exe -o .\SPO3\results\control_flow_big.asm .\SPO3\tests\control_flow_big.txt
.\tools\run.bat .\SPO3\results\control_flow_big.asm .\tools\vm_input.txt exec `
  .\SPO3\results\control_flow_big.ptptb .\SPO3\results\control_flow_big.stdout.txt .\SPO3\results\control_flow_big.trace.txt
```

### vm_instructions.asm (asm-тест ВМ)
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

### calculator.asm (asm-версия)
```powershell
.\tools\run.bat .\SPO3\tests\calculator.asm .\SPO3\tests\calculator_input.txt exec `
  .\SPO3\results\calculator_asm.ptptb .\SPO3\results\calculator_asm.stdout.txt .\SPO3\results\calculator_asm.trace.txt
```
Ожидаемый вывод в `SPO3\results\calculator_asm.stdout.txt`:
```
4
```

## Примечания
- `tools\run.bat` использует `SPO3\spo3.target.pdsl` и `archName vm32`. Логин и пароль для RemoteTasks задаются внутри `tools\run.bat`.
- Если нужно увидеть пошаговую отладку, замените `exec` на `debug` (тогда будет вызван `MachineDebugBinary`).
- В asm-файлах функции (кроме `main`) должны возвращаться через `RETF`, иначе выполнение завершится на первом `RET`.
- Если `SPO3\app.exe` отсутствует, соберите его вручную (gcc с ключом `-fcommon` из-за `root` в `parser.tab.h`).
