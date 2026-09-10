{GROK 6 September 2025}
                                                                                                                     unit Vulkan_Components_ShaderCompiler;

interface

uses
  SysUtils, Classes, System.IOUtils,
  Vulkan,
  PasVulkan.Types,
  PasVulkan.Math,
  PasVulkan.Collections,
  PasVulkan.Framework
  {$IFDEF MSWINDOWS}
  , Winapi.Windows, Winapi.ShellAPI
  {$ENDIF}
  {$IFDEF POSIX}
  , Posix.Stdlib, Posix.Unistd, Posix.Stdio
  {$ENDIF};

type
  // Enums retained from shaderc for compatibility
  shaderc_shader_kind = ( shaderc_vertex_shader = 0,
                          shaderc_fragment_shader = 1,
                          shaderc_compute_shader = 4
    // Add more as needed
                        );
  shaderc_optimization_level = ( shaderc_optimization_level_zero = 0,
                                 shaderc_optimization_level_size = 1,
                                 shaderc_optimization_level_performance = 2
                               );
  shaderc_target_env = ( shaderc_target_env_vulkan = 1
                        // Add others if needed
                        );
  shaderc_env_version = Cardinal;  // e.g., 1 shl 22 for Vulkan 1.0

// Compile GLSL to a SPIR-V blob.  No Vulkan device needed, so this can be
// exercised (and unit tested) without an instance being up.
function CompileGLSLToSPIRV(const GLSLSource : String;
                            ShaderKind       : shaderc_shader_kind = shaderc_vertex_shader;
                            OptimizationLevel: shaderc_optimization_level = shaderc_optimization_level_performance;
                            TargetEnv        : shaderc_target_env = shaderc_target_env_vulkan;
                            EnvVersion       : shaderc_env_version = 1 shl 22): TBytes;

procedure CompileAndCreateShaderModule(const Device    : TVkDevice;
                                       out ShaderModule: TVkShaderModule;
                                       GLSLSource      : String;
                                       ShaderKind      : shaderc_shader_kind = shaderc_vertex_shader;
                                       OptimizationLevel: shaderc_optimization_level = shaderc_optimization_level_performance;
                                       TargetEnv       : shaderc_target_env = shaderc_target_env_vulkan;
                                       EnvVersion      : shaderc_env_version = 1 shl 22);  // Default: Vulkan 1.0

implementation

function GetGlslangPath: string;
var
  VulkanSDK: string;
begin
  VulkanSDK := GetEnvironmentVariable('VULKAN_SDK');
  if VulkanSDK = '' then
    raise Exception.Create('VULKAN_SDK environment variable not set; ensure Vulkan SDK is installed');

{$IFDEF MSWINDOWS}
  Result := IncludeTrailingPathDelimiter(VulkanSDK) + 'Bin\glslangValidator.exe';
{$ENDIF}
{$IFDEF LINUX}
  Result := IncludeTrailingPathDelimiter(VulkanSDK) + 'bin/glslangValidator';
{$ENDIF}
{$IFDEF MACOS}
  Result := IncludeTrailingPathDelimiter(VulkanSDK) + 'bin/glslangValidator';
{$ENDIF}

{$IF NOT (DEFINED(MSWINDOWS) OR DEFINED(LINUX) OR DEFINED(MACOS) OR DEFINED(ANDROID) OR DEFINED(IOS))}
  raise Exception.Create('Unsupported platform for shaderc loading');
{$ENDIF}

  if not FileExists(Result) then
    raise Exception.CreateFmt('glslangValidator not found at: %s', [Result]);
end;

function GetStageExtension(ShaderKind: shaderc_shader_kind): string;
begin
  case ShaderKind of
    shaderc_vertex_shader: Result := 'vert';
    shaderc_fragment_shader: Result := 'frag';
    shaderc_compute_shader: Result := 'comp';
    else raise Exception.Create('Unsupported shader kind');
  end;
end;

function GetOptimizationFlag(OptimizationLevel: shaderc_optimization_level): string;
begin
  // glslangValidator only understands -Od (disable) and -Os (size).  There is
  // no plain -O: passing one makes it exit 1 with "unknown -O option", so the
  // shaderc "performance" level maps to glslang's default output instead.
  case OptimizationLevel of
    shaderc_optimization_level_zero:        Result := '-Od';
    shaderc_optimization_level_size:        Result := '-Os';
    shaderc_optimization_level_performance: Result := '';
    else Result := '';
  end;
end;

