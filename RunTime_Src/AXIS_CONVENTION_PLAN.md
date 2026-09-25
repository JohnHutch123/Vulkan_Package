# World Axis Convention - Plan

Branch: `refactor/world-axis-convention`

Goal: one global setting that selects the world convention.

| Convention | Horizontal plane | Up | Default "into screen" |
|---|---|---|---|
| `acYUp` (current, stays the default) | XZ | +Y | -Z |
| `acZUp` | XY | +Z | +Y |

## 1. What the survey found

Most of the package is already axis-neutral, which keeps this change small.

**Already neutral - no change needed**

- `TvgCamera.RecalculateViewMatrix` builds from `FUpVector`, not a literal.
- Projection matrices, `ScreenToWorldRay`, `WorldToScreenPoint`: screen/clip space, not world.
- Frustum extraction, `TvgAABB`, `vgFrustumTestAABB`, DataStore bounds: pure vector math.
- Generated GLSL (vertex, particle compute): world positions pass straight through;
  the compute shader's forces use whatever vectors the CPU uploads.
- `.y` uses in `Vulkan_Components.pas` (viewport / render area / image offsets) and
  `esdGrid2D` in Descriptors: 2D image space, not world.
- Handedness: Y-up to Z-up is a +90 degree rotation about X, `(x, y, z) -> (x, -z, y)`,
  determinant +1. Both conventions are right-handed, so **front-face winding, cull
  mode and the projection matrices do not change**.

**Hard-coded Y-up - must change**

| Location | What | Note |
|---|---|---|
| `Vulkan_Components_Camera.pas:594-596` | constructor: position (0,0,5), up (0,1,0) | In Z-up, looking along -Z with up +Z is **degenerate** (up parallel to view direction -> NaN view matrix). Must convert both, not just up. |
| `Vulkan_Components_Camera.pas:626-629` | `InitializeAsDefault`: (0,2,5) up (0,1,0) | |
| `Vulkan_Components_Scene_Renderer.pas:1799-1808` | `GetDragPlaneNormal`: 0 = XZ horizontal (0,1,0), 1 = XY front, 2 = YZ side | Reinterpret as semantic planes: horizontal / front / side. |
| `Vulkan_Components_Scene_Renderer.pas:399, 461` | comments on `DragPlaneAxis` | |
| `Vulkan_Components_Particles.pas:754` | force default `fVectorY := -1` (gravity down) | |
| `Vulkan_Components_Particles.pas:983-984` | emitter default velocity: Y in 2..6 (upward fountain) | See min/max gotcha below. |
| `Samples/ParticleDemo/ParticleDemo.pas:181-191` | gravity (0,-1,0), attractor at (0,2,0), vortex axis (0,1,0) | |

**Existing tests** (`AABBTest`, `BoundsTest`, `CullTest`, `FrustumTest`) pass explicit
camera vectors and test pure math. They are correct under either convention and
stay as-is - they become the regression guard that `acYUp` behaviour is unchanged.

**Not in the repo's live code**

- glTF: `Vulkan_Components_Scene_GLTF.pas` is a commented-out exporter stub and the
  sample loader is a skeleton. glTF is Y-up by spec, so a future importer/exporter
  must apply the conversion matrix from step 1 at the root node. The matrix is
  provided now; wiring it in waits for a real importer.
- `RunTime_Src/DRAFT/` is git-ignored; it has copies of the ToolManager code and is
  left alone.

## 2. Design

### Runtime global with a compile-time default

New unit `Vulkan_WorldAxes.pas`:

```pascal
type
  TvgAxisConvention = (acYUp, acZUp);

function  vgAxisConvention: TvgAxisConvention;
procedure vgSetAxisConvention(aValue: TvgAxisConvention);

// Basis for the active convention
function vgWorldUp      : TpvVector3;   // (0,1,0) | (0,0,1)
function vgWorldForward : TpvVector3;   // (0,0,-1) | (0,1,0)
function vgWorldRight   : TpvVector3;   // (1,0,0) both

// Author a vector in Y-up terms, get it in the active convention.
// Identity under acYUp; (x, y, z) -> (x, -z, y) under acZUp.
function vgFromYUp(const aX, aY, aZ: Single): TpvVector3; overload;
function vgFromYUp(const aV: TpvVector3): TpvVector3; overload;
function vgToYUp  (const aV: TpvVector3): TpvVector3;

function vgUpComponent(const aV: TpvVector3): Single;   // v.y | v.z

// For asset import/export (glTF, OBJ, ...), which are Y-up files
function vgYUpToWorldMatrix: TpvMatrix4x4;
function vgWorldToYUpMatrix: TpvMatrix4x4;
```

- Initial value comes from `VulkanPackage.inc`: `{$DEFINE VG_WORLD_Z_UP}` (commented
  out by default) selects `acZUp`. Existing projects are unchanged.
- **Set once, at startup.** The convention decides the defaults of objects as they
  are created; it never rotates data that already exists. To stop mixed-convention
  scenes, the objects that bake it into their defaults count themselves:
  `TvgCamera`, `TvgForceField` and `TvgParticleEmitter`. `vgSetAxisConvention`
  refuses a change while any are alive; it returns `False` and calls
  `CustomAssert`. (The first draft counted `TvgScene`, but a scene bakes nothing
  in.) Tests can switch between cases by freeing their objects first.

