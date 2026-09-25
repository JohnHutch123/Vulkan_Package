{GROK 5 September 2025}
//FAILS to load shaderc_shared.dll.  NOT sure why.

unit Vulkan_Components_ShaderCompiler_DLL;


interface

uses
  SysUtils, Classes,
  Vulkan,
    PasVulkan.Types,
  PasVulkan.Math,
  PasVulkan.Collections,
  PasVulkan.Framework,
  {$IFDEF MSWINDOWS}
   Winapi.Windows
  {$ENDIF}
  {$IFDEF POSIX}
   Posix.Dlfcn
  {$ENDIF} ;

type
  // Basic types from shaderc.h (adapted for Delphi Pascal)
  shaderc_compiler_t = Pointer;
  shaderc_compilation_result_t = Pointer;
  shaderc_shader_kind = (
    shaderc_vertex_shader = 0,
    shaderc_fragment_shader = 1,
    shaderc_compute_shader = 4  // Added for completeness
    // Add more kinds as needed
  );
  shaderc_optimization_level = (
    shaderc_optimization_level_zero = 0,      // No optimization
    shaderc_optimization_level_size = 1,      // Optimize for size
    shaderc_optimization_level_performance = 2 // Optimize for performance
  );
  shaderc_target_env = (
    shaderc_target_env_vulkan = 1  // Vulkan environment
    // Add others like OpenGL if needed
  );
  shaderc_env_version = Cardinal;  // e.g., shaderc_env_version_vulkan_1_0 = 1 shl 22
  shaderc_compile_options_t = Pointer;

  // Function pointers for dynamic loading
  Tshaderc_compiler_initialize = function: shaderc_compiler_t; stdcall;
  Tshaderc_compiler_release = procedure(compiler: shaderc_compiler_t); stdcall;
  Tshaderc_compile_options_initialize = function: shaderc_compile_options_t; stdcall;
  Tshaderc_compile_options_release = procedure(options: shaderc_compile_options_t); stdcall;
  Tshaderc_compile_options_set_optimization_level = procedure(options: shaderc_compile_options_t; level: shaderc_optimization_level); stdcall;
  Tshaderc_compile_options_set_target_env = procedure(options: shaderc_compile_options_t; target: shaderc_target_env; version: shaderc_env_version); stdcall;
  Tshaderc_compile_into_spv = function(compiler: shaderc_compiler_t; const source_text: PAnsiChar; source_text_size: NativeUInt;
    shader_kind: shaderc_shader_kind; const input_file_name: PAnsiChar; const entry_point_name: PAnsiChar;
    const options: shaderc_compile_options_t): shaderc_compilation_result_t; stdcall;
  Tshaderc_result_release = procedure(result: shaderc_compilation_result_t); stdcall;
  Tshaderc_result_get_length = function(const result: shaderc_compilation_result_t): NativeUInt; stdcall;
  Tshaderc_result_get_bytes = function(const result: shaderc_compilation_result_t): Pointer; stdcall;
  Tshaderc_result_get_num_errors = function(const result: shaderc_compilation_result_t): NativeUInt; stdcall;
  Tshaderc_result_get_error_message = function(const result: shaderc_compilation_result_t): PAnsiChar; stdcall;

var
  // Global function vars (loaded dynamically)
  shaderc_compiler_initialize: Tshaderc_compiler_initialize;
  shaderc_compiler_release: Tshaderc_compiler_release;
  shaderc_compile_options_initialize: Tshaderc_compile_options_initialize;
  shaderc_compile_options_release: Tshaderc_compile_options_release;
  shaderc_compile_options_set_optimization_level: Tshaderc_compile_options_set_optimization_level;
  shaderc_compile_options_set_target_env: Tshaderc_compile_options_set_target_env;
  shaderc_compile_into_spv: Tshaderc_compile_into_spv;
  shaderc_result_release: Tshaderc_result_release;
  shaderc_result_get_length: Tshaderc_result_get_length;
  shaderc_result_get_bytes: Tshaderc_result_get_bytes;
  shaderc_result_get_num_errors: Tshaderc_result_get_num_errors;
  shaderc_result_get_error_message: Tshaderc_result_get_error_message;

procedure LoadShadercLibrary;
Function CompileAndCreateShaderModule(const Device    : TVkDevice;
                                       out ShaderModule: TVkShaderModule;
                                       ShaderKind      : shaderc_shader_kind;
									                    OptimizationLevel: shaderc_optimization_level;
                                       TargetEnv       : shaderc_target_env;
                                       EnvVersion      : shaderc_env_version;
									                     GLSLSource      : String):Boolean;

implementation

{$IFDEF MSWINDOWS}
type
  TLibHandle = HMODULE;
const
  NilHandle = 0;
{$ENDIF}
{$IFDEF POSIX}
type
  TLibHandle = Pointer;
const
  NilHandle = nil;
{$ENDIF}

var
  ShadercLib: TLibHandle = NilHandle;

