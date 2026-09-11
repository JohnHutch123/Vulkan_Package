@echo off
setlocal enabledelayedexpansion

rem ---------------------------------------------------------------------------
rem  Builds and runs the console test programs in this folder.
rem
rem  Each test is a plain .dpr that compiles the real runtime units and asserts
rem  against them, so there is no test framework to install.  A test prints one
rem  line per check and exits non-zero if any failed.
rem
rem  Override either path if this script cannot find them by itself:
rem     set BDS=C:\Program Files (x86)\Embarcadero\Studio\23.0
rem     set PASVULKAN=D:\Vulkan
rem ---------------------------------------------------------------------------

set "TESTDIR=%~dp0"
set "TESTDIR=%TESTDIR:~0,-1%"
set "REPO=%TESTDIR%\.."
set "OUT=%TESTDIR%\Win32"

rem -- Locate the Delphi command line compiler --------------------------------
if defined BDS (
  set "DCC=%BDS%\bin\dcc32.exe"
) else (
  for %%V in (37.0 23.0 22.0) do (
    if not defined DCC (
      if exist "%ProgramFiles(x86)%\Embarcadero\Studio\%%V\bin\dcc32.exe" (
        set "DCC=%ProgramFiles(x86)%\Embarcadero\Studio\%%V\bin\dcc32.exe"
        set "BDS=%ProgramFiles(x86)%\Embarcadero\Studio\%%V"
      )
    )
  )
)

if not exist "%DCC%" (
  echo ERROR: could not find dcc32.exe.
  echo        Set BDS to your Delphi install, e.g.
  echo          set BDS=C:\Program Files ^(x86^)\Embarcadero\Studio\23.0
  exit /b 2
)

rem -- Locate PasVulkan -------------------------------------------------------
if not defined PASVULKAN (
  for %%P in ("%REPO%\..\Vulkan" "D:\Vulkan" "C:\Vulkan") do (
    if not defined PASVULKAN (
      if exist "%%~P\src\PasVulkan.Math.pas" set "PASVULKAN=%%~P"
    )
  )
)

if not exist "%PASVULKAN%\src\PasVulkan.Math.pas" (
  echo ERROR: could not find PasVulkan.
  echo        Set PASVULKAN to the PasVulkan checkout, e.g.
  echo          set PASVULKAN=D:\Vulkan
  exit /b 2
)

echo Compiler:  %DCC%
echo PasVulkan: %PASVULKAN%
echo.

if not exist "%OUT%" mkdir "%OUT%"

set "UNITS=-U"%BDS%\lib\win32\release" -U"%PASVULKAN%\src" -U"%PASVULKAN%" -U"%PASVULKAN%\externals\pasmp\src" -U"%PASVULKAN%\externals\pucu\src" -U"%PASVULKAN%\externals\pasdblstrutils\src" -U"%PASVULKAN%\externals\pasjson\src" -U"%REPO%\RunTime_Src""

set FAILED=0

for %%T in (FrustumTest AABBTest BoundsTest CullTest) do (
  echo === %%T ===

  "%DCC%" -Q -B --no-config -NSSystem;System.Win;Winapi;Vcl;Vcl.Imaging;Data;Xml ^
    %UNITS% -I"%REPO%\RunTime_Src" -N"%OUT%" -E"%OUT%" "%TESTDIR%\%%T.dpr" > "%OUT%\%%T.build.log" 2>&1

  if errorlevel 1 (
    echo BUILD FAILED - see %OUT%\%%T.build.log
    findstr /I /C:"Error" /C:"Fatal" "%OUT%\%%T.build.log"
    set /a FAILED+=1
  ) else (
    "%OUT%\%%T.exe"
    if errorlevel 1 set /a FAILED+=1
  )
  echo.
)

if %FAILED%==0 (
  echo ALL TEST PROGRAMS PASSED
  exit /b 0
) else (
  echo %FAILED% TEST PROGRAM^(S^) FAILED
  exit /b 1
)
