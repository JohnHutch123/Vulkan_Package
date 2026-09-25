# Zoom All / Look Down - Plan

Branch: `ZoomAll`

**Status: implemented.** All three layers are in, `Tests/ZoomAllTest.dpr`
passes in both axis conventions, and the full `Tests/RunTests.bat` suite is
green. This document is kept as the design record; section 6 lists the
decisions that were taken by default and are still worth a second opinion.

Goal: from a scene, produce a camera position (and projection extent) that
frames **all** the data, either along the current view direction ("Zoom All")
or straight down the world up axis ("Look Down" / plan view). Works for both
`ptPerspective` and `ptOrthographic`.

```
  Scene.GetDataBounds  ->  world AABB (double)
                            |
                            v
  Camera.ZoomAll / ZoomAllLookDown(aMin, aMax, aAspect, aMargin)
                            |
                            v
  Position + Target + Up + near/far  (+ Orth extent when orthographic)
```

## 1. What the survey found

Almost everything needed already exists; nothing has to be reworked.

**Already there - reuse as-is**

- `TvgAABB` (`Vulkan_Components_Camera.pas:117`) with `Reset`, `GrowPoint`,
  `GrowAABB`, `Centre`, `Extents`, `Size`, `Radius`, and a `Valid` flag that is
  `False` until a point is added.
- Per-object bounds already maintained by the data store:
  `TvgVulkanDataStore.GetObjectWorldBounds(ObjectIndex)`
  (`Vulkan_Components_DataStore.pas:1781`) rebuilds from vertex data and
  instance matrices on demand, honours `cmAuto` / `cmNever` / `cmManual`, and
  returns an **invalid** box when the object has none.
- `TvgScene.SceneData : TObjectList<TvgObjectStore>` and
  `TvgObjectStore.GetObjectCount` - the enumeration needed to union them.
- `TvgScene.LocalToWorld` / `WorldToLocal` (`:1557`) for the `WorldOrigin` shift,
  in double.
- `Vulkan_WorldAxes`: `vgWorldUp`, `vgWorldForward`, `vgWorldRight` - so
  "look down" means the same thing under `acYUp` and `acZUp`.
- `TvgCamera.LookAt`, `SetPerspective`, `SetOrthographic`, and
  `InvalidateMatrices`, which already bumps `Revision` so the HUD/renderer
  treat the move as a scene change.
- `TvgBaseRenderEngine.GetViewportAspect` (`Vulkan_Components.pas:12663`) and
  `TvgBaseToolManager.GetViewportSize` - the aspect to fit to.

**Gaps this branch fills**

| Gap | Where |
|---|---|
| No scene-wide bounds. Bounds exist per object only. | new `TvgScene.GetDataBounds` |
| No fit-to-bounds camera math at all. | new `TvgCamera.ZoomAll` family |
| No user-facing "zoom extents" entry point. | new `TvgToolManager.ZoomAll` / `ZoomAllLookDown` |

## 2. Three precision traps

These decide the shape of the API, so they come before the design.

**(a) The AABB is float32, the camera is double.**
`TvgAABB` is deliberately single - it is built from float32 vertex data. The
camera is deliberately double - it must hold survey coordinates. So the scene
must **not** hand back a `TvgAABB` in world space: `LocalBounds + WorldOrigin`
in float32 is exactly the 62.5 mm rounding `WorldOrigin` exists to avoid.

> `GetDataBounds` therefore returns `out aMin, aMax : TpvVector3D` (double),
> built by taking the union in **local** space (float32, where it belongs) and
> converting the two corners through `LocalToWorld` in double at the very end.

**(b) `BuildProjectionForAspect` ignores `OrthLeft`/`OrthRight`.**
Look at `Vulkan_Components_Camera.pas:1094`: for `ptOrthographic` the renderer
keeps the stored **height** and derives the width as `halfH * aAspect`. The
left/right the application set are discarded every frame.

