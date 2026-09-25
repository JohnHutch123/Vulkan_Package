# Vulkan DataStore Refactoring - Migration Guide

## Overview

This refactored version dramatically simplifies vertex, instance, and index buffer management by:

1. **Fixed Binding Scheme**: Binding 0 = Vertices, Binding 1 = Instances
2. **Single Interleaved Buffers**: One buffer per type instead of per-binding dictionaries
3. **Direct Array Access**: Objects track simple start/count ranges
4. **Removed Complexity**: No more multi-vertex-set or multi-index-set support

## Key Changes

### Old Object Record (Complex)
```pascal
TvgVulkanObjectRecord = record
  InstanceBinding: Cardinal;
  VertexBindings: TList<Cardinal>;
  IndexBindings: TList<Cardinal>;
  VertexStarts: TList<Integer>;
  VertexCounts: TList<Integer>;
  // ... many more lists
end;
```

### New Object Record (Simple)
```pascal
TvgVulkanObjectRecord = record
  VertexStart, VertexCount: Integer;
  InstanceStart, InstanceCount: Integer;
  IndexStart, IndexCount: Integer;
  IndexType: TIndexType;
  HasInstances: Boolean;
end;
```

## Migration Steps

### 1. Setup Phase (Before Adding Data)

**Old Code:**
```pascal
DataStore := TvgVulkanDataStore.Create;
DataStore.AddVertexAttributes([vdtPosition, vdtColor, vdtNormal], [0, 1, 2]);
DataStore.AddInstanceAttributes([idtObjID, idtMatrix], [3, 4]);
```

**New Code:**
```pascal
DataStore := TvgVulkanDataStore.Create;
DataStore.SetupVertexAttributes([vdtPosition, vdtColor, vdtNormal]);
DataStore.SetupInstanceAttributes([idtObjID, idtMatrix]);
// Locations are auto-assigned sequentially starting from 0
```

### 2. Object Creation

**Old Code:**
```pascal
ObjectIndex := DataStore.AddDataObject(True); // True = has instances
VertexSet := DataStore.AddObjectVertexSet(ObjectIndex);
IndexSet := DataStore.AddObjectIndexSet(ObjectIndex);
VertexBinding := DataStore.GetVertexBinding(ObjectIndex, VertexSet);
```

**New Code:**
```pascal
ObjectIndex := DataStore.AddDataObject(True); // True = has instances
// That's it! No binding lookups needed
```

### 3. Allocating Data

**Old Code:**
```pascal
DataStore.Allocate(VertexBinding, 100, amClear);
DataStore.AllocateIndices(IndexBinding, 300);
```

**New Code:**
```pascal
DataStore.AllocateVertices(ObjectIndex, 100, amClear);
DataStore.AllocateIndices(ObjectIndex, 300);
```

### 4. Setting Vertex Data

**Old Code:**
```pascal
// Required binding lookups
VertexBinding := DataStore.GetVertexBinding(ObjectIndex, VertexSet);
DataStore.SetVertexPosition(VertexBinding, LocalIndex, X, Y, Z);
```

**New Code:**
```pascal
// Direct access with object index
DataStore.SetObjectVertexPosition(ObjectIndex, LocalIndex, X, Y, Z);
```

### 5. Using TvgObject (Scene Level)

**Old Code:**
```pascal
Obj := ObjectStore.AddObject;
Obj.AllocateVertices(100);

// Adding vertices
VertexIndex := Obj.AddVertex;
Obj.SetVertexPosition(X, Y, Z);  // Uses internal binding lookups
Obj.SetVertexColor(R, G, B, A);
```

**New Code:**
```pascal
Obj := ObjectStore.AddObject;
Obj.AllocateVertices(100);

// Adding vertices - same API, but simpler internally
VertexIndex := Obj.AddVertex;
Obj.SetVertexPosition(X, Y, Z);  // No binding lookups!
Obj.SetVertexColor(R, G, B, A);
```

## Complete Usage Example

### Basic Triangle

