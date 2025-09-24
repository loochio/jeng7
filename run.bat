@echo off
setlocal

set PARAMS=%*

jai .\build.jai - %PARAMS%

if %errorlevel% neq 0 (
	echo Compilation failed
	exit /b %errorlevel%
)

.\GameF.exe

endlocal