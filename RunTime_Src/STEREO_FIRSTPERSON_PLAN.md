# Stereo (side-by-side) view and first-person walk — plan

Status: plan only, nothing implemented (2026-11-23).
Scope: core Vulkan_Package. PRO adds real VR (OpenXR) and a Delaunay ground
provider later, through interfaces defined here.

---

## What exists today (survey)

| Area | Where | Relevance |
|---|---|---|
| Camera | `TvgCamera` (`Vulkan_Components_Camera.pas`) — Orbit / Pan / Dolly / LookAt, `BuildViewForOrigin`, `BuildProjectionForAspect`, double precision | Eye matrices build on these. No eye/IPD support, no look-around-the-eye. |
| VP to GPU | `TvgScene.PrepareFrameGlobalData` (`Vulkan_Components_Scene_Renderer.pas:3878`) → `SetViewProjectMatrix` → one `UBO_4x4Matrix{S,D}` per frame slot | Must carry two matrices. |
| Culling / LOD | same routine: `SetFrustumPlanes`, `SetLodView` from one camera and one aspect | Needs a frustum that covers both eyes. |
| Viewport | **Static** in every pipeline: full swapchain size (`Vulkan_Components.pas:16495`) | Two-viewport rendering would mean dynamic viewport state in every pipeline. |
| Offscreen | `RT_FRAME` + `TvgFrame.FrameToScreenCopy_Record` / `RecordPresentAndHUD` blits the frame image to the swapchain | The natural place to put the two eyes side by side. |
| Multiview | Device feature flags `Multiview` etc. exist (`Vulkan_Components.pas:984`), nothing uses them | Basis of the recommended route. |
| Recording | Primary + worker secondaries re-recorded every frame (`StartRenderEnginePrepare`, `AddSceneRenderCommands`) | Drawing everything twice would double that CPU work. |
| Input | `TvgToolManager`: orbit/pan/dolly bindings, `DoKeyDown`, `DoMouseWheel`; **no KeyUp**, no per-frame tick | Walking needs held keys and a timed update. |
| Surface data | Core: object vertices/primitives (picking already reads them). PRO: `TvgDelaunay2D.FindTriangle(x, y)` | Ground following. |

**First-person / walk does not exist yet** — this plan adds it.

---

## Part A — Stereo side-by-side in one window

### A1. Approach: multiview into a 2-layer image, then composite into the window halves

Two ways to get two eyes into one window:

1. **Draw the scene twice**, each time with half-window viewport and its own
   VP. Every pipeline needs dynamic viewport/scissor, every bind needs
   `CmdSetViewport`, the workers record everything twice, and the VP descriptor
   has to switch between eyes partway through the pass. It touches a lot of core
   code, and the CPU cost doubles.
2. **Multiview (`VK_KHR_multiview`, core in Vulkan 1.1)** — **recommended.**
   Render once with `viewMask = 0b11` into 2-layer colour and depth images. The
   vertex shader picks `VP[gl_ViewIndex]`, and the GPU sends each draw to both
   layers. Then the composite step copies layer 0 into the left half of the
   swapchain image and layer 1 into the right half.

Why multiview:
- Recording happens once. Workers, secondaries and culling stay as they are.
- It is the same shape OpenXR wants: XR swapchains are 2-layer arrays and each
  eye has its own asymmetric projection. PRO VR then mostly replaces where the
  matrices come from and where the layers go. The render path stays the same.
- The package already has an offscreen frame (`RT_FRAME`) with a copy to the
  screen. Stereo forces that path and turns the one blit into two regions.

Cost: vertex shaders need a stereo variant (below). Picking and pixel
read-back must say which layer they read.

Multiview is supported on every desktop Vulkan 1.1 driver and on most Android
drivers. If the device lacks it, stereo is refused with a clear message.
There is no fallback to drawing twice.

### A2. Eye maths — `Vulkan_Components_Camera.pas`

New `TvgStereoSettings` (TPersistent, owned by `TvgCamera`, published):

| Property | Default | Meaning |
|---|---|---|
| `Enabled` | False | |
| `EyeSeparation` | 0.064 | IPD in **scene units**. Use with `UnitsPerMetre` when the scene is not in metres. |
| `Convergence` | 10.0 | Zero-parallax distance: objects at this distance appear at screen depth. |
| `SwapEyes` | False | For cross-eyed free viewing / wrong-way-round devices |

