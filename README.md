### What this repo is
A **Delphi/Object Pascal Vulkan component package** (mainly VCL-oriented) built on top of **PasVulkan** bindings/framework.

The root `README.md` is minimal, so most real documentation is in `RunTime_Src/*.md` and `Tests/README.md`.

---

### Public and PRO packages
This repository is the **public** core. Extras live in the private
[**Vulkan_Package_PRO**](https://github.com/JohnHutch123/Vulkan_Package_PRO)
repository, which builds on this one. It is available under licence from
Datavis (johnh@datavis.com.au); the link works once you have been given access.

| Public (this repo) | PRO |
|---|---|
| Instance/device/swapchain/pipeline components, descriptors, data stores, scene and render engine base, `TvgRenderEngine_Single`, camera, lights, HUD, compute, shader compiler, VCL/SDL2 windows, hand-built shaders (`VulkanShaders/`) | Particle system, glTF scene loader, shader builder (unit and app), `TvgCommThread_RenderEngine` (multi-threaded recording) |
| `TvgToolManager`: camera control, CPU/GPU picking, selection, zoom to all | `TvgEditToolManager` (a `TvgToolManager` descendant): edit tools, undo/redo, snapping, work plane |
| `TvgSceneLoaderStorer` (abstract loader base) | Natural neighbour, spring system, Delaunay display |

`TvgToolManager` exposes virtual hooks (`ToolMouseDown/Move/Up`,
`DoCameraDrag`, `DoSelectionChanged`, `ForgetObject`, `StoreGone`,
`SceneCleared`) so a descendant can add interactive tools without the scene
knowing about them.

The base runtime/design package suffix follows the Delphi release:

| Delphi | Runtime package | Design package |
|---|---|---|
| XE8 | `VulkanPkgR220` | `VulkanPkgD220` |
| 11 | `VulkanPkgR280` | `VulkanPkgD280` |
| 12 | `VulkanPkgR290` | `VulkanPkgD290` |
| 13 | `VulkanPkgR370` | `VulkanPkgD370` |

To use PRO, clone both repositories side by side and build the public
packages first:

```
<parent>\Vulkan_Package        (public)
<parent>\Vulkan_Package_PRO    (PRO packages require the matching VulkanPkgRxxx)
```

```
git clone https://github.com/JohnHutch123/Vulkan_Package.git
git clone https://github.com/JohnHutch123/Vulkan_Package_PRO.git
```

### Licence
The public package is released under the **zlib licence** - see `LICENSE`.
It may be used in closed-source and commercial applications. The PRO
repository is not covered by this licence.

---

### Vulkan session data module (`TvgVulkanDataModule`)
A `TDataModule` descendant that holds a whole Vulkan session -
`TvgInstance` -> `TvgPhysicalDevice` -> `TvgScreenRenderDevice` -> `TvgLinker` -
and connects it to a `TvgWindowVCL` on any form.

- **Create one:** File > New > Other > Delphi Files > *Vulkan Session Data Module*.
- **Build the session:** right-click the module > *Build Vulkan Session* (adds and wires the components).
- **Connect the window:** set the module's `Window` property to a `TvgWindowVCL`.
- **Enable / disable at design time:** right-click > *Enable/Disable Vulkan Session*, or toggle `SessionActive`.
- **More windows:** right-click > *Add Linker* (or drop a `TvgLinker` and set its `ScreenDevice`), then set
  the second `TvgWindowVCL`'s `VulkanLink` to it. Every linker connected under the instance is part of the
  session.
- **Connect in the Object Inspector:** `PhysicalDevice.Instance`, `ScreenDevice.PhysicalDevice`,
  `Linker.ScreenDevice` and `VulkanWindow.VulkanLink` drop down the matching components in every open
  form/module, as a dataset's `Connection` does.
- **Test like a dataset:** set `Active` to True on any session component (instance, device, linker or
  window) at design time to start the whole session it belongs to; the reason is shown if it can't start.
- **Scene:** drop a renderer (e.g. `TvgRenderEngine_Single`) and set the module's `Renderer`, then
  right-click > *Add Scene*. *Load Scene File...* picks a file and loads it with a registered scene loader:
  `SceneLoaderType` drops down the registered loaders (blank = choose by file extension), `SceneFileName`
  has a file-open button, and `LoadSceneOnEnable` reloads it whenever the session is enabled, at design
  time too. Any `TvgScene` also gets *Load Scene File...* / *Clear Scene* on its menu. In code:
  `DM.LoadScene('model.glb')`.
- **Tool manager:** right-click > *Add Tool Manager* creates a `TvgToolManager` (camera orbit mode) connected
  to the primary linker, scene and renderer, so the window can be orbited/picked; `ZoomAllOnLoad` (default on)
  frames each loaded scene. A PRO `TvgEditToolManager` can be assigned to `ToolManager` instead. Each extra
  window gets its own tool manager: set its linker's `ToolManager` (or the tool manager's `Linker`).
- **Scene loaders** register themselves in `Vulkan_SceneLoaders` (core package), e.g. in the PRO glTF unit:
  `RegisterSceneLoader(TvgSceneLoaderStorer_GLTF, 'glTF', 'glTF 2.0 scene', '.gltf;.glb', 'FileName');`
  where the last argument is the loader's published file-name property.