### As implemented

- `vgPlaneNormal(wpHorizontal | wpFront | wpSide)` holds the drag-plane mapping,
  so it can be tested without a ToolManager. Under Y-up it returns exactly the
  old normals.
- `vgRangeFromYUp` handles the min/max re-sort from step 4.
- `Orbit` needed more than the pitch clamp. Its yaw step dropped the Rodrigues
  term and normalised `Up x dir`, so each yaw while pitched pulled the eye's
  height towards the horizon. It is now an exact rotation about up. See the note
  in `MIGRATION_GUIDE.md`.

Why not a compile-time switch only: every package in `Delphi 11/12/13` would need a
rebuild to change it, and one test exe couldn't cover both conventions.

## 3. Implementation steps

1. **Add `Vulkan_WorldAxes.pas`** as above. Add to the `contains` lists of
   `Delphi 11/12/13/VulkanPkgR280.dpk`, the `Delphi 12/13` `.dproj` files, and
   `Samples/TestVulkan/VulcanTest.dpr/.dproj`. Add the `.inc` define (commented).
2. **Camera.** The constructor and `InitializeAsDefault` use `vgFromYUp(...)` for position
   and `vgWorldUp` for up. Register/unregister the live-instance count.
3. **ToolManager drag plane.** 0 = horizontal -> `vgWorldUp`, 1 = front ->
   `vgWorldForward`, 2 = side -> `vgWorldRight`. Keep the property an `Integer`
   (no DFM in the repo stores it, but changing the type would break any user DFM
   that does). Update comments to say "horizontal / front / side".
4. **Particles.**
   - `TvgForceField` default vector -> `-vgWorldUp`.
   - Emitter default velocity range -> converted through `vgFromYUp`.
     **Gotcha:** the conversion negates a component (`y' = -z`), so a converted
     `(min, max)` pair can come out with min > max on that axis. Convert both corners,
     then take the per-component min/max. Half-extents take `Abs`.
   - Add `TvgForceFields.AddGravityDown(aStrength)` so callers don't write axis literals.
   - Published emitter/force properties keep their X/Y/Z names: they are world axes.
     Values already saved in a DFM are the user's data and are not converted.
5. **ParticleDemo.** Use `AddGravityDown`, `vgFromYUp(0, 2, 0)` for the attractor, and
   `vgWorldUp` for the vortex axis. The demo then looks the same under both conventions.
6. **Tests: new `Tests/AxisConventionTest.dpr`**, added to `RunTests.bat`. It runs every
   case under `acYUp` then `acZUp`:
   - basis is right-handed: `Right x Forward` ... `= Up`, `det(vgYUpToWorldMatrix) = +1`
   - `vgToYUp(vgFromYUp(v)) = v`; `vgUpComponent(vgWorldUp) = 1`
   - default camera: view matrix finite, forward not parallel to up, camera is above
     the horizontal plane (`vgUpComponent(Position) > 0` after `InitializeAsDefault`)
   - `Orbit` yaw keeps the height along the world up axis constant
   - a horizontal drag hits the plane at up-component 0
   - force default points down; emitter default velocity has a positive up component
     and min <= max on every axis
   - changing the convention while a camera is alive asserts
7. **Pre-existing edge, same branch (small):** `Orbit` has no pitch clamp; pitching to
   the pole makes `FUpVector.Cross(direction)` zero and the view matrix NaN. It is
   convention-independent, but the new orbit tests will walk into it. Clamp pitch
   to about +/-89 degrees.
8. **Docs.** Add a section to `MIGRATION_GUIDE.md`: how to select Z-up, the
   set-once rule, stored data isn't converted, use `vgYUpToWorldMatrix` for Y-up assets.
9. **Verify.** `Tests\RunTests.bat` (all five tests). Then run `ParticleDemo` and
   `VulcanTest` once with the define on and once off. Orbit, pan, drag an object on the
   horizontal plane, and check that particles fall "down".

## 4. Cost estimate

| Step | Size (lines) | Developer effort |
|---|---|---|
| 1 `Vulkan_WorldAxes.pas` + package lists | ~180 new, ~12 edits | 2.5 h |
| 2 Camera | ~25 | 1 h |
| 3 ToolManager | ~20 | 0.5 h |
| 4 Particles (incl. min/max handling, `AddGravityDown`) | ~40 | 1.5 h |
| 5 ParticleDemo | ~10 | 0.5 h |
| 6 `AxisConventionTest.dpr` | ~250 new | 3 h |
| 7 Orbit pitch clamp | ~10 | 0.5 h |
| 8 Docs | ~60 | 1 h |
| 9 Manual visual check, both conventions | - | 1-2 h |
| **Total** | **~600 lines** (~45% tests) | **~11-12 h, about 1.5-2 dev days** |

Risk: **low to medium**. The core math is already neutral and `acYUp` stays the
default, so existing users see no change. Existing tests guard that.
The real risks:

- Data authored for one convention loaded under the other: DFM-stored particle
  values, or a user's hand-placed camera. This is documented, not converted.
- Future asset loaders forgetting the Y-up conversion. The matrix is provided and
  documented for that.
