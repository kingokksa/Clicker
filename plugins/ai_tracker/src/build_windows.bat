@echo off
REM Build AI Tracker plugin for Windows (MSVC)
REM Requires ONNX Runtime headers in ONNXROOT env var or ..\..\onnxruntime\include

setlocal

set PLUGIN_NAME=ai_tracker

echo Building %PLUGIN_NAME%.dll ...

REM Find Visual Studio
for /f "usebackq tokens=*" %%i in (`vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2^>nul`) do set VS_PATH=%%i

if "%VS_PATH%"=="" (
    echo ERROR: Visual Studio not found.
    exit /b 1
)

REM Set up MSVC environment
call "%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1

REM Create output directory
if not exist "..\windows" mkdir "..\windows"

REM Copy SDK header if not present
if not exist "clicker_plugin.h" copy /y "..\..\..\sdk\clicker_plugin.h" . >nul

REM Compile (without ONNX Runtime linked — loaded dynamically)
cl /LD /O2 /std:c++17 /W2 /D PLUGIN_EXPORTS main.cpp /I. /Fe:..\windows\%PLUGIN_NAME%.dll
if %ERRORLEVEL% neq 0 (
    echo ERROR: Build failed.
    exit /b 1
)

REM Clean up
del /q *.obj *.exp *.lib 2>nul

echo.
echo SUCCESS: ..\windows\%PLUGIN_NAME%.dll
echo.
echo NOTE: To enable AI detection, place onnxruntime.dll alongside this DLL
echo       and a YOLO .onnx model file in the models/ subdirectory.
endlocal
