@echo off
setlocal EnableExtensions

set "TOOLS_DIR=%~dp0"
for %%I in ("%TOOLS_DIR%..") do set "ROOT_DIR=%%~fI"
set "SPO3_DIR=%ROOT_DIR%\SPO3"
set "EXE=%TOOLS_DIR%Portable.RemoteTasks.Manager.exe"

set "LOGIN=338960"
set "PASSWORD=550fdf73-65b4-4e66-a0b6-6579cb1336a4"
set "ARCH=vm32"
set "TARGET_FILE=%SPO3_DIR%\spo3.target.pdsl"

set "ASM_FILE=%~1"
if "%ASM_FILE%"=="" set "ASM_FILE=%SPO3_DIR%\results\output.asm"
for %%I in ("%ASM_FILE%") do set "ASM_FILE=%%~fI"

set "BIN_FILE=%~4"
if "%BIN_FILE%"=="" set "BIN_FILE=%TOOLS_DIR%out.ptptb"
for %%I in ("%BIN_FILE%") do set "BIN_FILE=%%~fI"

set "STDOUT_FILE=%~5"
if "%STDOUT_FILE%"=="" set "STDOUT_FILE=%TOOLS_DIR%stdout.txt"
for %%I in ("%STDOUT_FILE%") do set "STDOUT_FILE=%%~fI"

set "TRACE_FILE=%~6"
if "%TRACE_FILE%"=="" set "TRACE_FILE=%TOOLS_DIR%trace.txt"
for %%I in ("%TRACE_FILE%") do set "TRACE_FILE=%%~fI"

set "INPUT_FILE=%~2"
if "%INPUT_FILE%"=="" set "INPUT_FILE=%TOOLS_DIR%vm_input.txt"
for %%I in ("%INPUT_FILE%") do set "INPUT_FILE=%%~fI"
if not exist "%INPUT_FILE%" echo 0> "%INPUT_FILE%"

set "RUN_MODE=%~3"
if "%RUN_MODE%"=="" set "RUN_MODE=debug"

set "ASM_ID="
set "ASM_ID_FILE=%TOOLS_DIR%asm_id.txt"
"%EXE%" -ul %LOGIN% -up %PASSWORD% -s Assemble -id -w definitionFile "%TARGET_FILE%" archName %ARCH% asmListing "%ASM_FILE%" > "%ASM_ID_FILE%"
set /p ASM_ID=<"%ASM_ID_FILE%"
if not defined ASM_ID (
    echo Assemble task failed.
    exit /b 1
)

"%EXE%" -ul %LOGIN% -up %PASSWORD% -g "%ASM_ID%" -r out.ptptb -o "%BIN_FILE%"

set "RUN_ID="
set "RUN_ID_FILE=%TOOLS_DIR%run_id.txt"
set "RUN_HAS_TRACE=0"
if /I "%RUN_MODE%"=="exec" (
    "%EXE%" -ul %LOGIN% -up %PASSWORD% -s ExecuteBinaryWithInput -id -w stdinRegStName rin_s stdoutRegStName rout_s inputFile "%INPUT_FILE%" definitionFile "%TARGET_FILE%" archName %ARCH% binaryFileToRun "%BIN_FILE%" codeRamBankName code ipRegStorageName ip_s finishMnemonicName ret > "%RUN_ID_FILE%"
    set /p RUN_ID=<"%RUN_ID_FILE%"
    if not defined RUN_ID (
        echo ExecuteBinaryWithInput task failed.
        exit /b 1
    )
    set "RUN_HAS_TRACE=1"
) else (
    "%EXE%" -ul %LOGIN% -up %PASSWORD% -s MachineDebugBinary -id -w definitionFile "%TARGET_FILE%" archName %ARCH% binaryFileToRun "%BIN_FILE%" codeRamBankName code ipRegStorageName ip_s finishMnemonicName ret > "%RUN_ID_FILE%"
    set /p RUN_ID=<"%RUN_ID_FILE%"
    if not defined RUN_ID (
        echo MachineDebugBinary task failed.
        exit /b 1
    )
)

if "%RUN_HAS_TRACE%"=="1" (
    "%EXE%" -ul %LOGIN% -up %PASSWORD% -g "%RUN_ID%" -r trace.txt -o "%TRACE_FILE%"
)
"%EXE%" -ul %LOGIN% -up %PASSWORD% -g "%RUN_ID%" -r stdout.txt -o "%STDOUT_FILE%"

if exist "%ASM_ID_FILE%" del "%ASM_ID_FILE%"
if exist "%RUN_ID_FILE%" del "%RUN_ID_FILE%"

echo Done
endlocal
