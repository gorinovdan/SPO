@echo off
setlocal

for /f "delims=" %%A in ('Portable.RemoteTasks.Manager.exe -ul 338960
-up 550fdf73-65b4-4e66-a0b6-6579cb1336a4 -s Assemble -id -w
definitionFile C:\Users\Asuse\Documents\Study\University\SPO\SPO3\spo3.target.pdsl
archName vm32 asmListing C:\Users\Asuse\Documents\Study\University\SPO\SPO3\results\output.asm') do set "out1=%%A"

Portable.RemoteTasks.Manager.exe -ul 338960 -up 550fdf73-65b4-4e66-a0b6-6579cb1336a4 -g "%out1%" -r out.ptptb -o C:\Users\Asuse\Documents\Study\University\SPO\tools\out.ptptb

echo Done

endlocal

.\Portable.RemoteTasks.Manager.exe -ul 338960 -up 550fdf73-65b4-4e66-a0b6-6579cb1336a4 -s Assemble -id -w definitionFile C:\Users\Asuse\Documents\Study\University\SPO\SPO3\spo3.target.pdsl archName vm32 asmListing C:\Users\Asuse\Documents\Study\University\SPO\SPO3\results\output.asm
