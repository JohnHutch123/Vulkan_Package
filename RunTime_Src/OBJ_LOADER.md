# OBJ and MTL loading

`Vulkan_Loader_OBJ.pas` supplies `TvgSceneLoader_OBJ`, a load-only descendant
of `TvgSceneLoaderStorer`. It is included in the Delphi 12 and 13 core
runtime packages and registers `.obj` with `Vulkan_SceneLoaders`. The existing
scene and data-module **Load Scene File** actions can therefore select it.
For an application compiled directly from source, include `Vulkan_Loader_OBJ`
in its uses clause to activate registration.

```pascal
uses Vulkan_Loader_OBJ, Vulkan_SceneLoaders;

// Scene is an existing TvgScene.
vgLoadSceneFile(Scene, 'C:\Models\example.obj');
```

At design time `TvgSceneLoader_OBJ` is on the **Vulkan Graphics** palette.
Drop one on a `TvgVulkanDataModule` to make it the module's `SceneLoader`,
or leave `SceneLoaderType` blank (or set it to `OBJ`) and point
`SceneFileName` at an `.obj` file. The *Load Scene File...* verbs list `.obj`
in their file filter. The `Tests/Test Vulkan` sample has a **Load File...**
button that loads any registered format and zooms to it.

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

## Geometry

- `v x y z [w]` positions, with optional nonzero homogeneous weight.
- `v x y z r g b` vertex colours (the MeshLab/CloudCompare extension),
  0..1 per channel. Explicit colours modulate material diffuse colour; without
  a material they retain their original brightness. Uncoloured, unmaterialled
  vertices use grey.
- `f` faces using one-based indices or negative indices relative to the
  positions already read. Zero and out-of-range position indices are errors.
- `vt` texture coordinates and `vn` normals. Independent positive/negative
  indices in `v`, `v/vt`, `v//vn`, and `v/vt/vn` corners are resolved and checked.
  Vertices split at UV seams and normal boundaries. Only referenced vertices
  enter the scene, so counts can differ from the number of `v` records.
- Simple planar convex and concave polygons, triangulated in the source winding
  order. Degenerate triangles are retained; degenerate or untriangulatable
  larger polygons are errors. Self-intersecting/nonplanar polygons are outside
  the supported subset and should be triangulated by the exporter.
- `s` smoothing groups: explicit normals are kept, and missing normals are
  generated with area weighting within a smoothing group. `s off`/`s 0` (the
  default) creates flat polygon normals. Smoothing crosses material/UV boundaries
  but not object boundaries.
- `o` object names and `g` group names. A new scene-owned `TvgOBJObjectStore`
  starts at each object/group/material/topology boundary. Each store contains
  one indexed object; multiple group names are kept as a space-separated string.
- `l` polylines become indexed line segments; `p` records become indexed points.
- Blank lines, spaces, tabs, comments (including inline comments), UTF-8 files,
  trailing-backslash continuations, quoted names, and dot decimal numbers
  independently of Windows locale.

Coordinates and winding are kept as supplied; there is no axis conversion or
auto-scaling. Two-dimensional source UVs are kept in vertex data; the texture
shader applies each diffuse map's scale/offset and flips V for image sampling.
The optional third `vt` component is not used by this 2D texture layout.
Empty files or files containing only coordinate definitions are errors.

### Vertex layout and tangent frames

Every store's vertices hold, in shader input order: position (location 0),
colour (1), normal (2), UV (3), tangent (4), bitangent (5); the per-instance
object ID follows at location 6. `OBJ.vert` declares the same layout.

The tangent frame is generated for normal-mapped lighting, which the unlit
OBJ shaders do not do yet:

- Per triangle, the UV derivatives give a tangent along +U and a bitangent
  along +V of the file's own UVs (V up: the OpenGL normal-map convention,
  which OBJ/MTL exporters use). Each vertex sums those of its triangles, so
  the frame is shared and smoothed like the vertex itself - split at UV seams
  and normal boundaries.
