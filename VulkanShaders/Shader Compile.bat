@echo off
:: Compiles the shaders in this folder, in place (the package reads them from
:: here).  glslangValidator and spirv-val come from the Vulkan SDK.
::
:: Each prebuilt shader is one source with #ifdef variants, compiled to the
:: names a store loads with PrebuiltShaderVariants:
::   Vert  <Name>_vert.spv            float view-projection
::         <Name>Double_vert.spv      -DVG_DOUBLE     (renderer ShaderUseDouble)
::   Frag  <Name>_frag.spv            no picking
::         <Name>Pick_frag.spv        -DVG_PICK       (SelectMode smStorageBuffer)
::         <Name>PickImage_frag.spv   -DVG_PICK_IMAGE (SelectMode smImageBuffer)
::   Plain <Name>_vert.spv, <Name>_frag.spv from <Name>.vert / <Name>.frag
:: A fourth argument adds a define of the shader's own.
::
:: set NOPAUSE=1 to skip the closing pause.

setlocal
set "HERE=%~dp0"
set "GLSLANG=glslangValidator.exe"
set "SPIRVVAL="
if defined VULKAN_SDK (
  set "GLSLANG=%VULKAN_SDK%\Bin\glslangValidator.exe"
  if exist "%VULKAN_SDK%\Bin\spirv-val.exe" set "SPIRVVAL=%VULKAN_SDK%\Bin\spirv-val.exe"
)
set FAILED=0

::          output name            source                     own define
call :Plain TestTriangle
call :Vert  TestTriangleWithData   TestTriangleWithData.vert
call :Frag  TestTriangleWithData   TestTriangleWithData.frag
call :Vert  TestTextureRect        TestTextureRect.vert
call :Frag  TestTextureRect        TestTextureRect.frag
call :Vert  OBJ                    OBJ.vert
call :Frag  OBJ                    OBJ.frag
call :Frag  OBJTexture             OBJ.frag                   -DOBJ_TEXTURE

echo.
if %FAILED%==0 (echo All shaders compiled.) else (echo %FAILED% shader^(s^) FAILED.)
if not defined NOPAUSE pause
exit /b %FAILED%

:Plain
call :Build "%~1.vert" "%~1_vert.spv"
call :Build "%~1.frag" "%~1_frag.spv"
exit /b

:Vert
call :Build "%~2" "%~1_vert.spv"       %3
call :Build "%~2" "%~1Double_vert.spv" %3 -DVG_DOUBLE
exit /b

:Frag
call :Build "%~2" "%~1_frag.spv"          %3
call :Build "%~2" "%~1Pick_frag.spv"      %3 -DVG_PICK
call :Build "%~2" "%~1PickImage_frag.spv" %3 -DVG_PICK_IMAGE
exit /b

:: source, output, defines
:Build
"%GLSLANG%" -V %3 %4 "%HERE%%~1" -o "%HERE%%~2" >nul
if errorlevel 1 (
  echo FAILED   %~2
  "%GLSLANG%" -V %3 %4 "%HERE%%~1" -o "%HERE%%~2"
  set /a FAILED+=1
  exit /b
)
if defined SPIRVVAL (
  "%SPIRVVAL%" "%HERE%%~2"
  if errorlevel 1 (
    echo INVALID  %~2
    set /a FAILED+=1
    exit /b
  )
)
echo ok       %~2
exit /b