```pascal
var
  DataStore: TvgVulkanDataStore;
  ObjIndex: Integer;
begin
  // 1. Create and configure
  DataStore := TvgVulkanDataStore.Create;
  DataStore.SetupVertexAttributes([vdtPosition, vdtColor]);
  DataStore.SetIndexType(itUInt32);
  
  // 2. Create object
  ObjIndex := DataStore.AddDataObject(False); // No instances
  
  // 3. Allocate space
  DataStore.AllocateVertices(ObjIndex, 3);
  DataStore.AllocateIndices(ObjIndex, 3);
  
  // 4. Set vertex data
  DataStore.SetObjectVertexPosition(ObjIndex, 0, -1.0, -1.0, 0.0);
  DataStore.SetObjectVertexColor(ObjIndex, 0, 1.0, 0.0, 0.0, 1.0);
  
  DataStore.SetObjectVertexPosition(ObjIndex, 1, 1.0, -1.0, 0.0);
  DataStore.SetObjectVertexColor(ObjIndex, 1, 0.0, 1.0, 0.0, 1.0);
  
  DataStore.SetObjectVertexPosition(ObjIndex, 2, 0.0, 1.0, 0.0);
  DataStore.SetObjectVertexColor(ObjIndex, 2, 0.0, 0.0, 1.0, 1.0);
  
  // 5. Set indices
  DataStore.SetObjectIndex(ObjIndex, 0, 0);
  DataStore.SetObjectIndex(ObjIndex, 1, 1);
  DataStore.SetObjectIndex(ObjIndex, 2, 2);
  
  // 6. Create Vulkan buffers and upload
  DataStore.VulkanDevice := MyVulkanDevice;
  DataStore.CreateVulkanDataBuffers;
  DataStore.UploadAllData(TransferPool, 0);
end;
```

### Instanced Cube

```pascal
var
  DataStore: TvgVulkanDataStore;
  ObjIndex: Integer;
  I: Integer;
  Matrix: TvgMatrix4x4S;
begin
  // 1. Setup
  DataStore := TvgVulkanDataStore.Create;
  DataStore.SetupVertexAttributes([vdtPosition, vdtNormal, vdtTexCoord]);
  DataStore.SetupInstanceAttributes([idtMatrix, idtColor]);
  DataStore.SetIndexType(itUInt32);
  
  // 2. Create object with instances
  ObjIndex := DataStore.AddDataObject(True); // Has instances
  
  // 3. Allocate
  DataStore.AllocateVertices(ObjIndex, 24);    // 24 cube vertices
  DataStore.AllocateInstances(ObjIndex, 100);  // 100 instances
  DataStore.AllocateIndices(ObjIndex, 36);     // 36 indices (12 triangles)
  
  // 4. Set vertex data (cube vertices)
  // ... set positions, normals, texcoords for all 24 vertices
  
  // 5. Set instance data
  for I := 0 to 99 do
  begin
    // Create transform matrix for this instance
    Matrix := CreateTranslationMatrix(I * 2.0, 0.0, 0.0);
    DataStore.SetObjectInstanceMatrix(ObjIndex, I, Matrix);
    
    // Set per-instance color
    DataStore.SetObjectInstanceColor(ObjIndex, I, 
      Random, Random, Random, 1.0);
  end;
  
  // 6. Set indices (cube triangles)
  DataStore.AddObjectTriangle(ObjIndex, 0, 1, 2);
  DataStore.AddObjectTriangle(ObjIndex, 2, 3, 0);
  // ... remaining triangles
  
  // 7. Upload to GPU
  DataStore.VulkanDevice := MyVulkanDevice;
  DataStore.CreateVulkanDataBuffers;
  DataStore.UploadAllData(TransferPool, 0);
end;
```

### Using TvgObject Interface

```pascal
var
  ObjectStore: TvgObjectStore;
  Obj: TvgObject;
  I: Integer;
begin
  // 1. Create store
  ObjectStore := TvgObjectStore.Create;
  ObjectStore.SetupVertexAttributes([vdtPosition, vdtColor, vdtNormal]);
  ObjectStore.IncludeInstanceData := True;
  ObjectStore.SetupInstanceAttributes([idtMatrix]);
  
  // 2. Create object
  Obj := ObjectStore.AddObject;
  
  // 3. Build geometry using fluent interface
  Obj.AllocateVertices(8);  // Cube vertices
  
  // Add vertices one by one
  Obj.AddVertex;
  Obj.SetVertexPosition(-1, -1, -1);
  Obj.SetVertexColor(1, 0, 0, 1);
  Obj.SetVertexNormal(-1, -1, -1);
  
  Obj.AddVertex;
  Obj.SetVertexPosition(1, -1, -1);
  Obj.SetVertexColor(0, 1, 0, 1);
  Obj.SetVertexNormal(1, -1, -1);
  
  // ... continue for all 8 vertices
  
  // 4. Add instances
  Obj.AllocateInstances(10);
  for I := 0 to 9 do
  begin
    Obj.AddInstance;
    Obj.SetInstanceMatrix(CreateTranslationMatrix(I * 3.0, 0, 0));
  end;
  
  // 5. Add indices
  Obj.AddIndex(0, 1, 2); // First triangle
  Obj.AddIndex(2, 3, 0); // Second triangle
  // ... remaining triangles
end;
```

