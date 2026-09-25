# VulkanShaders

Hand-built GLSL shaders for the public package (sources, and the compiled
`.spv` files). The particle system and glTF mesh shaders are in the PRO
package.

## Where the package looks for them

`TvgShaderModule` finds a shader file by name with
`FileExistsInVariousLocations` (`RunTime_Src/Vulkan_Components.pas`), searching
these folders **and their subfolders**, in order:

1. `ShaderFolderPath` - default `C:\ProgramData\Datavis\VulkanShaders\`
2. the application's own folder
3. the temp folder
4. `%PROGRAMDATA%\Datavis\VulkanShaders\`
5. `%PROGRAMFILES%\Datavis\`
6. `Documents\Datavis\VulkanShaders\`

So either copy this folder's contents to `C:\ProgramData\Datavis\VulkanShaders\`:

```
xcopy /e /i /y VulkanShaders "%PROGRAMDATA%\Datavis\VulkanShaders"
```

or point the package at this folder before any shader module is enabled:

```pascal
ShaderFolderPath := 'D:\Vulkan_Package\VulkanShaders\';   // trailing backslash
```

## Compiling

`.spv` files are compiled from the GLSL with `glslangValidator` from the Vulkan
SDK (`%VULKAN_SDK%\Bin\glslangValidator.exe -V shader.vert -o shader_vert.spv`),
or at run time by `Vulkan_Components_ShaderCompiler`.