- The tangent is made perpendicular to the (unit) vertex normal by
  Gram-Schmidt, and the bitangent rebuilt as normal x tangent, reversed where
  the UVs are mirrored. Tangent, bitangent and normal are orthonormal at every
  vertex.
- Where there are no usable UVs - none in the file, or degenerate on every
  triangle around the vertex - and for lines and points, the tangent is any
  unit vector perpendicular to the normal.

A diffuse map's `-s`/`-o` scale and offset are applied at sampling and do not
change the frame; a negative scale mirrors the map relative to it.
Free-form curves/surfaces (`vp`, `curv`, `curv2`, `surf`, `cstype`) and `call`
are explicitly rejected. Other unsupported OBJ rendering hints are ignored.

## Materials, textures and lighting data

`mtllib` loads one or more MTL libraries; `usemtl` assigns named materials.
Libraries resolve relative to the OBJ; texture paths resolve relative to their
MTL. Absolute paths and quoted filenames containing spaces are supported.
An unquoted library filename containing spaces is accepted when that complete
path exists. Missing MTL libraries and undefined material names fall back to
opaque grey, preserving explicit vertex colours and the requested material name.
Available libraries still load when other libraries are missing, so OBJ-only
files can be opened even if they contain `mtllib` and `usemtl` statements.
Malformed libraries that are present, and missing textures referenced by a
loaded material, remain errors.

A missing library or material is not silent: after `LoadScene` the loader's
`Warnings` (on `TvgSceneLoaderStorer`, so any loader can report) lists each
one once, with its line and the folder searched, e.g.
`Material library "Plants 190.mtl" (line 1) not found in D:\Models\ - its
materials are drawn grey`. Warnings are cleared at the start of each load.
`vgLoadSceneFile(Scene, FileName, Warnings)` hands back those of the temporary
loader it frees; `TvgVulkanDataModule.SceneLoadWarnings` holds the last
`LoadScene`'s. The IDE's *Load Scene File...* shows them in a dialog, and the
`Tests/Test Vulkan` sample's **Load File...** writes them to its message log.

`TvgOBJObjectStore.Material` retains these properties after the loader is freed:

| MTL records | Material fields |
|---|---|
| `Ka`, `Kd`, `Ks`, `Ke`, `Tf` | Ambient, Diffuse, Specular, Emissive, Transmission |
| `Ns`, `Ni`, `illum`, `sharpness` | Shininess, OpticalDensity, IlluminationModel, Sharpness |
| `d`, `d -halo`, `Tr` | Opacity (Tr converted to 1-Tr), Halo |
| `Pr`, `Pm`, `Ps`, `Pc`, `Pcr`, `aniso`, `anisor` | Roughness, Metallic, Sheen, Clearcoat, ClearcoatRoughness, Anisotropy, AnisotropyRotation |

Colours accept RGB triples, a single value, or `xyz` (converted to linear RGB).
Spectral colour files are not supported. Unknown MTL statements are retained in
`ExtraStatements`. Repeated properties use their last declaration.

All referenced `map_*`, `bump`, `norm`, `disp`, `decal`, and `refl` image files
on used materials are read into scene-owned shared texture descriptors, even
when not yet sampled by the renderer. `Material.Maps` contains each map's kind,
resolved filename, descriptor binding, options and typed parameters. Diffuse
`map_Kd` is always binding 0; the other maps follow in declaration order.
Reflection cube faces are retained individually by their `-type` projection.

Parsed map options: `-o`, `-s`, `-t`, `-clamp`, `-blendu`, `-blendv`, `-bm`,
`-mm`, `-imfchan`, `-type`, `-colorspace`, `-texres`, `-boost`, `-cc`. The final
two are retained in the raw `Options` string. Unknown options are errors.
Current display applies diffuse scale/offset, clamp, and brightness/contrast.
Other map controls are data for future shader work, including colour-space
overrides. Normal/bump mapping, displacement, reflections, opacity-map sampling,
lighting and transparency sorting/blending are not implemented by this loader.

No scene light records are created. Material lighting properties are loaded
only; create actual lights separately through the existing `Scene.Lights` API.
As with other scene loads, loading replaces the existing scene, including lights.