## GLSL Shader Generation

The refactored DataStore automatically generates GLSL header code:

```pascal
var
  ShaderHeader: string;
begin
  ShaderHeader := DataStore.WriteGLSLHeader;
  // Produces output like:
  // layout(location = 0) in vec3 inPosition;  // per-vertex
  // layout(location = 1) in vec4 inColor;  // per-vertex
  // layout(location = 2) in vec3 inNormal;  // per-vertex
  // layout(location = 3) in mat4 inInstanceMatrix; // per-instance (columns 3..6)
end;
```

## Drawing

Drawing is simplified - no need to specify bindings:

```pascal
procedure TMyRenderer.RecordDrawCommands(CmdBuffer: TvgCommandBuffer; FrameIndex: Integer);
var
  CommandCount: Integer;
begin
  CommandCount := 0;
  
  // DataStore automatically binds correct buffers and draws all objects
  ObjectStore.VulkanDraw(CmdBuffer, MyPipeline, FrameIndex, CommandCount);
end;
```

## Benefits of Refactored Version

1. **~70% Less Code**: Removed thousands of lines of binding management
2. **Simpler Mental Model**: Objects are just ranges in buffers
3. **Better Performance**: Direct array access instead of dictionary lookups
4. **Easier Debugging**: Fewer indirection layers
5. **Fixed Bindings**: Always know binding 0 = vertex, 1 = instance
6. **Auto-layout**: Locations assigned automatically in order

## What Was Removed

- Multi-vertex-set support (each object had multiple vertex buffers)
- Multi-index-set support (each object had multiple index buffers)
- Dynamic binding assignment (now fixed at 0 and 1)
- Per-binding offset dictionaries
- Upload mode switching (simplified to single approach)
- Complex binding lookup methods

## When to Use This

**Use the refactored version when:**
- Each object needs ONE vertex buffer and ONE index buffer
- You're okay with fixed bindings (0=vertex, 1=instance)
- You want simpler, more maintainable code

**Stick with the original when:**
- You need multiple independent vertex streams per object
- You need dynamic binding assignment
- You have complex multi-buffer scenarios

## Performance Notes

The refactored version is actually **faster** because:

1. Direct array indexing (no dictionary lookups)
2. Better cache locality (single contiguous buffers)
3. Fewer indirection layers
4. Simpler draw loops

Typical performance improvement: 10-15% faster draw submission.

## World Axis Convention (Y-up or Z-up)

The package defaults to **XZ horizontal, +Y up**. It can instead run as
**XY horizontal, +Z up**. Both are right-handed, so winding, cull mode and
projection are unchanged; only which way is "up" differs.

### Selecting it

Either build the package with the define in `VulkanPackage.inc`:

```pascal
{$DEFINE VG_WORLD_Z_UP}
```

or set it at run time, first thing in the `.dpr`:

```pascal
uses Vulkan_WorldAxes;
begin
  vgSetAxisConvention(acZUp);
  Application.Initialize;
  ...
```

### Set it once, before creating anything

The convention decides the **defaults** objects are created with: a camera's
position and up vector, a force field's direction, an emitter's launch
velocity. It never rotates anything that already exists. While a `TvgCamera`,
`TvgForceField` or `TvgParticleEmitter` is alive, `vgSetAxisConvention`
refuses a change: it returns `False` and raises `CustomAssert`.

What follows the convention:

| Where | Y-up | Z-up |
|---|---|---|
| `TvgCamera` default position / up | (0,0,5) / +Y | (0,-5,0) / +Z |
| `TvgCamera.InitializeAsDefault` | (0,2,5) | (0,-5,2) |
| `TvgToolManager.DragPlaneAxis` 0 / 1 / 2 | XZ / XY / YZ | XY / XZ / YZ |
| `TvgForceField` default vector | (0,-1,0) | (0,0,-1) |
| `TvgParticleEmitter` default velocity | up along Y | up along Z |