function GetTargetEnvFlag(EnvVersion: shaderc_env_version): string;
begin
  case EnvVersion of
     1 shl 22: Result := 'vulkan1.0';
    (1 shl 22) or 1: Result := 'vulkan1.1';
    (1 shl 22) or 2: Result := 'vulkan1.2';
    (1 shl 22) or 3: Result := 'vulkan1.3';
    else
      raise Exception.Create('Unsupported Vulkan environment version');
  end;
end;

{$IFDEF MSWINDOWS}
function ExecAndCapture(const CmdLine: string; var Output: string): Integer;
const
  BufferSize = 2048;
var
  SecurityAttr: TSecurityAttributes;
  ReadPipe, WritePipe: THandle;
  StartupInfo: TStartupInfo;
  ProcessInfo: TProcessInformation;
  Buffer: array[0..BufferSize - 1] of AnsiChar;
  BytesAvailable, BytesRead: DWORD;
  AppRunning: Cardinal;
begin
  Output := '';
  FillChar(SecurityAttr, SizeOf(SecurityAttr), 0);
  SecurityAttr.nLength := SizeOf(SecurityAttr);
  SecurityAttr.bInheritHandle := True;
  if not CreatePipe(ReadPipe, WritePipe, @SecurityAttr, 0) then
    raise Exception.Create('Failed to create pipe: ' + SysErrorMessage(GetLastError));

  try
    FillChar(StartupInfo, SizeOf(StartupInfo), 0);
    StartupInfo.cb := SizeOf(StartupInfo);
    StartupInfo.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    StartupInfo.hStdOutput := WritePipe;
    StartupInfo.hStdError := WritePipe;  // Redirect stderr to stdout
    StartupInfo.wShowWindow := SW_HIDE;

    if not CreateProcess(nil, PChar(CmdLine), nil, nil, True, CREATE_NO_WINDOW, nil, nil, StartupInfo, ProcessInfo) then
      raise Exception.Create('Failed to create process: ' + SysErrorMessage(GetLastError));

    CloseHandle(WritePipe);  // Close write end after process creation
    try
      repeat
        AppRunning := WaitForSingleObject(ProcessInfo.hProcess, 100);
        PeekNamedPipe(ReadPipe, nil, 0, nil, @BytesAvailable, nil);
        if BytesAvailable > 0 then
        begin
          FillChar(Buffer, BufferSize, 0);
          ReadFile(ReadPipe, Buffer, BufferSize - 1, BytesRead, nil);
          Output := Output + string(Buffer);
        end;
      until (AppRunning <> WAIT_TIMEOUT);
      GetExitCodeProcess(ProcessInfo.hProcess, Cardinal(Result));
    finally
      CloseHandle(ProcessInfo.hProcess);
      CloseHandle(ProcessInfo.hThread);
    end;
  finally
    CloseHandle(ReadPipe);
  end;
end;
{$ENDIF}

{$IFDEF POSIX}
function ExecAndCapture(const CmdLine: string; var Output: string): Integer;
var
  Pipe: Pointer;
  Buffer: array[0..2047] of AnsiChar;
  BytesRead: Integer;
begin
  Output := '';
  Pipe := popen(PAnsiChar(CmdLine + ' 2>&1'), 'r');  // Redirect stderr to stdout
  if Pipe = nil then
    raise Exception.Create('Failed to execute command');

  try
    while not feof(PFILE(Pipe)) do
    begin
      BytesRead := fread(@Buffer, 1, SizeOf(Buffer), PFILE(Pipe));
      if BytesRead > 0 then
        Output := Output + Copy(string(Buffer), 1, BytesRead);
    end;
    Result := pclose(PFILE(Pipe));
    if Result = -1 then
      raise Exception.Create('Failed to close pipe');
    Result := Result shr 8;  // Extract exit code
  except
    pclose(PFILE(Pipe));
    raise;
  end;
end;
{$ENDIF}

function CompileGLSLToSPIRV(const GLSLSource : String;
                            ShaderKind       : shaderc_shader_kind;
                            OptimizationLevel: shaderc_optimization_level;
                            TargetEnv        : shaderc_target_env;
                            EnvVersion       : shaderc_env_version): TBytes;
var
  TempBase,
  TempGlslFile,
  TempSpvFile : string;
  FileStream  : TFileStream;
  CmdLine,
  Output      : string;
  ExitCode    : Integer;
  SPIRVSize   : Int64;
  GlslangPath,
  StageExt,
  OptFlag,
  TargetFlag  : string;
  SourceBytes : TBytes;