function GetShadercLibName: string;
begin
{$IFDEF MSWINDOWS}
  Result := 'C:\VulkanSDK\1.4.309.0\Bin\shaderc_shared.dll';
{$ENDIF}
{$IFDEF LINUX}
  Result := 'libshaderc_shared.so';
{$ENDIF}
{$IFDEF MACOS}
  Result := 'libshaderc_shared.dylib';
{$ENDIF}
{$IFDEF ANDROID}
  Result := 'libshaderc_shared.so';  // Bundle in app assets
{$ENDIF}
{$IFDEF IOS}
  Result := 'libshaderc_shared.dylib';  // Bundle in app framework
{$ENDIF}

{$IF NOT (DEFINED(MSWINDOWS) OR DEFINED(LINUX) OR DEFINED(MACOS) OR DEFINED(ANDROID) OR DEFINED(IOS))}
  raise Exception.Create('Unsupported platform for shaderc loading');
{$ENDIF}
end;

function vscGetProcAddress(LibraryHandle:pointer;const ProcName:string):pointer; {$ifdef CAN_INLINE}inline;{$endif}
begin
{$ifdef Windows}
 result:=GetProcAddress({%H-}HMODULE(LibraryHandle),PChar(ProcName));
{$else}
{$ifdef Unix}
 result:=dlsym(LibraryHandle,PChar(ProcName));
{$else}
 result:=nil;
{$endif}
{$endif}
end;


procedure LoadShadercLibrary;
var
  LibName: string;
begin
  LibName := GetShadercLibName;


{$IFDEF MSWINDOWS}
  ShadercLib := LoadLibrary(pChar(LibName));
{$ENDIF}
{$IFDEF POSIX}
  ShadercLib := dlopen(PAnsiChar(LibName), RTLD_LAZY);
{$ENDIF}
  if ShadercLib = NilHandle then
    raise Exception.CreateFmt('Failed to load shaderc library: %s (ensure Vulkan SDK is installed and in path)', [LibName]);

  // Load functions with error checking
{$IFDEF MSWINDOWS}
  shaderc_compiler_initialize := GetProcAddress(ShadercLib, 'shaderc_compiler_initialize');
{$ENDIF}
{$IFDEF POSIX}
  shaderc_compiler_initialize := dlsym(ShadercLib, 'shaderc_compiler_initialize');
{$ENDIF}
  Assert(Assigned(shaderc_compiler_initialize), 'Failed to load shaderc_compiler_initialize');


  // Repeat for other functions (omitted for brevity; follow the same pattern)
{$IFDEF MSWINDOWS}
  shaderc_compiler_release := GetProcAddress(ShadercLib, 'shaderc_compiler_release');
  shaderc_compile_options_initialize := GetProcAddress(ShadercLib, 'shaderc_compile_options_initialize');
  shaderc_compile_options_release := GetProcAddress(ShadercLib, 'shaderc_compile_options_release');
  shaderc_compile_options_set_optimization_level := GetProcAddress(ShadercLib, 'shaderc_compile_options_set_optimization_level');
  shaderc_compile_options_set_target_env := GetProcAddress(ShadercLib, 'shaderc_compile_options_set_target_env');
  shaderc_compile_into_spv := GetProcAddress(ShadercLib, 'shaderc_compile_into_spv');
  shaderc_result_release := GetProcAddress(ShadercLib, 'shaderc_result_release');
  shaderc_result_get_length := GetProcAddress(ShadercLib, 'shaderc_result_get_length');
  shaderc_result_get_bytes := GetProcAddress(ShadercLib, 'shaderc_result_get_bytes');
  shaderc_result_get_num_errors := GetProcAddress(ShadercLib, 'shaderc_result_get_num_errors');
  shaderc_result_get_error_message := GetProcAddress(ShadercLib, 'shaderc_result_get_error_message');
{$ENDIF}
{$IFDEF POSIX}
  NOT TESTED
  shaderc_compiler_release := dlsym(ShadercLib, 'shaderc_compiler_release');
  shaderc_compile_options_initialize := dlsym(ShadercLib, 'shaderc_compile_options_initialize');
  shaderc_compile_options_release := dlsym(ShadercLib, 'shaderc_compile_options_release');
  shaderc_compile_options_set_optimization_level := dlsym(ShadercLib, 'shaderc_compile_options_set_optimization_level');
  shaderc_compile_options_set_target_env := dlsym(ShadercLib, 'shaderc_compile_options_set_target_env');
  shaderc_compile_into_spv := dlsym(ShadercLib, 'shaderc_compile_into_spv');
  shaderc_result_release := dlsym(ShadercLib, 'shaderc_result_release');
  shaderc_result_get_length := dlsym(ShadercLib, 'shaderc_result_get_length');
  shaderc_result_get_bytes := dlsym(ShadercLib, 'shaderc_result_get_bytes');
  shaderc_result_get_num_errors := dlsym(ShadercLib, 'shaderc_result_get_num_errors');
  shaderc_result_get_error_message := dlsym(ShadercLib, 'shaderc_result_get_error_message');
{$ENDIF}

  // Assert all are assigned (add individual Asserts as in previous version)
  Assert(Assigned(shaderc_compiler_release), 'Failed to load shaderc_compiler_release');
  Assert(Assigned(shaderc_compile_options_initialize), 'Failed to load shaderc_compile_options_initialize');
  Assert(Assigned(shaderc_compile_options_release), 'Failed to load shaderc_compile_options_release');
  Assert(Assigned(shaderc_compile_options_set_optimization_level), 'Failed to load shaderc_compile_options_set_optimization_level');
  Assert(Assigned(shaderc_compile_options_set_target_env), 'Failed to load shaderc_compile_options_set_target_env');
  Assert(Assigned(shaderc_compile_into_spv), 'Failed to load shaderc_compile_into_spv');
  Assert(Assigned(shaderc_result_release), 'Failed to load shaderc_result_release');
  Assert(Assigned(shaderc_result_get_length), 'Failed to load shaderc_result_get_length');
  Assert(Assigned(shaderc_result_get_bytes), 'Failed to load shaderc_result_get_bytes');
  Assert(Assigned(shaderc_result_get_num_errors), 'Failed to load shaderc_result_get_num_errors');
  Assert(Assigned(shaderc_result_get_error_message), 'Failed to load shaderc_result_get_error_message');

