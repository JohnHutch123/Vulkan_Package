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

To use PRO, clone both repositories side by side and build the public
packages first:

```
<parent>\Vulkan_Package        (public)
<parent>\Vulkan_Package_PRO    (PRO: its packages require VulkanPkgR280)
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
- **Edit everything:** right-click > *Edit Vulkan Session...* opens an editor for the published
  properties of every session component (read only while the session runs).
- **At run time:** call `EnableSession` once the window's form is showing (e.g. in `OnShow`),
  `DisableSession` to shut down.

Files (all in `Design_Src`): `Vulkan_DataModule.pas` (runtime base class, in `VulkanPkg_VCLR280`),
`VulkanPkg_DataModuleReg.pas` and `VulkanDataModuleEditFM.pas/.dfm` (IDE side, in `VulkanPkg_VCLD280`).

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
