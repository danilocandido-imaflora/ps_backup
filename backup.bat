@echo off

openfiles > NUL 2>&1 
if NOT %ERRORLEVEL% EQU 0 goto :notadmin

:start
powershell.exe -ExecutionPolicy Bypass -File \\imanet\NETLOGON\tools\backup.ps1
goto :end

:notadmin 
echo.
echo     A operação solicitada requer elevação.
echo     Entre em contato com o Suporte TI
echo.
goto end

:end
endlocal
@echo on