end;

procedure UnloadShadercLibrary;
begin
  if ShadercLib <> NilHandle then
  begin
{$IFDEF MSWINDOWS}
    FreeLibrary(ShadercLib);
{$ENDIF}
{$IFDEF POSIX}
    dlclose(ShadercLib);
{$ENDIF}
    ShadercLib := NilHandle;
  end;
end;

Function CompileAndCreateShaderModule(const Device     : TVkDevice;
                                       out ShaderModule: TVkShaderModule;
                                       ShaderKind      : shaderc_shader_kind; 
									                    OptimizationLevel: shaderc_optimization_level;
                                       TargetEnv       : shaderc_target_env; 
									                     EnvVersion      : shaderc_env_version;
									                     GLSLSource      : String):Boolean;
var
  Compiler: shaderc_compiler_t;
  Options: shaderc_compile_options_t;
  aResult: shaderc_compilation_result_t;
 // GLSLSource: AnsiString;
  SPIRVData: Pointer;
  SPIRVSize: NativeUInt;
  CreateInfo: TVkShaderModuleCreateInfo;
  VkResult: TVkResult;
begin
  Result := False;
  Assert(Device <> VK_NULL_HANDLE, 'Invalid Vulkan device handle');
  
  Assert((GLSLSource<>''), 'No GLSL Source code provided');
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
  Compiler := shaderc_compiler_initialize();
  if Compiler = nil then
    raise Exception.Create('Failed to initialize shaderc compiler');
  try
    Options := shaderc_compile_options_initialize();
    if Options = nil then
      raise Exception.Create('Failed to initialize shaderc options');
    try
      // Apply user-specified compiler options
      shaderc_compile_options_set_optimization_level(Options, OptimizationLevel);
      shaderc_compile_options_set_target_env(Options, TargetEnv, EnvVersion);
      // Add more options here if needed, e.g., shaderc_compile_options_set_warnings_as_errors, etc.

      aResult := shaderc_compile_into_spv(Compiler, PAnsiChar(GLSLSource), Length(GLSLSource),
           ShaderKind, 'shader.glsl', 'main', Options);  // Use generic filename; adapt entry point if needed
      if aResult = nil then
        raise Exception.Create('Shader compilation invocation failed');
      try
        if shaderc_result_get_num_errors(aResult) > 0 then
          raise Exception.CreateFmt('Shader compilation failed with %d errors: %s',
            [shaderc_result_get_num_errors(aResult), shaderc_result_get_error_message(aResult)]);

        SPIRVSize := shaderc_result_get_length(aResult);
        Assert(SPIRVSize > 0, 'Compiled SPIR-V size is zero');
        SPIRVData := shaderc_result_get_bytes(aResult);
        Assert(SPIRVData <> nil, 'Compiled SPIR-V data is null');

        // Create Vulkan shader module
        CreateInfo := Default(TVkShaderModuleCreateInfo);
       // FillChar(CreateInfo, SizeOf(CreateInfo), #0);
        CreateInfo.sType := VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
        CreateInfo.codeSize := SPIRVSize;
        CreateInfo.pCode := SPIRVData;  // SPIR-V is array of uint32_t

        VkResult := vkCreateShaderModule(Device, @CreateInfo, nil, @ShaderModule);
        if VkResult <> VK_SUCCESS then
          raise Exception.CreateFmt('Failed to create Vulkan shader module (error code: %d)', [Ord(VkResult)])
		else 
          Result := (ShaderModule <> VK_NULL_HANDLE);		
        Assert(ShaderModule <> VK_NULL_HANDLE, 'Created shader module is invalid');
      finally
        shaderc_result_release(aResult);
      end;
    finally
      shaderc_compile_options_release(Options);
    end;
  finally
    shaderc_compiler_release(Compiler);
  end;
end;

initialization
 Try
  LoadShadercLibrary;
 Except

 End;

finalization
  UnloadShadercLibrary;

end.