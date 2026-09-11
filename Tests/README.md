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

## What is covered

| Program | Unit under test | Covers |
|---|---|---|
| `FrustumTest.dpr` | `Vulkan_Components_Camera` | Frustum plane extraction: normalisation, signed distance to the near and far planes, and inside/outside for points straddling each of the six planes. Runs perspective at two aspect ratios, the camera's own aspect, and orthographic. |
| `AABBTest.dpr` | `Vulkan_Components_Camera` | `TvgAABB` growth, union, centre/extent/size/radius, and `Transform` under identity, translation, scale and rotation. Then `vgFrustumTestAABB` against boxes behind the camera, past the far plane, off each side, straddling the near plane, enclosing the frustum, and centred outside the frustum while still overlapping it. |
| `BoundsTest.dpr` | `Vulkan_Components_DataStore` | The per-object bounds the store maintains: accumulation from vertex writes, the union over instance matrices, the three cull modes, that two objects sharing the interleaved vertex array keep separate boxes, and the whole thing tested against a real camera frustum. Drives the store with no Vulkan device, since bounds live in its CPU arrays. |
| `CullTest.dpr` | `Vulkan_Components`, `Vulkan_Components_Scene_Renderer`, `Vulkan_Components_DataStore` | Culling end to end without a device: publishing a cull volume onto a renderer, the scene publishing one for its renderer's own aspect, the master switch, and every branch of the per-object decision `VulkanDraw` makes. Also covers one scene feeding two differently shaped viewports. |

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
- `CullTest`: *moved object still drawn (bounds only grow)* - pins a real
  limitation rather than hiding it. See below.

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
plane carries roughly 0.5% error in float32, from cancellation in `w - z`
during extraction. `FrustumTest` asserts this loosely for that range and
tightly for a sane one. The error is conservative - the far plane lands
slightly too far away, so culling keeps a little more than it needs to and
never drops anything visible.