New camera functions, all double precision, like the existing ones:
- `EyePosition(aEye)` = `Position ± RightVector * EyeSeparation/2`
- `BuildEyeViewForOrigin(aEye, aOrigin)`: parallel view axes (not toe-in,
  because toe-in causes vertical parallax and eye strain), eye offset applied in
  double before the WorldOrigin subtraction.
- `BuildEyeProjectionForAspect(aEye, aAspect)`: **off-axis** (asymmetric)
  frustum. Shift each side by `±(EyeSeparation/2) * Near / Convergence`. Keep
  the same Y FOV and zero-to-one depth convention as `BuildProjectionForAspect`.
- `GetEyeViewProjectionForAspect(aEye, aAspect, aOrigin)`.
- `GetStereoFrustumPlanesForAspect(aAspect, aOrigin)`: one cull volume that
  holds both eyes. Take the left plane from the left eye, the right plane from
  the right eye, and top/bottom/near/far from either eye. This is conservative,
  so nothing gets culled that either eye can see.

Orthographic + stereo: either disallow it or skip the eye offset (orthographic
views have no parallax). Decide during A2. Disallowing is simpler.

Unit tests (no GPU) in `Tests\`: the two eyes are symmetric about the mono
matrix; a point at `Convergence` projects to the same NDC x in both eyes; a
point at infinity projects with x offset = the projection shift; it works with
a survey-sized WorldOrigin.

### A3. Hook point that PRO VR replaces

```pascal
TvgEyeView = record
  View, Proj : TpvMatrix4x4D;   // local to WorldOrigin
  Eye        : TpvVector3D;     // world, for LOD / lighting
end;

IvgStereoViewSource = interface
  function  StereoActive: Boolean;
  procedure GetEyeViews(aAspect: Double; const aOrigin: TpvVector3D;
                        out aLeft, aRight: TvgEyeView);
end;
```

The default implementation is the camera + `TvgStereoSettings`. PRO's OpenXR
source composes body pose (the first-person camera, Part B) × head pose
(`xrLocateViews`) and uses the runtime's per-eye FOV.
`PrepareFrameGlobalData` only talks to the interface.

### A4. Per-frame data — `PrepareFrameGlobalData`

- The VP UBO **always** holds 2 matrices (`AddMatrix` twice in
  `ValidateViewProjectionDescriptor`). In mono, both are the same matrix. Mono
  shaders declare a single `mat4` and read the first 64 bytes, which is valid
  against a bigger buffer, so **existing shaders need no change**.
- Stereo writes the left matrix to index 0 and the right to index 1. It uses the
  stereo cull volume. The LOD eye is the midpoint between the eyes (so both
  eyes pick the same LOD band, with no popping between eyes).
- Per-eye aspect = (window width / 2) / height for full side-by-side.
  `GetViewportAspect` returns this while stereo is on, so ZoomAll, rays and the
  HUD camera all agree.

### A5. Render targets and passes — `Vulkan_Components.pas`

- Stereo forces `RT_FRAME`. The frame colour image, depth image and MSAA
  resolve image get `arrayLayers = 2`, with `VK_IMAGE_VIEW_TYPE_2D_ARRAY`
  views. The frame size is per eye: (W/2) × H × FrameResolution.
- Classic render pass: chain `VkRenderPassMultiviewCreateInfo`
  (viewMask 0b11, correlationMask 0b11) into each subpass.
- Dynamic rendering: `VkRenderingInfo.viewMask = 0b11`, `layerCount` = 0, as
  multiview requires.
- Enable the `multiview` device feature when the linker's stereo flag is set.
  Changing the stereo flag rebuilds the frames, like a resize does.
- This is the one sizeable core change. Follow the dynamic-rendering work and
  run validation on Win64 (`RunGPUTests.bat`) for both render paths.

### A6. Shaders — `VulkanShaders`

- Stereo variants of every vertex shader that reads the global VP:
  `#extension GL_EXT_multiview : require`, `mat4 VP[2]` / `dmat4 VP[2]`,
  `VP[gl_ViewIndex]`. Generate them from one source with a `VG_STEREO`
  define, so the mono and stereo variants cannot drift apart.