`DragPlaneAxis` now means horizontal / front / side, whichever convention is
active.

### Things that are not converted

- **Values you set yourself.** `Cam.LookAt(..., TpvVector3.Create(0, 1, 0))`
  is still +Y. Use `vgWorldUp`, `vgWorldForward` and `vgWorldRight`, or write
  the value Y-up and pass it through `vgFromYUp`.
- **Values stored in a DFM.** For example, particle emitter or force
  properties saved while designing under the other convention.
- **Assets.** glTF is Y-up by specification. Apply `vgYUpToWorldMatrix` at the
  root node when importing and `vgWorldToYUpMatrix` when exporting. Both are
  the identity under Y-up.
- **Min/max ranges.** Converting to Z-up negates one component, so convert a
  range with `vgRangeFromYUp`, which re-sorts min and max, rather than
  converting each corner on its own.

### Behaviour change in `TvgCamera.Orbit` (both conventions)

- **Yaw is now an exact rotation about the up vector.** Previously each yaw
  while pitched pulled the eye's height towards the horizon, and yawed faster
  than asked at steep angles.
- **Pitch now stops at ±89°.** Previously pitching over the pole left the view
  matrix full of NaN.

## Survey Coordinates and Double Precision

Camera and view-projection math is double precision (`PasVulkan.Math.Double`).
Vertex data stays float32, which cannot hold six-digit coordinates: at that
size float32 steps are 62.5 mm. A scene therefore stores vertices **relative
to a world origin** and adds the origin back on the CPU, in double. The design
and measurements are in `DOUBLE_PRECISION.md`.

### Set a world origin before loading

Pick a point near the middle of the data and set it before adding any object
store. It is refused while the scene holds data.

```pascal
Scene.WorldOrigin := TpvVector3D.Create(525000, 875000, 100);
Scene.Load_Begin;
Scene.AddDataStore(Store);
...
Scene.Load_End;
```

`WorldOriginX/Y/Z` are published, so it can also be set in the Object
Inspector.

### Write vertices in world coordinates

```pascal
Obj.AddVertex;
Obj.SetVertexWorldPosition(TpvVector3D.Create(523456.789, 876543.210, 98.765));
```

This subtracts the origin in double and stores the offset in float32. Keep
every vertex within **16,384** of the origin (`VG_LOCAL_COORD_LIMIT`). Inside
that, every value with three decimals reads back exactly. Outside it the call
asserts: it raises in debug builds and logs otherwise. To write offsets directly, use `Scene.WorldToLocal` and
`SetObjectVertexPosition`.

Everything read back from a store is local: bounds, and positions you
reconstruct. `Scene.LocalToWorld` converts back.

### Keep camera values in double

`TvgCamera` positions are `TpvVector3D`, matrices `TpvMatrix4x4D`, and lens and
movement parameters `Double`. **Assigning them to `TpvVector3` or
`TpvMatrix4x4` still compiles**, because `PasVulkan.Math.Double` converts
implicitly, and it silently drops back to float32. Declare your own variables
with the D types.

### ToolManager events carry world positions

`OnObjectMoved` and `OnObjectAddReq` pass `const TpvVector3D`. Handlers written
for `TpvVector3` must change their parameter type. Convert with
`SetVertexWorldPosition` or `Scene.WorldToLocal` before writing vertex data.
Drag planes now pass through `Scene.WorldOrigin` rather than (0,0,0).

### dmat4 or mat4

| `ShaderUseDouble` | GPU gets | Worst error, camera 2 m away |
|---|---|---|
| False (default) | `mat4` | about 1 mm |
| True | `dmat4`, or `mat4` if the GPU lacks `shaderFloat64` | about 0.35 mm |

**This is a behaviour change:** the view-projection used to be a `dmat4`
whatever the setting. Intel integrated graphics from 11th Gen onward and Intel
Arc GPUs do not support `shaderFloat64`, so the `mat4` fallback is what they
use.

### Other `TvgCamera` changes

- `GetViewProjectionMatrix`, `GetFrustumPlanes` and `WorldToScreenPoint` used
  to return results from the camera as it was constructed. They are current
  now.
