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
