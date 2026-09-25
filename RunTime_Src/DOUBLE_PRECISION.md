# Double Precision and Survey Coordinates

Branch: `refactor/double-precision-camera`

Goal: move the camera and view-projection math to double precision
(`PasVulkan.Math.Double`), keep vertex and colour data in the data stores as
float32 (`PasVulkan.Math`), and render real-world survey data to the
millimetre.

The data this is built for:

- positions with **5 or 6 digits before the decimal** and **3 after**
- one dataset spans **under 10,000 units** ("view all" is a 4-digit box)

## 1. The numbers behind the design

float32 has 24 bits of mantissa, so the gap between neighbouring values grows
with magnitude:

| Magnitude | float32 step |
|---|---|
| 4,096 - 8,192 | 0.49 mm |
| 8,192 - 16,384 | 0.98 mm |
| 65,536 - 131,072 | 7.8 mm |
| 524,288 - 1,048,576 | 62.5 mm |

Two consequences:

1. **Camera math must be double.** The view matrix's translation is the
   camera's own position, a six-digit number. So is the D term of every
   frustum plane.
2. **Vertices can stay float32 only relative to a nearby origin.** A 3-decimal
   value survives a round trip through float32 exactly while it is under
   16,384. Measured over 400,000 random millimetre values: none lost below
   16,384, about a quarter lost below 32,767.

With the origin at the dataset centre and the dataset under 10,000 across,
offsets stay near 5,000, well inside that limit.

## 2. Design

### Three coordinate spaces

| Space | Precision | Used by |
|---|---|---|
| **world** | double | `TvgCamera`, ToolManager positions and events, `TvgScene.WorldOrigin` |
| **local** = world - `WorldOrigin` | float32 | vertex data, `TvgAABB` bounds, the published cull volume |
| **clip** | - | what the view-projection produces |

With the default origin (0,0,0), local and world are the same, and the package
behaves as it did before.

### Where the origin enters

`TvgScene.PrepareFrameGlobalData` publishes, for each renderer:

- `Cam.GetViewProjectionMatrixForAspect(Aspect, WorldOrigin)`: maps a **local**
  position to clip space.
- `Cam.GetFrustumPlanesForAspect(Aspect, WorldOrigin)`: planes in **local**
  coordinates, the same space as the float32 bounds, so culling still works.

Both build the view from `FPosition - aOrigin`, subtracted **before** it enters
the matrix. The eye and the origin are both six-digit numbers that nearly
cancel. Their difference is exact in double, whereas the product
`View * Translate(origin)` would add and cancel million-unit terms. Because of
this, the matrix is small-valued and survives narrowing to a float32 `mat4`.

### What is double, what stays single

| Double | Single (unchanged) |
|---|---|
| `TvgCamera`: position, target, up, lens, every cached matrix | vertex, colour, normal, texcoord data |
| `TvgFrustrumPlanes` | `TvgAABB` (built from float32 vertices) |
| `IvgGlobalDataTarget.SetViewProjectMatrix` | instance matrices (`TvgMatrix4x4S`) |
| ToolManager drag point, plane normal, ray maths, events | particle GPU records |
| `Vulkan_WorldAxes` vectors, matrices and scalars | |

### dmat4 or mat4 on the GPU

`TvgBaseRenderEngine.UsesDoubleViewProjection` decides:

- `ShaderUseDouble` off gives a **mat4** (`TvgDescriptorArray_UBO_4x4MatrixS`).
- `ShaderUseDouble` on gives a **dmat4** (`TvgDescriptorArray_UBO_4x4MatrixD`).
  `TvgRenderEngine` still falls back to a `mat4` if the device is known to lack
  `shaderFloat64`. That is checked in `SetEnabled`, the first point at which the
  device's features are known.

The global descriptor, the `USE_DOUBLE` specialisation constant and the
pipeline's `DoubleON` all follow this one answer. The descriptor item is
re-typed in place, so it keeps its binding.

