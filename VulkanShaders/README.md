# VulkanShaders

Hand-built GLSL shaders for the public package (sources, and the compiled
`.spv` files). The particle system and glTF mesh shaders are in the PRO
package.

## Where the package looks for them

`TvgShaderModule` resolves a shader file name (e.g. `OBJ_vert.spv`) when it is
enabled, with `vgFindShaderFile` (`RunTime_Src/Vulkan_Components.pas`). It
looks directly in these folders, in order, each once:

1. `ShaderFolderPath` - default `C:\ProgramData\Datavis\VulkanShaders\`
2. `ExecutableFolderPath`, when set
3. the application's own folder
4. the nearest `VulkanShaders` folder above the application's folder, then
   above the current directory - so a build inside this checkout (the IDE's
   `Tests\Test Vulkan\23.0\Win64\Debug`, or `Tests\Win32`) finds this folder
   with no setup
5. `%PROGRAMDATA%\Datavis\VulkanShaders\`
6. `%PROGRAMFILES%\Datavis\`
7. `Documents\Datavis\VulkanShaders\`
8. the temp folder

Only if none has it are the subfolders of `ShaderFolderPath` searched. The
temp folder and the application's folder are never searched recursively.
Found paths are cached (and re-checked to still exist), so the many pipelines
sharing a shader look it up once; a miss is not cached, so a shader deployed
later is found. Call `vgClearShaderFileCache` after moving shader files.
A missing shader is reported with its name and every folder searched
(`CustomAssert`, so in `C:\ProgramData\Datavis\ErrorLogFile.txt`, and raised in
`DEBUG` builds). `vgShaderSearchFolders` returns the folder list.

Copies in `ShaderFolderPath` win over this folder: an older copy there
(e.g. from an earlier `xcopy`) is used instead of the one in the checkout.

To deploy, copy this folder's contents to `C:\ProgramData\Datavis\VulkanShaders\`:

```
xcopy /e /i /y VulkanShaders "%PROGRAMDATA%\Datavis\VulkanShaders"
```

or point the package at another folder before any shader module is enabled:

```pascal
ShaderFolderPath := 'D:\Vulkan_Package\VulkanShaders\';   // trailing backslash
```

## Compiling

`.spv` files are compiled from the GLSL with `glslangValidator` from the Vulkan
SDK (`%VULKAN_SDK%\Bin\glslangValidator.exe -V shader.vert -o shader_vert.spv`),
or at run time by `Vulkan_Components_ShaderCompiler`.

## OBJ loader

Copy all `OBJ*.spv` files along with the other public shaders. `OBJ.vert` and
`OBJ.frag` provide unlit diffuse colour/texture display for `TvgSceneLoader_OBJ`.
Normals and material lighting properties are imported as data but not shaded.
The loader selects the float/double view-projection and no-selection,
storage-buffer-selection or image-selection variants automatically.

`CompileOBJShaders.ps1` rebuilds and validates all eight variants with
`glslangValidator` and `spirv-val` from the Vulkan SDK (both must be on PATH).
Diffuse UV transforms and brightness/contrast use specialization constants;
source UVs remain intact for future shaders using other material maps.
