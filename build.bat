@echo off
REM ============================================================================
REM  AsmCross - Build script (VS 2022 Build Tools x86 toolchain)
REM  Usage: run build.bat from a terminal
REM ============================================================================
setlocal enableextensions enabledelayedexpansion

set "VSBAT=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars32.bat"
set "SRC=Crosshair.asm"
set "OBJ=Crosshair.obj"
set "EXE=Crosshair.exe"

if not exist "%VSBAT%" (
    echo [ERROR] vcvars32.bat not found: "!VSBAT!"
    echo         Please install Visual Studio 2022 Build Tools with C++ workload.
    exit /b 1
)

if not exist "%SRC%" (
    echo [ERROR] Source file not found: %SRC%
    exit /b 1
)

REM --- 1. Initialize x86 build environment (INCLUDE / LIB / PATH) ---
call "%VSBAT%" >nul
if errorlevel 1 (
    echo [ERROR] vcvars32.bat invocation failed.
    exit /b 1
)

echo [1/3] Assembling %SRC% ...
ml /c /coff /Cp /nologo "%SRC%"
if errorlevel 1 (
    echo [ERROR] ml.exe assembly failed.
    exit /b 1
)

echo [2/3] Linking %OBJ% -^> %EXE% ...
link /SUBSYSTEM:WINDOWS /ENTRY:start /NODEFAULTLIB /MACHINE:X86 ^
     /NXCOMPAT /DYNAMICBASE /nologo ^
     /STACK:262144,4096 /HEAP:262144,4096 ^
     /OUT:"%EXE%" ^
     "%OBJ%" kernel32.lib user32.lib gdi32.lib
if errorlevel 1 (
    echo [ERROR] link.exe failed.
    exit /b 1
)

echo [3/3] Build succeeded.
echo       Output: %CD%\%EXE%
echo       Run:    %EXE%  (Alt+F1 toggle, Alt+F2 exit)
endlocal
exit /b 0
