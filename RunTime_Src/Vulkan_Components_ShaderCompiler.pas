{GROK 6 September 2025}
                                                                                                                     unit Vulkan_Components_ShaderCompiler;

interface

uses
  SysUtils, Classes,
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
  case OptimizationLevel of
    shaderc_optimization_level_zero: Result := '';
    shaderc_optimization_level_size: Result := '-Os';
    shaderc_optimization_level_performance: Result := '-O';
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

procedure CompileAndCreateShaderModule(const Device    : TVkDevice;
                                       out ShaderModule: TVkShaderModule;
                                       GLSLSource      : String;
                                       ShaderKind      : shaderc_shader_kind = shaderc_vertex_shader;
                                       OptimizationLevel: shaderc_optimization_level = shaderc_optimization_level_performance;
                                       TargetEnv       : shaderc_target_env = shaderc_target_env_vulkan;
                                       EnvVersion      : shaderc_env_version = 1 shl 22);  // Default: Vulkan 1.0

var
 // GLSLSource: AnsiString;
  TempGlslFile, TempSpvFile: string;
  FileStream: TFileStream;
  CmdLine, Output: string;
  ExitCode: Integer;
  SPIRVData: TBytes;
  SPIRVSize: NativeUInt;
  CreateInfo: TVkShaderModuleCreateInfo;
  VkResult: TVkResult;
  GlslangPath, StageExt, OptFlag, TargetFlag: string;
begin
  Assert(Device <> VK_NULL_HANDLE, 'Invalid Vulkan device handle');

 (*
  // Dynamically build GLSL shader in code (example: simple vertex shader; adapt as needed)
  GLSLSource :=
    '#version 450' + #10 +
    '#extension GL_KHR_vulkan_glsl : enable' + #10 +
    'layout(location = 0) in vec3 inPosition;' + #10 +
    'layout(location = 0) out vec4 fragColor;' + #10 +
    'void main() {' + #10 +
    '  gl_Position = vec4(inPosition, 1.0);' + #10 +
    '  fragColor = vec4(1.0, 0.0, 0.0, 1.0);' + #10 +
    '}';
  *)

  // Prepare temp files
// Prepare temp files (use GetTempDir for correct temp path handling)
  TempGlslFile := IncludeTrailingPathDelimiter(GetTempDir) + 'shader_temp.' + GetStageExtension(ShaderKind);
  TempSpvFile  := IncludeTrailingPathDelimiter(GetTempDir) + 'shader_temp.spv';


  // Write GLSL to temp file
  FileStream := TFileStream.Create(TempGlslFile, fmCreate);
  try
    FileStream.WriteBuffer(Pointer(GLSLSource)^, Length(GLSLSource));
  finally
    FileStream.Free;
  end;

  // Build command line
  GlslangPath := GetGlslangPath;
  StageExt := GetStageExtension(ShaderKind);
  OptFlag := GetOptimizationFlag(OptimizationLevel);
  TargetFlag := GetTargetEnvFlag(EnvVersion);
  CmdLine := Format('"%s" -S %s --target-env %s -e main %s -o "%s" "%s"',
    [GlslangPath, StageExt, TargetFlag, OptFlag, TempSpvFile, TempGlslFile]);

  // Execute and capture output (for errors)
  ExitCode := ExecAndCapture(CmdLine, Output);
  try
    if ExitCode <> 0 then
      raise Exception.CreateFmt('glslangValidator failed (exit code %d): %s', [ExitCode, Trim(Output)]);

    // Read SPIR-V binary
    if not FileExists(TempSpvFile) then
      raise Exception.Create('SPIR-V output file not created');
    FileStream := TFileStream.Create(TempSpvFile, fmOpenRead);
    try
      SPIRVSize := FileStream.Size;
      Assert(SPIRVSize > 0, 'Compiled SPIR-V size is zero');
      SetLength(SPIRVData, SPIRVSize);
      FileStream.ReadBuffer(SPIRVData[0], SPIRVSize);
    finally
      FileStream.Free;
    end;

    // Create Vulkan shader module
    FillChar(CreateInfo, SizeOf(CreateInfo), 0);
    CreateInfo.sType := VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    CreateInfo.codeSize := SPIRVSize;
    CreateInfo.pCode := @SPIRVData[0];  // SPIR-V binary words (uint32_t*)

    VkResult := vkCreateShaderModule(Device, @CreateInfo, nil, @ShaderModule);
    if VkResult <> VK_SUCCESS then
      raise EVulkanException.CreateFmt('Failed to create Vulkan shader module (error code: %d)', [Ord(VkResult)]);
    Assert(ShaderModule <> VK_NULL_HANDLE, 'Created shader module is invalid');
  finally
    // Clean up temp files
    DeleteFile(TempGlslFile);
    DeleteFile(TempSpvFile);
  end;
end;

end.
