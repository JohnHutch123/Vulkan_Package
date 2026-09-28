# Tests

Console test programs that compile the real runtime units and assert against
them. Each one is a plain `.dpr` with no test framework to install: it prints a
line per check and exits non-zero if any check failed.

## Running

```
Tests\RunTests.bat
```

The script finds `dcc32.exe` and PasVulkan on its own where it can. Override
either if it cannot:

```
set BDS=C:\Program Files (x86)\Embarcadero\Studio\23.0
set PASVULKAN=D:\Vulkan
Tests\RunTests.bat
```

Build output and logs go to `Tests\Win32\`, which is ignored by git.

To run a single test, build it the same way and run the exe, or just run
`Tests\Win32\AABBTest.exe` after a full run.


The tests for the PRO units (edit tools, particles, natural neighbour,
springs, Delaunay display, glTF, the shader builder and the GPU tests) are in
the Vulkan_Package_PRO repository.

## What is covered

| Program | Unit under test | Covers |
|---|---|---|
| `FrustumTest.dpr` | `Vulkan_Components_Camera` | Frustum plane extraction: normalisation, signed distance to the near and far planes, and inside/outside for points straddling each of the six planes. Runs perspective at two aspect ratios, the camera's own aspect, and orthographic. |
| `AABBTest.dpr` | `Vulkan_Components_Camera` | `TvgAABB` growth, union, centre/extent/size/radius, and `Transform` under identity, translation, scale and rotation. Then `vgFrustumTestAABB` against boxes behind the camera, past the far plane, off each side, straddling the near plane, enclosing the frustum, and centred outside the frustum while still overlapping it. |
| `BoundsTest.dpr` | `Vulkan_Components_DataStore` | The per-object bounds the store maintains: accumulation from vertex writes, the union over instance matrices, the three cull modes, that two objects sharing the interleaved vertex array keep separate boxes, and the whole thing tested against a real camera frustum. Drives the store with no Vulkan device, since bounds live in its CPU arrays. |
| `DataStoreEditTest.dpr` | `Vulkan_Components_DataStore` | Editing a store after it is built, with no Vulkan device, checking every time that an edit to one object leaves every other object's vertices, indices and object IDs exactly as they were. Growing an object that is not the last one in the shared arrays moves it to the end instead of overwriting the next object (vertices, indices and instances), and a tail object still grows in place. `ResetObject` works on any object and can be refilled. `DeleteDataObject` leaves a tombstone so every other object keeps its index, the deleted object has no range and no bounds, and any further write, add, reset or second delete raises; deleting the tail object gives its space straight back. Writes past the end of an object raise instead of landing in its neighbour. `RemoveObjectVertex` drops the primitives that used the vertex and renumbers the rest for indexed line lists, triangle lists and strips, removes the whole primitive for non-indexed lists, and rescans the bounds. `SetObjectVertexCount`/`SetObjectIndexCount` shrink and grow in place or by relocating. `Compact` removes every kind of waste while keeping object indices, contents and object IDs, packs the ranges in object order, and leaves the store usable; automatic compaction triggers past its ratio and minimum and not below. `ClearAll` followed by new data no longer writes past the end of the emptied arrays. `SetObjectHidden`: a hidden object is skipped by the draw (`ShouldSkipObject`, the loop's own decision) but keeps its data and bounds, and stays hidden through relocation, `RemoveObjectVertex`, `SetObjectVertexCount`, `SetObjectData`, `ResetObject` and `Compact`; hiding a deleted object raises. |
| `SceneEditTest.dpr` | `Vulkan_Components_Scene_Renderer`, `Vulkan_Components_DataStore` | Editing a loaded `TvgScene` with no Vulkan device. The scene's live-object list: objects added while loading are on it, so are those of a store filled before it joined, and nil or any other object is not. `TvgObjectStore.RemoveObject` takes the object off that list (so a pick of the last frame drawn with it finds nothing), deletes its data, leaves every other object's index and vertices as they were, shrinks `GetDataBounds`, fires `OnDataChanged` once for the store, and ignores nil and another store's object. `AddDataStoreLive` adds a store to a READY scene without clearing it, registers its objects and later ones, is idempotent, is plain `AddDataStore` while loading, and is refused in any other state. `RemoveDataStore` frees the store and its objects, leaves the others, and ignores a store the scene does not hold. `NotifyDataChanged` fires `OnDataChanged` with or without a renderer, and freeing a scene full of objects, including mid-load and with a removed object's tombstone, is clean. Edit layers (`GetEditStore`): one store per kind, made once, with the documented topology, index type, vertex colour, object ID and shader name, taking `EditLineWidth`/`EditColor`/`EditShaderPrefix`; made again after `RemoveDataStore` or a reload; none while storing. `AddLine`/`AddPolyline`/`AddPoint` at survey coordinates through a `WorldOrigin` round-trip to the millimetre, carry the object's address as its object ID, notify, and grow the scene bounds; polylines share vertices in an indexed `LINE_LIST`, repeat them in an unindexed one, and close up in a `LINE_STRIP`; the wrong shape for a store, a one-point polyline and a closed two-point one raise and add nothing. `TvgObject` edits: `MoveVertex` rescans the bounds so they shrink back, `Translate` moves every vertex and the bounds, `Centroid`, `NearestVertex`, `DeleteVertex`, out-of-range and locked/frozen refusals leaving the data as it was, one notification per edit, and `Delete`. `TvgObject.VisibleON` False hides the object in its store as well as from `GetDataBounds`, keeps its data and edits, notifies once per change and once per `BeginUpdate`/`EndUpdate` group, and True shows it again. Building pipelines on a real renderer (`ConnectStoreLive`) needs a device. |
| `CullTest.dpr` | `Vulkan_Components`, `Vulkan_Components_Scene_Renderer`, `Vulkan_Components_DataStore` | Culling end to end without a device: publishing a cull volume onto a renderer, the scene publishing one for its renderer's own aspect, the renderer's own per-frame step (`PrepareGlobalAndSceneDescriptors`) leaving that volume in place for the workers, the master switch, and every branch of the per-object decision `VulkanDraw` makes. Also covers one scene feeding two differently shaped viewports. |
| `AxisConventionTest.dpr` | `Vulkan_WorldAxes`, `Vulkan_Components_Camera` | The world axis convention, run once as Y-up and once as Z-up: the basis is right-handed, the Y-up conversion is a rotation (determinant +1) that round-trips, the drag planes are horizontal/vertical, the default camera is above the ground and its centre ray lands on the target, orbit yaw keeps height and distance, pitch stops short of the poles with a finite view matrix, and the convention cannot change while a camera is alive. Under Y-up it also pins the old defaults, so existing users see no change. |
| `CameraTest.dpr` | `Vulkan_Components_Camera` | The cached view-projection stays current whichever getter runs first. `ScreenToWorldRay` and `WorldToScreenPoint` round-trip a pixel exactly and agree with the matrix the renderer draws with, near the origin, far from it and at survey coordinates, perspective and orthographic, with a viewport aspect different from the camera's. Screen up is world up for both projections. `Zoom` moves by the documented step. `ViewUpVector` is the screen's up: level it is the reference up; pitched 30 degrees it tilts by exactly that, at right angles to the view and the right vector, while `UpVector` stays put; a step along it moves straight up the screen; yaw alone keeps it level. |
| `ZoomAllTest.dpr` | `Vulkan_Components_Camera`, `Vulkan_Components_Scene_Renderer` | Zoom to all data, run once as Y-up and once as Z-up, with no Vulkan device. `TvgCamera.ZoomAll`/`ZoomAllLookDown`/`ZoomAllFromDirection` are measured by pushing all eight corners of the box through the same view-projection the renderer would draw with: every corner lands inside NDC, between the near and far planes, and touches the margin on whichever screen axis binds - so a camera parked uselessly far back fails. Perspective and orthographic, at 16:9, 1:1 and 9:16, for a cube, a flat slab, a tall column and a box a long way off the origin. Look-down produces a finite view matrix (the naive world-up choice gives NaN), puts the data centre at the centre of the screen, and has screen up pointing north with east to the right. The target lands on the data centre, so orbiting afterwards pivots on the data. Degenerate input: an empty box is refused and the camera is untouched, a single point and a zero-thickness plane still yield a finite matrix and a near plane greater than zero, and the near/far range tracks the scene size rather than being fixed. `TvgScene.GetDataBounds` unions several stores, skips invisible objects and `cmNever` ones, reports False for an empty scene, and returns doubles exact to the millimetre at survey coordinates through a `WorldOrigin`. The `TvgToolManager` entry points reach all of it and `ZoomAllPlanView` really does switch to orthographic. |
| `DynamicRenderingTest.dpr` | `Vulkan_Components`, `Vulkan_Components_Scene_Renderer` | The render-path decision behind dynamic rendering, with no Vulkan device: the defaults (`RenderingMode = rmDynamic`, instance API 1.3, device `DynamicRenderingON`); switching `RenderingMode` between Dynamic and Standard before enabling, with `ActiveRenderingMode` and the render pass following it; each reason Dynamic falls back to Standard - no linker, no screen device, the device request off, two subpasses (dynamic rendering has no `NextSubpass`); the device reporting only its request before a Vulkan device exists; and a standalone render pass with no handle and no dynamic path. Whether the device really grants the feature, the latch taken in `SetEnabled`, and the recording itself need a GPU - see *GPU tests* above. |
| `SceneLinkTest.dpr` | `Vulkan_Components`, `Vulkan_Components_Scene_Renderer` | The link between a `TvgRenderEngine` and its `TvgScene`, with no Vulkan device. Three things must agree: `Scene`, `BaseScene`, and the scene listing the renderer exactly once in `RendererList`. They are checked after assigning `Scene`, after assigning `BaseScene`, and after `TvgScene.ConnectRenderEngine` (what the design-time auto-link calls), each time through connect, reconnect to the same scene, move to a second scene, and clear. A second scene cannot claim an engine that is already linked, and freeing either end clears the other. A DFM round trip through `WriteComponent`/`ReadComponent`, with the scene ahead of the engine and behind it, writes `Scene` and restores the whole link. So does a DFM saved before the fix, which holds only `BaseScene`. Also the renderer's global descriptors: fixed bindings (0 view-projection, 1 object-ID target, 2 lights) through every `SelectMode`, the last mode's object-ID item removed on each switch, and the lights buffer - always `MaxGlobalLights` slots, uploaded, live lights first and the rest type None, extra lights dropped. |

## Why these exist

They back the CPU-side frustum culling work. Culling is the kind of change
whose failure mode is *geometry silently disappearing* at certain camera
angles - easy to miss in a demo, hard to attribute later. The checks that earn
their keep are the ones asserting the culler does **not** reject something
visible:

- `AABBTest`: *centre outside, box overlaps* - a box whose centre is outside
  the frustum but which still pokes into view. A centre-only test passes every
  other check in the file and fails this one.
- `AABBTest`: *empty box is kept* - an object with no bounds must be drawn, not
  skipped.
- `FrustumTest`: signed distances, not just signs. Sign-only tests pass even
  with unnormalised planes; anything comparing a distance against a bounding
  volume's extent does not.
- `BoundsTest`: *manual Min/Max survives a vertex write* - an object whose
  bounds the application supplied, because a compute shader owns its
  geometry, must not have them quietly replaced by stale CPU positions.
- `BoundsTest`: *union Min/Max* over instance matrices. `TvgMatrix4x4S` is
  reinterpreted as a `TpvMatrix4x4` when the store reads an instance
  transform back; if that layout assumption were wrong the boxes would not
  move, or would move along the wrong axis, and these checks say which.
- `CullTest`: *no camera leaves the volume invalid* - a frame that cannot
  produce a cull volume must draw everything, not keep culling against the
  previous frame's camera.
- `CullTest`: *cut on the square viewport* / *drawn on the wide viewport* -
  one scene, two viewport shapes, one object that is genuinely visible in one
  and not the other. A single shared cull volume passes every other check and
  fails this pair.
- `CullTest`: *camera: volume valid after the frame* - runs the renderer's
  real per-frame step rather than its parts. It used to invalidate the
  volume after the scene published it, so nothing was ever culled while
  every check on the parts still passed.
- `CullTest`: *moved object still drawn (bounds only grow)* - pins a real
  limitation rather than hiding it. See below.

`CameraTest` (and `PrecisionTest`, in the PRO package) back the double-precision work
(`RunTime_Src/DOUBLE_PRECISION.md`), where the failure mode is geometry that
is drawn but in slightly the wrong place, or picking that misses, and only far
from the origin:

- `CameraTest`: *centred when ...ForAspect ran first* - the cached
  view-projection used to be rebuilt only by the constructor.
- `CameraTest`: *pixel -> ray -> pixel* at survey coordinates - the old ray
  started at the world origin, which looks right near (0,0,0) and nowhere else.
- `CameraTest`: *orthographic: a point above the target is in the top half* -
  orthographic cameras drew upside down.
- `PrecisionTest`: *no origin ... is over 10 mm* - proves the sweep can see
  float32 world coordinates fail, so the sub-millimetre results mean something.
- `PrecisionTest`: *20000 positions within the limit read back exactly* -
  fails if vertices go beyond `VG_LOCAL_COORD_LIMIT` (16,384) from the origin.
- `PrecisionTest`: *ShaderUseDouble switches it to a dmat4* - re-typing the
  descriptor used to raise `EComponentError`.

`ZoomAllTest` backs zoom to all data (`RunTime_Src/ZOOM_ALL_PLAN.md`), where
the failure mode is a view that looks fine on the developer's monitor and
clips the data on someone else's, or a plan view that renders nothing at all:

- *every corner on screen* **and** *fit is tight, not merely safe*, together.
  Either alone is trivially satisfiable - stand a mile back, or don't move -
  and it takes the pair to mean anything. They are measured through
  `GetViewProjectionMatrixForAspect`, the matrix the renderer actually draws
  with, not through the fit's own arithmetic.
- *fitted at 1:1* for the orthographic cases. `BuildProjectionForAspect`
  discards the stored left/right and re-derives width from the stored height,
  so an ortho fit that solves for width frames correctly at exactly one aspect
  ratio and clips at every other. Checking three aspects is what catches it.
- *look down: view matrix is finite*. Looking straight down with the obvious
  up vector - world up - makes `RecalculateViewMatrix` cross two parallel
  vectors, and every subsequent frame is NaN. The check is for a *finite*
  matrix rather than a plausible one, because that is the actual failure.
- *look down: screen up points north* / *east is to the right*. A plan view
  that is upside down or mirrored passes every framing check in the file.
- *target is the centre of the data*. The fit could place the eye correctly
  and leave the target behind, which looks right until the user orbits and the
  view swings away from what they just zoomed to.
- *near plane greater than zero* on a single point and on a zero-thickness
  plane - a contour set or a survey with one station. A fit that scales the
  near plane from the box size gives zero or negative here and the depth
  buffer collapses.
- *near/far follows the scene size* rather than being fixed: the same fit has
  to serve a 1 m object and a 10 km site without z-fighting on one or clipping
  the other.
- *empty box is refused and the camera is untouched*. `GetDataBounds` returns
  False for a scene with nothing in it, and the camera must stay where it was
  rather than jump somewhere meaningless.
- *skips invisible objects* and *skips cmNever objects*. Bounds are taken per
  object, not per store: `TvgObjectStore.GetVisible` is True if *any* object in
  it is visible, so a store-level filter silently zooms out to include hidden
  geometry. `RecomputeWorldBounds` only special-cases `cmManual`, so `cmNever`
  objects still carry a valid box and have to be excluded explicitly.
- *survey bounds: min is exact to 1 mm*. The union is taken in local float32
  and only the two final corners are converted to double through
  `LocalToWorld`. Adding `WorldOrigin` to a float32 corner instead rounds to
  the nearest 62.5 mm at six-digit coordinates, and the camera then frames a
  box that is not quite the data's.
- *ZoomAllPlanView switches to orthographic* - the projection has to be set
  before the fit runs, since the fit reads it to choose its branch.

Both conventions are run because the look-down direction, the plan view's up
vector and the survey-coordinate axis all change with `vgSetAxisConvention`,
and under Z-up two opposite corners of a Y-up box are no longer its min and
max - which is what `vgRangeFromYUp` is for.

## Known behaviour: bounds only grow

`SetObjectVertexPosition` accumulates bounds per write, so rewriting a vertex
to a new position extends the box to cover both the old and new places rather
than moving it. The error is in the safe direction - the culler keeps drawing
something it could have skipped - but an object animated by rewriting its
vertices accumulates a box that widens until it is never culled at all.

`TvgVulkanDataStore.RebuildObjectBounds` rescans the vertices and replaces the
box. Call it once after moving or rebuilding a mesh in place. Objects built
once and left alone never need it. `CullTest` asserts both halves: the moved
object is still drawn, and the rebuild culls it again.

## Adding a test

Copy the shape of an existing one: a `Check`-style helper that increments a
failure counter, one `procedure` per area, and `ExitCode := 1` if anything
failed. Then add its name to the `for %%T in (...)` list in `RunTests.bat`.

## Known numeric caveat

With a near/far ratio around 100000 (for example near 0.01, far 1000) the far
plane's extraction cancels two nearly equal numbers in `w - z`. In float32
that put the far plane about 0.5% too far away. The camera now builds its
matrices and planes in double, where the error is gone, and `FrustumTest`
asserts the far plane to 0.001 for that range too.

The float32 limits that remain are on the GPU side and are measured by
`PrecisionTest` (PRO): vertex offsets within 16,384 of `TvgScene.WorldOrigin` keep
three decimals, and a float32 `mat4` view-projection places them to about
1 mm.
