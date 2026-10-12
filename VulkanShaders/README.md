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

Run `Shader Compile.bat` (set `NOPAUSE=1` to skip its closing pause). It
compiles every shader in this folder in place with `glslangValidator` and checks
each with `spirv-val` (both from `%VULKAN_SDK%\Bin`), and reports any that fail.
Shaders can also be compiled at run time by `Vulkan_Components_ShaderCompiler`.

### Prebuilt shader variants

Each prebuilt shader is a single `.vert` / `.frag` source whose variants are
`#ifdef` blocks, compiled by the bat to the names a store loads:

| Variant | Define | File | Loaded when |
|---|---|---|---|
| vertex | - | `<Name>_vert.spv` | float view-projection |
| vertex | `VG_DOUBLE` | `<Name>Double_vert.spv` | the renderer's `ShaderUseDouble` |
| fragment | - | `<Name>_frag.spv` | the pipeline is not selectable |
| fragment | `VG_PICK` | `<Name>Pick_frag.spv` | `SelectMode = smStorageBuffer` (object IDs to the storage buffer, screen size push constant at offset 0) |
| fragment | `VG_PICK_IMAGE` | `<Name>PickImage_frag.spv` | `SelectMode = smImageBuffer` (object IDs to the `rg32ui` image) |

A store picks the variant itself when `TvgObjectStore.PrebuiltShaderVariants`
is True: `BaseVertName` / `BaseFragName` are the `<Name>`, and the pipeline
gets the suffix matching its renderer. With it False (the default) the names
are used as they are - for shaders generated for one pipeline.

To add a shader, write its source with the same three switches and add one
line per stage to the bat:

```
call :Vert  MyShader  MyShader.vert
call :Frag  MyShader  MyShader.frag
```

A fourth argument adds a define of the shader's own, built as a separate set
(`call :Frag OBJTexture OBJ.frag -DOBJ_TEXTURE`). `call :Plain <Name>` compiles
a shader with no variants (`TestTriangle`).

Bindings follow the renderer's fixed layout: set 0 binding 0 view-projection,
binding 1 the object-ID target, binding 2 lights; set 1 is the store's own
(e.g. its texture at binding 0).

## OBJ loader

A deployed application needs all `OBJ*.spv` files beside the others. `OBJ.vert` and
`OBJ.frag` provide unlit diffuse colour/texture display for `TvgSceneLoader_OBJ`.
Normals and material lighting properties are imported as data but not shaded.
Its stores set `PrebuiltShaderVariants`, so the float/double view-projection
and no-selection, storage-buffer-selection or image-selection variants are
picked automatically.

`OBJ` and `OBJTexture` (`-DOBJ_TEXTURE`, the diffuse map) are built from these
sources like every prebuilt shader, by `Shader Compile.bat`.
Diffuse UV transforms and brightness/contrast use specialization constants;
source UVs remain intact for future shaders using other material maps.