> So fitting an orthographic camera means solving for the height alone:
> `halfH := Max(halfH, halfW / aAspect)`. Setting left/right to the data width
> and stopping there frames correctly at exactly one aspect ratio and clips the
> data at every other one. This is the single easiest thing to get wrong here.

**(c) Looking down cannot use `vgWorldUp` as the up vector.**
`RecalculateViewMatrix` does `xaxis := FUpVector.Cross(zaxis)`. Straight down,
`zaxis` **is** `vgWorldUp`, the cross product is zero and the view matrix fills
with NaN - the same degeneracy `Orbit` already guards with `MAX_ELEVATION`.

> The look-down up vector is `vgWorldForward`, which puts world "forward" at the
> top of the screen in either axis convention. Under `acYUp` that is `-Z` up the
> screen with `+X` to the right; under `acZUp` it is `+Y` up the screen with
> `+X` to the right - i.e. a normal map orientation, north up, east right.

## 3. Design

### 3.1 `TvgScene.GetDataBounds` - `Vulkan_Components_Scene_Renderer.pas`

```pascal
{ World-space bounds of every object in the scene, in double.

  Unions TvgVulkanDataStore.GetObjectWorldBounds over every object of every
  store, which rebuilds any stale box on the way, then converts the two
  corners through LocalToWorld.  The union is taken in LOCAL space, where the
  float32 boxes already live; adding WorldOrigin to a float32 corner would
  round a survey coordinate to the nearest 62.5 mm.

  Objects with no usable bounds contribute nothing: an empty box (never
  filled), and cmNever, whose bounds the application has said not to trust.
  A compute-owned object can still be included by giving it bounds through
  SetObjectBounds, which is what cmManual is for.

  Returns False, leaving aMin/aMax untouched, when the scene has no object
  with usable bounds - an empty scene, or one built entirely from cmNever
  geometry.  Callers must not zoom to a box they did not get. }
Function GetDataBounds(out aMin, aMax: TpvVector3D;
                       aVisibleOnly: Boolean = True): Boolean;
```

- Walks `fSceneData`, skipping a store when `aVisibleOnly` and the store is not
  `Visible`, so hiding a layer also takes it out of the zoom.
- Accumulates into a local `TvgAABB` with `GrowAABB`.
- `Result := Box.Valid`; on success
  `aMin := LocalToWorld(Box.Min)` / `aMax := LocalToWorld(Box.Max)`.
- Overload `GetDataBounds(out aBox: TvgAABB): Boolean` returning the **local**
  box unconverted, for culling-side callers already working in local space.

### 3.2 `TvgCamera` fit methods - `Vulkan_Components_Camera.pas`

One private worker, three public entry points.

```pascal
private
  { Places the eye so the box aMin..aMax fills a viewport of aAspect, looking
    along aDirection with aUp as the screen's up.  Shared by every ZoomAll
    entry point; they differ only in where the direction comes from.
    CALLER MUST NOT HOLD FCriticalSection. }
  function FitToBounds(const aMin, aMax, aDirection, aUp: TpvVector3D;
                       aAspect, aMargin: Double): Boolean;

public
  { Frames all of aMin..aMax without turning the camera: keeps the current
    view direction and up vector and only moves the eye (and, for an
    orthographic camera, widens the extent).

    aAspect is the viewport's width/height - pass the same value the renderer
    draws with (TvgBaseRenderEngine.GetViewportAspect), not the camera's own
    stored AspectRatio, or the fit is right for a window shape nobody has.

    aMargin is the fraction of empty space left around the data; 1.0 touches
    the data to the edge of the screen, the default 1.05 leaves 5%.

    Returns False and changes nothing if the box is empty (aMin > aMax on any
    axis) - see TvgScene.GetDataBounds, which reports the same condition. }
  function ZoomAll(const aMin, aMax: TpvVector3D;
                   aAspect: Double; aMargin: Double = 1.05): Boolean;

  { The same fit looking straight down the world up axis - a plan view.  The
    screen's up becomes vgWorldForward, since vgWorldUp is the view direction
    here and an up vector parallel to it makes the view matrix degenerate. }
  function ZoomAllLookDown(const aMin, aMax: TpvVector3D;
                           aAspect: Double; aMargin: Double = 1.05): Boolean;

  { Fit along a caller-supplied direction, for a named view (front, side, an
    isometric).  aDirection is the way the camera LOOKS, from eye to target;
    it need not be normalised.  aUp is trimmed to the part perpendicular to
    aDirection, and a caller passing one parallel to it gets False rather
    than a NaN view matrix. }
  function ZoomAllFromDirection(const aMin, aMax, aDirection, aUp: TpvVector3D;
                                aAspect: Double; aMargin: Double = 1.05): Boolean;
```