Why a fallback is needed: Intel states that integrated graphics in 11th Gen
Core processors and newer, and Arc discrete GPUs, do not support
`shaderFloat64` and that there is no plan to add it
([Intel support article 000089817](https://www.intel.com/content/www/us/en/support/articles/000089817/graphics.html)).

Measured cost (`PrecisionTest`: camera 2 m away, 20,000 samples):

| Path | Worst on-object error |
|---|---|
| origin + dmat4 | **0.34 mm** |
| origin + mat4 (float32 GPU arithmetic emulated) | **0.97 mm** |
| no origin (the package before this branch) | 43.3 mm |

## 3. Commits

| Commit | What |
|---|---|
| `88f2857` | Fix the build: `Vulkan_WorldAxes` had been half-converted (`TpvMatrix4x4D.Identity` does not exist, a malformed identity matrix, `out` parameter type mismatches). Scalars in `vgFromYUp` / `vgUpComponent` go to double. `PasVulkan.Math.Double` is added to the Delphi 11/12/13 packages. |
| `374aa55` | Camera, frustum planes, renderer interface, descriptor upload and ToolManager to double. Test helpers too. |
| `ac04579` | Four camera bugs (section 5). New `CameraTest`. |
| `c108432` | `TvgScene.WorldOrigin`, `TvgObject.SetVertexWorldPosition`, the camera's origin overloads, the scene publishing local matrix and planes, drag planes through the origin. New `PrecisionTest`. |
| `1c01603` | `mat4` fallback, `UsesDoubleViewProjection`, and a fix in `TvgDescriptorItem.SetDescriptorType`. |

## 4. Changes that affect existing code

### Compile-time

- **`TvgCamera`**: vectors are `TpvVector3D`, matrices `TpvMatrix4x4D`, and
  scalars (FOV, near, far, aspect, ortho bounds, orbit/pan/zoom amounts,
  `Distance`) are `Double`.
- **`IvgGlobalDataTarget.SetViewProjectMatrix`** and
  `TvgBaseRenderEngine.SetViewProjectMatrix` take a `TpvMatrix4x4D`. Update any
  class of your own that implements or overrides them.
- **`TvgDescriptorArray_UBO_4x4MatrixD.UpdateMatrixValues`** takes
  `const TpvMatrix4x4D`.
- **`TvgToolManager.OnObjectMoved` / `OnObjectAddReq`** deliver `TpvVector3D`.
  These events are published, so handlers assigned in a form need their
  parameter type changed; the IDE reports the mismatch when the form loads.
  No form in this repository assigns them.
- **`vgFromYUp(X, Y, Z)`** takes, and **`vgUpComponent`** returns, `Double`.
- **`TCameraUpdateFlags`** gains `cfViewProjectionDirty`.

> **Silent narrowing.** `PasVulkan.Math.Double` converts double types to
> single *implicitly*. Code that stores a camera result in a `TpvVector3` or
> `TpvMatrix4x4` still compiles and quietly drops back to float32. See
> section 6 for how this branch checked for it.

### Behaviour

| Change | Before | Now |
|---|---|---|
| Renderer view-projection with `ShaderUseDouble` off (the default) | always `dmat4` | `mat4`. Set `ShaderUseDouble` for `dmat4` where the GPU supports it. |
| `GetViewProjectionMatrix`, `GetFrustumPlanes`, `WorldToScreenPoint` | used the matrix built in the constructor | current |
| `ScreenToWorldRay` | direction from the world origin, not the eye | the ray through the pixel. A new overload also returns its origin. |
| Aspect used by `ScreenToWorldRay` / `WorldToScreenPoint` | camera's stored `AspectRatio` | the viewport's, as the renderer draws |
| Orthographic camera on screen | upside down | right way up |
| `Zoom` | step size from an uninitialised variable | 10% per unit, as documented |
| ToolManager drag plane | through (0,0,0) | through `Scene.WorldOrigin` (same by default) |

## 5. Bugs fixed along the way

| Bug | Symptom | Fix |
|---|---|---|
| Stale cached view-projection | Each getter cleared a dirty flag and then tested the same flag, so the product was never rebuilt. A target at screen centre came out at (530, 338) of (500, 500). | `cfViewProjectionDirty` and `UpdateMatrices` |
| `ScreenToWorldRay` origin | No perspective divide and no eye subtraction. The centre ray was 6° off at (1000, 0, 1000) and pointed almost straight up at (0, 100000, 0). | Unproject a near and a far point in eye space, then apply the rigid inverse view |
| Orthographic Y | `BuildProjectionForAspect` negated Y for perspective only | Negated for orthographic too |
| `Zoom` | `distance := Distance`, where the local variable hides the property | Reads `(FPosition - FTarget).Length` |
| `TvgDescriptorItem.SetDescriptorType` | Named the new descriptor while the old one still held that name, so any named item changing type raised `EComponentError` | Name it after the old one is freed |
| `Vulkan_WorldAxes` build break | `main` did not compile | Commit `88f2857` |

## 6. Verification

Done on this branch:

- **Test suite.** All seven programs in `Tests\RunTests.bat` pass, including
  the two new ones:
  - `CameraTest`: cached-matrix freshness through every getter order; pixel ->
    ray -> pixel round trips (worst error below 1e-6 px) at the origin, at
    (1000, 0, 1000), at (0, 100000, 0) and at survey coordinates, perspective
    and orthographic, with a viewport aspect different from the camera's;
    screen orientation; `Zoom`.
  - `PrecisionTest`: 3-decimal round trip; the projection error table above;
    culling in local space; `WorldOrigin` rules; renderer `dmat4` / `mat4`
    selection, upload and generated shader text.
- **Mutation checks.** Reintroducing the stale-product bug, the orthographic
  flip or the descriptor naming bug makes the tests fail, and so does writing
  vertices past the 16,384 limit.
- **Silent-narrowing check.** A copy of `PasVulkan.Math.Double` with its 11
  implicit double-to-single operators removed, placed first on the unit path,
  turns every accidental narrowing into a compile error. All seven tests and
  `Samples\TestVulkan\VulcanTest` compile against it.
- **Full sample build.** `Samples\TestVulkan\VulcanTest.dpr` compiles with
  `dcc32`. It pulls in every runtime unit except seven (`DetectImageFormat`,
  `ToolManagerDraft`, `Vulkan_Components_Scene_GLTF`,
  `Vulkan_Components_ShaderCompiler_DLL`, `Vulkan_MemoryPool`,
  `Vulkan_OMNIThread_Renderer`, `Vulkan_WindowSDL2`), and none of those seven
  use an API this branch changed.
- **Shaders.** Vertex shaders generated for both paths were compiled with
  `glslangValidator` and passed `spirv-val`. The `mat4` shader declares no
  `Float64` capability, including with a leftover `USE_DOUBLE` header; the
  `dmat4` shader does.

**Not done, and needed before merging** (these need a GPU and the IDE):

1. Install the Delphi 12/13 packages in the IDE (only command-line builds of
   the tests and `VulcanTest` were done).
2. Run `VulcanTest` / `ParticleDemo` with `ShaderUseDouble` on and off: the
   image must not move or flip between them.
3. Run one orthographic view and check it is the right way up.
4. On an Intel Xe or Arc GPU with `ShaderUseDouble` on: the renderer should
   fall back to `mat4` and draw.
5. Load a survey dataset with `WorldOrigin` at its centre; zoom to about 1 m
   and orbit. There should be no jitter. Picking and dragging should land
   under the cursor.

## 7. Follow-ups, not in this branch

- **Depth precision is the next limit.** "View all" of a 10,000-unit dataset
  needs a far plane around 20 km, while zooming to 2 m wants a near plane
  around 0.1, a ratio of about 200,000. The perspective path produces OpenGL
  -1..1 depth, which Vulkan clips to 0..1. Expect z-fighting at distance. Fit
  near/far to the data each frame, or use reversed-Z with a float depth buffer.
- **Instance matrices** (`TvgMatrix4x4S`) are float32 and must also be relative
  to `WorldOrigin` when they place data at survey coordinates.
- **`TvgObject.AllocateVertices` then `AddVertex`** adds a vertex *after* the
  allocation rather than filling it, leaving an unwritten vertex at the local
  origin inside the bounds. Found while writing `PrecisionTest`; not changed.
- **The camera's own projection** (`GetProjectionMatrix`,
  `GetViewProjectionMatrix`, `GetFrustumPlanes`) is still OpenGL-style (Y up,
  the camera's stored aspect), unlike the render path. Consider aligning it.
- **Particles** simulate in float32 on the GPU, so a particle system at survey
  coordinates needs its emitter and bounds expressed relative to
  `WorldOrigin`.
- The legacy `Delphi XE8` package lists were not updated.
