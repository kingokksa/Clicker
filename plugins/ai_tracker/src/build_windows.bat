@echo off
setlocal

set PLUGIN_NAME=ai_tracker

echo Building %PLUGIN_NAME%.dll ...

REM Find Visual Studio via vswhere
set VSWHERE_PATH=
for %%p in (
    "%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
    "%ProgramFiles%\Microsoft Visual Studio\Installer\vswhere.exe"
) do (
    if exist %%p set VSWHERE_PATH=%%p
)

set VS_PATH=
if not "%VSWHERE_PATH%"=="" (
    for /f "usebackq tokens=*" %%i in (`%VSWHERE_PATH% -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2^>nul`) do set VS_PATH=%%i
)

if "%VS_PATH%"=="" (
    echo ERROR: Visual Studio not found via vswhere.
    echo Searching common paths...
    for %%d in (
        "H:\vs\product"
        "C:\Program Files\Microsoft Visual Studio\2022\Community"
        "C:\Program Files\Microsoft Visual Studio\2022\Professional"
        "C:\Program Files\Microsoft Visual Studio\2022\Enterprise"
        "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community"
        "C:\Program Files (x86)\Microsoft Visual Studio\2019\Professional"
    ) do (
        if exist %%d\VC\Auxiliary\Build\vcvars64.bat (
            set VS_PATH=%%d
            echo Found: %%d
        )
    )
)

if "%VS_PATH%"=="" (
    echo ERROR: Visual Studio not found.
    exit /b 1
)

echo Using VS: %VS_PATH%

REM Set up MSVC environment
call "%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat"

REM Create output directory
if not exist "..\windows" mkdir "..\windows"

REM Copy SDK header if not present
if not exist "clicker_plugin.h" copy /y "..\..\..\sdk\clicker_plugin.h" . >nul

REM Compile
cl /LD /O2 /std:c++17 /W2 /utf-8 /EHsc /D PLUGIN_EXPORTS main.cpp /I. /Fe:..\windows\%PLUGIN_NAME%.dll Shell32.lib
if %ERRORLEVEL% neq 0 (
    echo ERROR: Build failed.
    exit /b 1
)

REM Clean up
del /q *.obj *.exp *.lib 2>nul

echo.
echo SUCCESS: ..\windows\%PLUGIN_NAME%.dll
endlocal