- The shader lookup (see `shader-folder` rules) picks the stereo variant when
  the renderer is stereo, just as it already picks the double-VP variant.
- Sky box: same approach. The sky is at infinity, so only the projection
  differs between eyes. That works with the existing translation-free sky VP.
- World axes and the HUD-camera overlay: decide per item. World axes are scene
  objects and should be stereo. The HUD is 2D (A7).
- PRO ShaderBuilder: emit the same define. Coordinate with PRO, no core
  dependency.

### A7. Composite to the window — `TvgFrame.RecordPresentAndHUD`

`StereoLayout` on the linker:
- `slSideBySideFull`: each eye fills its half at native aspect. Use this for
  phone-in-headset viewers and most video glasses running in 3D mode.
- `slSideBySideHalf`: each eye is rendered at full-window aspect, then squeezed
  into its half. Use this for 3D TVs and projectors.
- `slTopBottom`: optional, cheap to add.
- `slAnaglyph`: red/cyan in one image. Optional, but useful for testing
  without glasses. Needs a small full-screen composite shader instead of a blit.

Phase 1 composites with two `vkCmdBlitImage` regions (layer 0 → left rect,
layer 1 → right rect). `SwapEyes` swaps the destination rects.

The HUD is drawn after the composite. In stereo it is drawn **once per half**
at zero parallax, with the same scissor-per-half used for both. Otherwise the
HUD straddles the split.

### A8. Input in a split window

`TvgToolManager` maps the mouse to the half it is in. X is taken relative to
that half, and the ray comes from that eye's matrices. Picking/pixel read-back
reads the matching layer. Orbit/pan/dolly deltas need no change.

### A9. Lens distortion (later, optional)

Phone-in-headset viewers need barrel distortion and chromatic-aberration
correction per eye. That is a full-screen pass with k1/k2 coefficients in
place of the blit (A7), driven by a lens profile. It is not needed for video
glasses or 3D TVs. Keep it out of phase 1, but give the composite a slot so it
fits later.

### Stereo phases

| Phase | Content | Risk |
|---|---|---|
| S0 | `TvgStereoSettings`, eye maths, unit tests | low |
| S1 | VP UBO ×2, `IvgStereoViewSource`, stereo cull volume, per-eye aspect (mono behaviour unchanged) | low |
| S2 | Multiview layered frame images + render pass/dynamic rendering viewMask + feature enable | **medium/high** |
| S3 | `VG_STEREO` shader variants + lookup, sky box | medium |
| S4 | Composite layouts, HUD per half | low |
| S5 | Per-half picking / pixel read-back | low |
| S6 | Anaglyph, lens distortion (optional) | low |

S0–S1 can ship on their own: they change no output. S2–S4 must land together
before anything visible works.

---

## Part B — First-person navigation with surface following

### B1. Navigation modes

`TvgNavigationMode = (nmOrbit, nmFly, nmWalk)` on `TvgToolManager`, default
`nmOrbit`, which is today's behaviour. The motion logic lives in a separate
**`TvgFirstPersonController`** class. The tool manager owns one, and PRO VR
drives the same controller from a gamepad or headset.

### B2. Camera additions — `TvgCamera`

- `Look(aYaw, aPitch)`: rotates the **target about the position**, the reverse
  of `Orbit`. Uses the world up axis, with pitch clamped to ±89°.
- `Translate(aDelta)`: moves position and target together.
- Both are double precision and work with survey coordinates.

### B3. Controls

| Input | Fly | Walk |
|---|---|---|
| Mouse drag (`OrbitButton`) or captured mouse | look | look |
| W/S, ↑/↓ | forward/back along view direction | forward/back **horizontally** |
| A/D, ←/→ | strafe | strafe |
| Q/E, PgUp/PgDn | down/up | — (or crouch/jump later) |
| Shift / Ctrl | run ×4 / slow ×0.25 | same |
| Wheel | speed up/down | speed up/down |

Needs:
- `DoKeyUp` on `TvgBaseToolManager`, with `TvgLinker.KeyUp` and the window
  classes (VCL/FMX/SDL2) forwarding it, since there is only `KeyDown` today. The
  controller keeps a held-keys set.
- A **tick**. While any movement key is held, a timer at about 60 Hz advances
  by `Speed × dt` and calls `TriggerDraw`. Rendering is on demand (a drag
  needs an explicit `TriggerDraw`), so movement does not come for free. The tick
  stops when no keys are held, so an idle view costs nothing.
