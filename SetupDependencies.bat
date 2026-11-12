@echo off
rem Installs, checks or updates this repository's dependencies (PasVulkan, Vulkan SDK, ...).
rem   SetupDependencies.bat                 install what is missing
rem   SetupDependencies.bat check           report only
rem   SetupDependencies.bat update          move dependencies to the pinned versions
rem Options are passed through, e.g. -DepsRoot E:\Deps -AcceptLicenses -Feature physics
rem See Tools\Deps\README.md.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Tools\Deps\Deps.ps1" %*
exit /b %ERRORLEVEL%