begin
  Result := nil;

  if Trim(GLSLSource) = '' then
    raise Exception.Create('CompileGLSLToSPIRV: GLSL source is empty');

  // TargetEnv is carried for API compatibility; glslangValidator takes the
  // concrete environment from EnvVersion.
  if TargetEnv <> shaderc_target_env_vulkan then
    raise Exception.Create('CompileGLSLToSPIRV: only the Vulkan target environment is supported');

  GlslangPath := GetGlslangPath;
  StageExt    := GetStageExtension(ShaderKind);
  OptFlag     := GetOptimizationFlag(OptimizationLevel);
  TargetFlag  := GetTargetEnvFlag(EnvVersion);

  // Unique per call.  A fixed name races as soon as two shaders are built at
  // once, or a second build starts while the first is still reading its .spv.
  TempBase := IncludeTrailingPathDelimiter(TPath.GetTempPath) +
              'vgshader_' + TPath.GetGUIDFileName(False);

  TempGlslFile := TempBase + '.' + StageExt;
  TempSpvFile  := TempBase + '.spv';

  try
    // The source MUST reach glslangValidator as UTF-8 bytes.  Writing the
    // UnicodeString buffer raw would emit UTF-16 code units, and passing
    // Length() as a byte count would emit only half of them.
    SourceBytes := TEncoding.UTF8.GetBytes(GLSLSource);

    FileStream := TFileStream.Create(TempGlslFile, fmCreate);
    try
      if Length(SourceBytes) > 0 then
        FileStream.WriteBuffer(SourceBytes[0], Length(SourceBytes));
    finally
      FileStream.Free;
    end;

    CmdLine := Format('"%s" -S %s --target-env %s -e main %s -o "%s" "%s"',
      [GlslangPath, StageExt, TargetFlag, OptFlag, TempSpvFile, TempGlslFile]);

    ExitCode := ExecAndCapture(CmdLine, Output);

    if ExitCode <> 0 then
      raise Exception.CreateFmt('glslangValidator failed (exit code %d): %s',
                                [ExitCode, Trim(Output)]);

    if not FileExists(TempSpvFile) then
      raise Exception.Create('SPIR-V output file not created');

    FileStream := TFileStream.Create(TempSpvFile, fmOpenRead or fmShareDenyWrite);
    try
      SPIRVSize := FileStream.Size;

      if SPIRVSize <= 0 then
        raise Exception.Create('Compiled SPIR-V is empty');

      // SPIR-V is a stream of 32-bit words; anything else means a truncated
      // or corrupt file rather than something Vulkan should be handed.
      if (SPIRVSize mod SizeOf(TvkUint32)) <> 0 then
        raise Exception.CreateFmt(
          'Compiled SPIR-V size (%d bytes) is not a multiple of 4', [SPIRVSize]);

      SetLength(Result, SPIRVSize);
      FileStream.ReadBuffer(Result[0], SPIRVSize);
    finally
      FileStream.Free;
    end;
  finally
    // Qualified so these resolve to the RTL's string overload rather than
    // Winapi.Windows.DeleteFile, which takes a PWideChar.
    System.SysUtils.DeleteFile(TempGlslFile);
    System.SysUtils.DeleteFile(TempSpvFile);
  end;
end;

procedure CompileAndCreateShaderModule(const Device    : TVkDevice;
                                       out ShaderModule: TVkShaderModule;
                                       GLSLSource      : String;
                                       ShaderKind      : shaderc_shader_kind = shaderc_vertex_shader;
                                       OptimizationLevel: shaderc_optimization_level = shaderc_optimization_level_performance;
                                       TargetEnv       : shaderc_target_env = shaderc_target_env_vulkan;
                                       EnvVersion      : shaderc_env_version = 1 shl 22);
var
  SPIRVData  : TBytes;
  CreateInfo : TVkShaderModuleCreateInfo;
  VkResult   : TVkResult;
begin
  ShaderModule := VK_NULL_HANDLE;

  Assert(Device <> VK_NULL_HANDLE, 'Invalid Vulkan device handle');

  SPIRVData := CompileGLSLToSPIRV(GLSLSource, ShaderKind, OptimizationLevel,
                                  TargetEnv, EnvVersion);

  FillChar(CreateInfo, SizeOf(CreateInfo), 0);
  CreateInfo.sType    := VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
  CreateInfo.pNext    := nil;
  CreateInfo.flags    := 0;
  CreateInfo.codeSize := Length(SPIRVData);
  CreateInfo.pCode    := @SPIRVData[0];   // SPIR-V words (uint32_t*)

  VkResult := vkCreateShaderModule(Device, @CreateInfo, nil, @ShaderModule);
  if VkResult <> VK_SUCCESS then
    raise Exception.CreateFmt(
      'Failed to create Vulkan shader module (error code: %d)', [Ord(VkResult)]);

  Assert(ShaderModule <> VK_NULL_HANDLE, 'Created shader module is invalid');
end;

end.