**`FitToBounds` math** (all double, all in world space):

1. `C := (aMin + aMax) * 0.5`; reject if any `aMax < aMin`.
2. Orthonormal camera basis from the requested direction:
   `F := aDirection.Normalize`; `R := F.Cross(aUp)`; reject if `R.Length` is
   below a tolerance (up parallel to the direction); `R := R.Normalize`;
   `U := R.Cross(F)`. Re-deriving `U` is what lets a caller pass a rough up.
3. Project the **8 corners** onto `R`, `U`, `F` relative to `C` and take the
   max absolute value on each - `halfW`, `halfH`, `halfD`. For an
   axis-aligned box this equals
   `halfW = dot(abs(R), extents)` etc., so it is 3 dot products, not 8
   transforms; the corner loop is written out anyway because it also states
   the intent and costs nothing at this call rate.
4. Floor all three at a small epsilon so a flat or single-point dataset (a
   plan-view height field has `halfD` of 0, a single point has all three)
   still produces a finite, usable camera rather than a divide by zero.
5. Apply `aMargin` to `halfW` and `halfH` (never `halfD` - depth is not being
   framed, only cleared).
6. Then, by projection type:

   **Perspective** - `t := Tan(DegToRad(FieldOfView) / 2)` (`FieldOfView` is
   the **vertical** fov: `RecalculateProjectionMatrix` puts `f` unscaled in
   the Y column and divides X by the aspect).

   ```
   Dist := Max(halfH / t, halfW / (t * aAspect)) + halfD
   Eye  := C - F * Dist
   Near := Max(CAMERA_MIN_NEAR, (Dist - halfD) * 0.01)
   Far  := (Dist + halfD) * 1.5
   ```

   The `+ halfD` pushes the eye back past the near face of the box, so the fit
   is computed at the centre and nothing in the front half of the data is
   clipped. Near is tied to the scene size rather than left at
   `CAMERA_DEFAULT_NEAR` (0.01): a survey-scale dataset with near 0.01 and far
   10⁶ is a 10⁸ depth ratio and z-fighting across the whole scene. The 0.01
   factor keeps the ratio near 10⁴, comfortably inside float32 depth.

   **Orthographic** - the extent is the fit; distance only has to clear the
   near plane.

   ```
   halfH := Max(halfH, halfW / aAspect)   // see trap (b)
   halfW := halfH * aAspect               // stored for completeness
   Pad   := Max(halfD, halfH) * 0.1 + CAMERA_MIN_NEAR
   Eye   := C - F * (halfD + Pad)
   SetOrthographic(-halfW, +halfW, +halfH, -halfH, Pad * 0.5, halfD * 2 + Pad * 2)
   ```

7. `LookAt(Eye, C, U)` - so `Target` lands on the centre of the data and
   subsequent `Orbit` / `Zoom` / `Pan` all pivot about it, which is the whole
   point of a zoom-extents. Then `SetPerspective`/`SetOrthographic` for the
   planes. Both already bump `Revision`.
8. `FAspectRatio` is **not** written. It stays the camera's design aspect, as
   `PrepareFrameGlobalData` documents; `aAspect` is a fit input only.