```pascal
Store := TvgOBJObjectStore(Scene.SceneData[0]);
Material := Store.Material; // TvgOBJMaterial record; CPU data, not a light
// Material.Ambient, .Specular, .Emissive, .Shininess, .Maps, ...
```

## Display and shaders

The supplied OBJ shaders display vertex/material diffuse colour multiplied by
the diffuse texture, with material opacity in output alpha. They do not perform
lighting. The store selects float/double view-projection and no-picking,
storage-buffer-picking or image-picking variants to match the renderer.
They are read from the package's `VulkanShaders` folder only, found with no
setup from builds in (or beside) the checkout; a deployed application ships
**all `OBJ*.spv` files** in a `VulkanShaders` folder beside the exe, as described in [the shader guide](../VulkanShaders/README.md).
The previous `EditLines` pair is no longer used by this loader.

## Drawing many copies (instancing)

A loaded model can draw its meshes many times, one 4x4 matrix per copy,
without copying any vertices. `Vulkan_Instancing` does it for any loader's
stores, live or not:

```pascal
Copies := TvgInstanceSet.Create(Stores);   // every store of the model
Settings := TvgScatterSettings.Default(500, RegionMin, RegionMax);
Settings.ModelUp := TpvVector3D.Create(0, 1, 0);   // authored Y up; zero = world up
Copies.SetMatrices(vgScatterMatrices(Settings, Surface, Copies.BasePivot(Settings.ModelUp)));
```

OBJ coordinates are kept as written, so a Y-up export in a Z-up world lies on
its side until `ModelUp` stands it up.

`Surface` is any `IvgSurfaceSampler` - `TvgFlatSurface` for a fixed height.
Each store is converted with `vgMakeStoreInstanced` and every object gets the
same copies, carrying its own object ID. By hand, before the store has GPU
buffers:

```pascal
Store := TvgOBJObjectStore(Scene.SceneData[I]);   // each store of the model
Store.ChangeInstanceAttributes([idtObjID, idtMatrix]);
Store.GetObjectInstanceObjID(0, 0, ID1, ID2);
// instance 0 is the loaded one; add the rest
Copy := Store.AddObjectInstance(0);
Store.SetObjectInstanceObjID(0, Copy, ID1, ID2); // new instances start at ID 0
Store.SetObjectInstanceMatrix(0, Copy, M);       // TvgMatrix4x4S, [column, row]
```

Existing and new instances start with an identity matrix, and the existing
object ID is kept. The store then loads the `OBJInst` vertex shader (matrix at
locations 7..10) and culls against the union of the copies. Give every store
of a model the same matrices so its parts stay together. The matrix moves
positions only; normals and tangents are not yet transformed, which the unlit
shaders do not need.

## Errors and tests

Loading replaces the scene. OBJ/MTL reading, texture-source loading and CPU geometry
construction finish before `Load_Begin`, so failures during those steps keep the existing
scene. GPU pipeline failures during `Load_End` are not transactional.
Malformed geometry raises `EvgOBJError` with its file and line number; file I/O
errors use the standard Delphi exceptions. `StoreScene` exists because the base
class requires it, but always raises `EvgOBJError` without writing anything.

Texture headers are inspected before scene replacement. Full GPU image decode,
upload and pipeline creation still take place later and are not transactional.

`Tests/OBJLoaderTest.dpr` covers the original geometry/registry/file contract;
`Tests/OBJMaterialTest.dpr` covers normals, UVs, smoothing, concave triangulation,
materials, texture sources, descriptor bindings, shader variant selection and
failure preservation. Both run without a GPU via `Tests/RunTests.bat`.
`OBJLoaderTest` accepts an optional path to TeaPot.obj; `OBJMaterialTest` accepts
an optional shader-folder path when run outside the usual Tests/Win32 folder.

Format references: [OBJ](https://www.loc.gov/preservation/digital/formats/fdd/fdd000507.shtml)
and [MTL](https://www.loc.gov/preservation/digital/formats/fdd/fdd000508.shtml),
including links to the original Wavefront documentation.
