# Simple OBJ loading

`Vulkan_Loader_OBJ.pas` supplies `TvgSceneLoader_OBJ`, a load-only descendant
of `TvgSceneLoaderStorer`. It is included in the Delphi 11, 12 and 13 core
runtime packages and registers `.obj` with `Vulkan_SceneLoaders`. The existing
scene and data-module **Load Scene File** actions can therefore select it.
For an application compiled directly from source, include `Vulkan_Loader_OBJ`
in its uses clause to activate registration.

```pascal
uses Vulkan_Loader_OBJ, Vulkan_SceneLoaders;

// Scene is an existing TvgScene.
vgLoadSceneFile(Scene, 'C:\Models\example.obj');
```

Or create the component directly:

```pascal
Loader := TvgSceneLoader_OBJ.Create(nil);
try
  Loader.Scene := Scene;
  Loader.FileName := 'C:\Models\example.obj';
  Loader.LoadScene;
finally
  Loader.Free;
end;
```

## Supported subset

- `v x y z [w]` positions, with optional nonzero homogeneous weight.
- `f` faces using one-based indices or negative indices relative to the
  positions already read. Zero and out-of-range position indices are errors.
- `v`, `v/vt`, `v//vn`, and `v/vt/vn` face-corner syntax. Only positions
  are imported; optional attribute indices are syntax checked but not resolved.
- Triangles and convex polygons, triangulated as a fan in the file's winding
  order. Export concave polygons as triangles before loading.
- Blank lines, spaces, tabs, comments (including inline comments), UTF-8 files,
  and dot decimal numbers independently of Windows locale.

The file becomes one indexed triangle object in one store. Object/group names,
normals, texture coordinates, materials, smoothing, lines, points and other
records are ignored. No MTL or texture files are opened. Vertex colour
extensions and continued records are not supported. Coordinates and axis
conventions are kept as supplied; there is no axis conversion or auto-scaling.
An empty file or file without polygon faces is rejected.

The object uses uniform grey vertex colour and the public `EditLines` shader
pair, whose position/colour/object-ID inputs also work with triangle topology.
Make `EditLines_vert.spv` and `EditLines_frag.spv` available through
`ShaderFolderPath`, as described in [the shader guide](../VulkanShaders/README.md).
Lighting and textured rendering are outside this loader's scope.

Loading replaces the scene. File reading, parsing and CPU geometry construction
finish before `Load_Begin`, so failures during those steps keep the existing
scene. GPU pipeline failures during `Load_End` are not transactional.
Malformed geometry raises `EvgOBJError` with its file and line number; file I/O
errors use the standard Delphi exceptions. `StoreScene` exists because the base
class requires it, but always raises `EvgOBJError` without writing anything.

`Tests/OBJLoaderTest.dpr` tests real scene data and registry loading without a GPU.
Run it with the other console tests using `Tests/RunTests.bat`.