- **Edit everything:** right-click > *Edit Vulkan Session...* opens an editor showing the session as it is
  connected (Instance > devices > linkers > windows, plus anything not yet connected) and the published
  properties of each component (read only while the session runs).
- **At run time:** call `EnableSession` once the window's form is showing (e.g. in `OnShow`),
  `DisableSession` to shut down.

See [`RunTime_Src/DATA_MODULE_GUIDE.md`](RunTime_Src/DATA_MODULE_GUIDE.md) for a step-by-step guide.

Files: `RunTime_Src/Vulkan_DataModule.pas` (runtime base class, in `VulkanPkg_VCLR280`). The IDE registration and
editor (`Design_Src/VulkanPkg_DataModuleReg.pas`, `Design_Src/VulkanDataModuleEditFM.pas/.dfm`) are in
`VulkanPkgD290` for Delphi 12; other Delphi folders keep them in their `VulkanPkg_VCLD...` design package.

---

### SDL2 window (`TvgSDL2Window`)

`TvgSDL2Window` presents a session in an SDL2 window instead of a VCL control. It is created in code and
linked like `TvgWindowVCL`:

```pascal
Window := TvgSDL2Window.Create(Self);
Window.Caption    := 'Model';
Window.VulkanLink := Linker1;
Instance1.Active  := True;      // creates the SDL window and its surface
```

- **Events:** call `TvgSDL2Window.ProcessEvents` regularly (`Application.OnIdle`, a timer or your own loop).
  It forwards mouse, wheel and keys to the linker and its tool manager, rebuilds the swap chain on resize and
  repaints on expose.
- **Closing** fires `OnClose`; unless it refuses, that window's linker is disabled and the SDL window
  destroyed, while other windows keep running. `Active := True` opens it again.
- **SDL** is started with the first window and stopped with the last, so linking the unit alone does not
  touch it. Needs SDL 2.0.6 or later.
- **Package:** `VulkanPkg_SDL2R280` (runtime, requires the matching `VulkanPkgRxxx`) builds with `PasVulkanUseSDL2`,
  `PasVulkanUseSDL2WithVulkanSupport` and `PasVulkanUseSDL2WithStaticVulkanSupport`. `PasVulkan.SDL2`
  links against `sdl2.dll` on Win32 but `sdl264.dll` on Win64, so a Win64 application has to ship SDL2.dll
  under that name.

File: `RunTime_Src/Vulkan_WindowSDL2.pas`.

---

### Key technologies
- **Language:** Object Pascal (Delphi)
- **Graphics API:** Vulkan (`Vulkan.pas`, `TVk*` types)
- **Core dependency:** **PasVulkan** (`PasVulkan.Math`, `PasVulkan.Framework`, etc.)
- **UI/frameworks:** VCL (primary), plus optional SDL2 windowing
- **Shader path:** GLSL → SPIR-V via `glslangValidator` (`VULKAN_SDK`)

---

### Repository structure
- `/home/runner/work/Vulkan_Package/Vulkan_Package/RunTime_Src`  
  Main runtime units (core engine/components). Key files:
  - `Vulkan_Components.pas` (base component/state model and shared types)
  - `Vulkan_Components_Scene_Renderer.pas` (scene/object-store/render flow)
  - `Vulkan_Components_DataStore.pas` (vertex/index/instance storage model)
  - `Vulkan_Components_Camera.pas`, `Vulkan_WorldAxes.pas`, descriptors/compute/etc.
- `/home/runner/work/Vulkan_Package/Vulkan_Package/Design_Src`  
  Delphi design-time editors, property editors, and component icons.
- `/home/runner/work/Vulkan_Package/Vulkan_Package/VulkanShaders`  
  Hand-built GLSL shaders and where the package looks for them.
- `/home/runner/work/Vulkan_Package/Vulkan_Package/Samples/Renderers`  
  The single-thread render engine `TvgRenderEngine_Single` and its packages.
- `/home/runner/work/Vulkan_Package/Vulkan_Package/Tests`  
  Console `.dpr` tests (no external test framework), run by `RunTests.bat`.
- `/home/runner/work/Vulkan_Package/Vulkan_Package/Delphi 11`, `Delphi 12`, `Delphi 13`, `Delphi XE8`  
  Version-specific Delphi package/project files (`.dpk`, `.dproj`, `.groupproj`).

---

### How the code is organized conceptually
It’s a **component-oriented architecture**:
- Base classes derive from `TComponent` (`TvgBaseComponent` etc.)
- Scene/object/data-store abstractions manage geometry and renderer linkage
- Vulkan wrappers handle descriptors/pipelines/device-level resources
- Window adapters (VCL/SDL2) expose platform surface callbacks
- Design-time packages expose these components/editors inside Delphi IDE

---

### Build/test expectations
- CI (`.github/workflows/delphi-tests.yml`) is designed for a **self-hosted Windows runner** with Delphi installed.
- Tests are CPU-focused and compile/run real runtime units via `dcc32`.
- Repo expects an external PasVulkan checkout (paths referenced from tests/packages).
