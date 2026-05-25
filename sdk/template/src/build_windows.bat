@echo off
REM Build Clicker plugin for Windows (MSVC)
REM Usage: build_windows.bat [plugin_name]
REM Example: build_windows.bat example_plugin

setlocal

set PLUGIN_NAME=%1
if "%PLUGIN_NAME%"=="" set PLUGIN_NAME=example_plugin

echo Building %PLUGIN_NAME%.dll ...

REM Find Visual Studio
for /f "usebackq tokens=*" %%i in (`vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2^>nul`) do set VS_PATH=%%i

if "%VS_PATH%"=="" (
    echo ERROR: Visual Studio not found. Please install Visual Studio with C++ tools.
    exit /b 1
)

REM Set up MSVC environment
call "%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1

REM Create output directory
if not exist "..\windows" mkdir "..\windows"

REM Compile
cl /LD /O2 /W4 /D PLUGIN_EXPORTS main.c /I. /Fe:..\windows\%PLUGIN_NAME%.dll
if %ERRORLEVEL% neq 0 (
    echo ERROR: Build failed.
    exit /b 1
)

REM Clean up
del /q *.obj *.exp *.lib 2>nul

echo.
echo SUCCESS: ..\windows\%PLUGIN_NAME%.dll
endlocal