### 3.3 `TvgToolManager` entry points - `Vulkan_Components_Scene_Renderer.pas`

The interactive front door, alongside `DoCameraOrbit` / `DoCameraZoom`. It is
the only class that already holds the scene, the renderer and the viewport.

```pascal
public
  { Moves the active camera to frame every object in the scene, fitted to this
    tool manager's current viewport.  Returns False, and moves nothing, when
    there is no scene, no active camera, no viewport yet, or no data with
    usable bounds. }
  function ZoomAll(aMargin: Double = 1.05): Boolean;

  { The same, looking straight down - a plan view of all the data. }
  function ZoomAllLookDown(aMargin: Double = 1.05): Boolean;

  { Switches the active camera to orthographic and frames all the data looking
    down: the survey/map view.  Perspective foreshortening is what makes a
    plan view hard to read, so this is the combination most callers of a
    "look down at everything" button actually want. }
  function ZoomAllPlanView(aMargin: Double = 1.05): Boolean;
```

Each is: `GetActiveCamera`, `fScene.GetDataBounds`, `GetViewportSize` ->
`W / H` (falling back to `fRenderer.GetViewportAspect`, then 1.0), then the
matching `TvgCamera` call. No mouse plumbing, no new gesture - they are called
from a button, a menu, a hotkey, or right after loading data.

Optionally bind one to a key later; not in this branch, since the base tool
manager has no key handling yet.

## 4. Files touched

| File | Change |
|---|---|
| `RunTime_Src/Vulkan_Components_Camera.pas` | `CAMERA_MIN_NEAR` const; `FitToBounds` (private); `ZoomAll`, `ZoomAllLookDown`, `ZoomAllFromDirection` (public) |
| `RunTime_Src/Vulkan_Components_Scene_Renderer.pas` | `TvgScene.GetDataBounds` (2 overloads); `TvgToolManager.ZoomAll`, `ZoomAllLookDown`, `ZoomAllPlanView` |
| `Tests/ZoomAllTest.dpr` | new, see below |
| `Tests/RunTests.bat` | add `ZoomAllTest` to the `for %%T in (...)` list |
| `Tests/README.md` | row in the coverage table, and the "why these exist" notes |
| `RunTime_Src/MIGRATION_GUIDE.md` | short "Zoom to all data" section - additive API, nothing to migrate |

No existing signature changes, no behaviour change to any existing call, so
nothing downstream has to move. Every addition is a new method.

## 5. Test plan - `Tests/ZoomAllTest.dpr`

CPU-only like the rest of the suite (no device, no window). Same shape: a
`Check` helper, one `procedure` per area, `ExitCode := 1` on any failure.

The checks that earn their keep are the ones that fail for a fit that *looks*
right:

1. **Every corner is on screen** - the real assertion, and it subsumes most of
   the rest. For each case, build the VP the renderer would actually use
   (`GetViewProjectionMatrixForAspect(aAspect, WorldOrigin)`), push all 8
   corners of the data box through it, and assert every one lands inside NDC:
   `|x| <= 1`, `|y| <= 1`, `0 <= z <= 1`. Run it perspective and orthographic,
   at aspects 16:9, 1:1 and 9:16.
2. **Tight, not just safe** - at least one corner within `aMargin` of an edge.
   A camera parked a kilometre away passes check 1 and fails this. Together
   they are the fit.
3. **A wide, flat dataset at aspect 1:1, orthographic** - trap (b). A fit that
   stores left/right from the data width passes at 16:9 and clips here.
4. **Look down under both axis conventions** - run the whole file twice, as
   `AxisConventionTest` does. Assert the view matrix is finite (trap (c)), that
   the eye is above the data (`vgUpComponent(Position) > vgUpComponent(aMax)`),
   and that `WorldToScreenPoint` puts a point at `+vgWorldForward` from the
   centre in the **top** half of the screen and one at `+vgWorldRight` in the
   right half - i.e. the plan view is not mirrored or rotated.