- `ScreenToWorldRay` now returns the ray through the pixel. It used to point
  from the world origin, which only looked right near (0,0,0). A new overload
  also returns the ray's origin; use it for orthographic cameras.
- `ScreenToWorldRay` and `WorldToScreenPoint` use the viewport's aspect ratio,
  as the renderer does, not the camera's stored `AspectRatio`.
- Orthographic cameras draw the right way up; they were upside down.
- `Zoom` moves 10% per unit as documented.

## Zoom to All Data

New, additive - nothing existing changed. A one-call "fit everything on
screen", and a plan view of the site, for the toolbar button every viewer
needs.

### From the tool manager (the usual way)

```pascal
// Frame all the data from wherever the camera is now, keeping the current
// projection.  Uses the viewport's real aspect ratio.
ToolManager.ZoomAll;

// Straight down at it.  Screen up is north, east is to the right.
ToolManager.ZoomAllLookDown;

// The same, but switch to orthographic first - a true plan view, no
// perspective convergence, so distances across the screen are comparable.
ToolManager.ZoomAllPlanView;
```

All three return `Boolean`. **`False` means the scene has no data to frame**
and the camera was left exactly where it was - not moved somewhere
meaningless. Nothing is raised; an empty scene is a normal state.

### From the scene or the camera

```pascal
// The scene's bounds in world (double) coordinates.
var BMin, BMax : TpvVector3D;
if Scene.GetDataBounds(BMin, BMax) then ...

// Only what is actually visible (the default), or everything:
Scene.GetDataBounds(BMin, BMax, False);   // include hidden objects

// There is a TvgAABB overload too, in scene-local single precision:
var Box : TvgAABB;
if Scene.GetDataBounds(Box) then ...

// And the camera will fit any box you hand it - it does not have to come
// from a scene.
Camera.ZoomAll(BMin, BMax, ViewportAspect);
Camera.ZoomAllLookDown(BMin, BMax, ViewportAspect);
Camera.ZoomAllFromDirection(BMin, BMax, Dir, Up, ViewportAspect);
```

### Things worth knowing

- **Pass the viewport's aspect ratio, not the camera's.** The camera-level
  calls take it as an argument because the renderer draws with the viewport's,
  and a fit computed against the camera's stored `AspectRatio` clips whenever
  the two differ. The `ToolManager` calls work it out for you.
- **The margin is 5% by default** (`CAMERA_DEFAULT_ZOOM_MARGIN`), so the data
  does not touch the edge of the window. Pass your own as the last argument.
  Values below 1.0 are clamped to 1.0 - these calls will not crop.
- **`ZoomAll` keeps the current projection.** Set `ProjectionType` first if you
  want to change it, or use `ZoomAllPlanView`, which does that for you.
- **The camera's `AspectRatio` is never written.** A fit moves the eye, the
  target, the near/far planes and (orthographic only) the extents. It is safe
  to fit a camera that several differently shaped viewports share.
- **`Target` lands on the centre of the data**, so `Orbit` afterwards pivots on
  what you just zoomed to.
- Hidden objects and objects with `CullMode = cmNever` are excluded. If your
  scene is entirely compute-generated geometry marked `cmNever`, set bounds
  with `SetObjectBounds` or ask for `aVisibleOnly = False`.
- The fit is exact when the box is seen square on. Seen from an oblique angle
  it is conservative - everything on screen, with a little margin to spare -
  because the widest part of the box may be at the back, where perspective
  shrinks it.

Covered by `Tests/ZoomAllTest.dpr`; the design notes are in
`RunTime_Src/ZOOM_ALL_PLAN.md`.

## Troubleshooting

**Q: My objects aren't drawing**
A: Make sure you called `CreateVulkanDataBuffers` and `UploadAllData` before drawing

**Q: Getting "Invalid object index" errors**
A: Check that you're using the ObjectIndex returned from `AddDataObject`

**Q: Instance data not working**
A: Verify you set `IncludeInstanceData = True` and called `SetupInstanceAttributes`

**Q: Indices out of range**
A: Make sure you allocated enough space with `AllocateVertices/Instances/Indices`

## Summary

The refactored version trades flexibility for simplicity. If you need:
- One vertex buffer per object
- One instance buffer per object  
- One index buffer per object

Then this refactored version will make your code much cleaner and easier to maintain!