- Focus loss clears held keys, so the camera never keeps walking on its own.

### B4. Surface following

```pascal
IvgGroundProvider = interface
  // Highest surface point under aXY no higher than aMaxZ (world coords, double).
  function GroundAt(const aXY: TpvVector3D; aMaxZ: Double;
                    out aZ: Double; out aNormal: TpvVector3D): Boolean;
end;
```

Walk tick:
1. Move horizontally by the input.
2. `GroundAt(newXY, currentFeetZ + StepHeight)`. "Highest hit below
   feet + step" handles bridges, overhangs and multi-level meshes.
3. If there is no hit (off the surface's edge), set `EdgeBehaviour`: stop
   (default) or drop into fly mode.
4. If the slope between the old and new foot positions is above `MaxSlope`
   degrees, or the climb is above `StepHeight`, refuse the move. Optionally
   slide along the contour.
5. Eye Z = ground + `EyeHeight` (default 1.7). The height is smoothed over a
   few frames so a coarse TIN does not jolt the view. The smoothing is always
   applied upwards, so the view never dips below the surface.

Providers:
- **Core `TvgMeshGround`**: built from a list of `TvgObject`s, which may be any
  triangle mesh, including a Delaunay surface displayed as a mesh. Triangles
  use local (WorldOrigin-relative) coordinates, bucketed in a 2D uniform grid
  over XY. A query tests only its cell's triangles (vertical ray, barycentric
  Z). The grid is rebuilt when a store's `ChangeStamp` moves, the same rule
  `TvgObjectProjection` uses.
- **PRO `TvgDelaunayGround`**: `TvgDelaunay2D.FindTriangle(x, y)` plus the
  triangle plane is exact and needs no extra index. An option uses
  `TvgNaturalNeighbourCompute.InterpolateZ` for a smoother surface.

Up axis: the queries run along the scene's up axis. The checkout builds Z-up;
the sky box already has `UpAxis` for mismatched models. B needs the same
decision: use one scene-level up axis rather than a third copy.

Not in scope for phase 1: collision with walls or objects (capsule sweep).
The provider interface allows a later `IvgCollisionProvider`.

### B5. Properties (controller)

`EyeHeight`, `WalkSpeed` (m/s), `RunMultiplier`, `StepHeight` (0.4),
`MaxSlope` (45°), `EdgeBehaviour`, `MouseSensitivity`, `InvertY`, `Ground`
(`IvgGroundProvider`). Events: `OnMoved` for coordinate readouts and
`OnBlocked`.

### First-person phases

| Phase | Content |
|---|---|
| F0 | `TvgCamera.Look` / `Translate` + tests |
| F1 | `DoKeyUp` plumbing (linker + VCL/FMX/SDL2 windows), held-keys, tick + `TriggerDraw` |
| F2 | `TvgFirstPersonController`, `nmFly` |
| F3 | `IvgGroundProvider`, `TvgMeshGround`, `nmWalk` (eye height, step, slope, edge) |
| F4 | Sample app: mode switch, speed and eye-height controls, readout |
| F5 (PRO) | `TvgDelaunayGround` |

---

## How A and B fit together, and VR later

- Stereo eye positions come from the camera, so walking in stereo needs no extra
  work. The first-person camera becomes the "body" pose.
- PRO OpenXR: `IvgStereoViewSource` = body (controller) × head (HMD pose). The
  render path is the S2 multiview path, writing straight into the XR swapchain
  layers and skipping the A7 composite. Snap-turn/smooth locomotion reuse
  `TvgFirstPersonController` with a thumbstick in place of WASD.

## Order of work

F0–F2 and S0–S1 are independent and low risk. Do them first, in either order.
Then F3, then S2–S4 as one block, then the rest.

## Open questions

1. **Which "VR glasses"?** Video glasses (full side-by-side over DP/USB-C, no
   distortion) or a phone-in-headset viewer (needs lens distortion, A9)? This
   decides whether A9 is phase 1.
2. Stereo + orthographic: disallow or ignore (A2)?
3. One scene-level up axis for walk + sky box (B4)?
4. Is `EyeSeparation` in scene units acceptable, or add `UnitsPerMetre` on the
   scene?