5. **Survey coordinates** - a box around (612345.678, 5432109.876) with a
   scene `WorldOrigin` in the middle of it. Checks 1 and 2 must hold to the
   same tolerance as near the origin; this is what catches the float32 corner
   conversion of trap (a).
6. **Target is the centre of the data** - so a following `Orbit` pivots on the
   data, not on wherever the camera was pointing before.
7. **Degenerate input**: empty scene returns `False` and leaves the camera
   exactly where it was (compare `Position`, `Target`, `Revision`); a single
   point; a perfectly flat height field (`halfD = 0`); a box with one axis of
   zero length. All must produce a finite view matrix and a `NearPlane > 0`
   with `FarPlane > NearPlane`.
8. **`GetDataBounds`**: union across two stores and across multiple objects in
   one store; a `cmNever` object excluded; a `cmManual` object included at the
   bounds the application gave; an invisible store excluded when
   `aVisibleOnly`, included when not; and the returned corners exact to
   millimetres at survey coordinates.
9. **Depth ratio** - `FarPlane / NearPlane < 1e5` for a survey-sized dataset,
   pinning the near-plane rule in 3.2 step 6 rather than leaving it to a
   comment.

## 6. Open questions

1. **Default margin** - 1.05 (5% of empty space) is proposed. Some packages use
   1.0 flush, CAD tools typically 1.02-1.10.
2. **Should `ZoomAll` keep the projection type?** As specified, yes: `ZoomAll`
   and `ZoomAllLookDown` fit whichever projection is set, and only
   `ZoomAllPlanView` switches to orthographic. The alternative is a projection
   argument on all three.
3. **`cmNever` objects** - excluded, since their bounds are exactly what the
   application said not to trust. The consequence: a scene that is *entirely*
   compute-generated geometry has no bounds to zoom to and `GetDataBounds`
   returns `False`. `SetObjectBounds` is the answer, but it is worth confirming
   that is the behaviour wanted rather than falling back to some default box.
4. **Should the HUD be excluded?** The HUD has its own camera
   (`TvgRenderEngine.GetHUDCamera`), so it is already out of the scene's data
   stores - no action expected, but worth confirming against a live HUD scene.

## 7. What was actually built

All nine test areas in section 5 are implemented and passing, in both axis
conventions, alongside the existing suite. Three things are worth recording
because they were decided during implementation rather than in the plan:

**The perspective fit is exact square on, conservative obliquely.** `Dist` is
derived from the maximum extent perpendicular to the view direction, measured
at the box centre. When the box is seen square on, the corner furthest out
perpendicular is also on the near face, so it projects to exactly the margin -
a tight fit. Seen from a corner, that extreme corner may be at the *back* of
the box, where perspective shrinks it, so the result has some margin to spare.
Everything is still on screen, which is the promise; a truly tight oblique fit
needs a per-corner solve and was not worth it. `ZoomAllTest` asserts tightness
only for square-on views and states why.

**`AspectRatio` is never written.** The perspective branch sets `NearPlane` and
`FarPlane` as properties rather than calling `SetPerspective`, because
`SetPerspective` also overwrites `FAspectRatio` - which
`TvgScene.PrepareFrameGlobalData` documents must stay the camera's own design
value, not a viewport's. `SetOrthographic` does not touch it, so the
orthographic branch calls it directly.

**Visibility is filtered per object, not per store.**
`TvgObjectStore.GetVisible` is True if *any* object in the store is visible, so
filtering at store level would silently include hidden geometry and zoom out
too far. `GetDataBounds` tests `TvgObject.VisibleON` on each object.

One thing the test suite found: under `acZUp`, two opposite corners of a box
expressed in Y-up are no longer its min and max, because `vgFromYUp` negates a
component. `GetDataBounds` returns properly ordered corners; callers
constructing expected values from Y-up input need `vgRangeFromYUp`.
