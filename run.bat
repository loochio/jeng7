@echo off
setlocal

set PARAMS=%*

E:\dev\jai\jai-beta-2-017\jai\bin\jai.exe .\build.jai - %PARAMS%

if %errorlevel% neq 0 (
	echo Compilation failed
	exit /b %errorlevel%
)

.\GameF.exe

endlocal