# VulkanShaders

Hand-built GLSL shaders for the public package (sources, and the compiled
`.spv` files). The particle system and glTF mesh shaders are in the PRO
package.

## Where the package looks for them

Only in this folder. `ShaderFolderPath` (`RunTime_Src/Vulkan_Components.pas`)
starts out empty and is filled in with this folder - the `VulkanShaders` whose
sibling `RunTime_Src` holds `Vulkan_Components.pas` - found by walking up from:

1. the module the package is in (the exe it is linked into, or its BPL)
2. the exe
3. the current directory

At each level both `<dir>\VulkanShaders` and a sibling checkout's
`<dir>\Vulkan_Package\VulkanShaders` are tried, so builds anywhere in this
checkout (the IDE's `Tests\Test Vulkan\23.0\Win64\Debug`, `Tests\Win32`) and in
a `Vulkan_Package_PRO` checkout beside it find this folder with no setup.
Failing those, a `VulkanShaders` folder next to the exe is used (a deployed
application: ship this folder beside it).

In the IDE the BPLs live outside the checkout, so the design package finds the
folder from the projects open in the IDE (above or beside them), then from the
IDE library path, the first time a shader is looked up.

`TvgShaderModule` resolves a shader file name with `vgFindShaderFile`: this
folder itself, then its subfolders. ProgramData, Program Files, Documents, TEMP
and the exe folder are not searched. Found paths are cached (and re-checked to
still exist); a miss is not cached, so a shader added later is found.
`vgClearShaderFileCache` forgets the cache. A missing shader is reported with
its name and the folders searched (`CustomAssert`: logged, and raised in
`DEBUG` builds).

To use another folder, set it before any shader module is enabled (setting it
back to `''` finds this folder again):

```pascal
ShaderFolderPath := 'D:\MyApp\Shaders\';
```

Another package's own shaders (e.g. PRO's glTF and particle shaders) go in
`AdditionalShaderFolders`, searched after `ShaderFolderPath`:

```pascal
AdditionalShaderFolders := ['D:\Vulkan_Package_PRO\VulkanShaders'];
```

Shaders generated at run time (the PRO `TvgShaderBuilder`) are written to
`ShaderFolderPath`, i.e. into this folder.

## Compiling

`.spv` files are compiled from the GLSL with `glslangValidator` from the Vulkan
SDK (`%VULKAN_SDK%\Bin\glslangValidator.exe -V shader.vert -o shader_vert.spv`),
or at run time by `Vulkan_Components_ShaderCompiler`.

## OBJ loader

A deployed application needs all `OBJ*.spv` files beside the others. `OBJ.vert` and
`OBJ.frag` provide unlit diffuse colour/texture display for `TvgSceneLoader_OBJ`.
Normals and material lighting properties are imported as data but not shaded.
The loader selects the float/double view-projection and no-selection,
storage-buffer-selection or image-selection variants automatically.

`CompileOBJShaders.ps1` rebuilds and validates all eight variants with
`glslangValidator` and `spirv-val` from the Vulkan SDK (both must be on PATH).
Diffuse UV transforms and brightness/contrast use specialization constants;
source UVs remain intact for future shaders using other material maps.
