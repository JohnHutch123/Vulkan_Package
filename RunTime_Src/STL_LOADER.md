# STL loading and saving

Two units, both in the Delphi 11, 12 and 13 core runtime packages:

- `Vulkan_STL.pas` is the file format on its own: a `TvgSTLMesh` record and
  routines to read binary or ASCII STL, write either, weld shared corners,
  and measure a mesh. It needs no Vulkan and also compiles with Free Pascal
  3.2, so a console tool can make or convert meshes with it.
- `Vulkan_LoaderStorer_STL.pas` supplies `TvgSceneLoaderStorer_STL`, which
  loads an STL file into a `TvgScene` and stores a scene as STL. It
  registers `.stl` with `Vulkan_SceneLoaders`, so `vgLoadSceneFile` and the
  data module's **Load Scene File** actions pick it. At design time it is on
  the **Vulkan Graphics** palette.

```pascal
uses Vulkan_LoaderStorer_STL, Vulkan_SceneLoaders;

vgLoadSceneFile(Scene, 'C:\Models\part.stl');
```

Or directly, which also gives the save side:

```pascal
Loader := TvgSceneLoaderStorer_STL.Create(nil);
try
  Loader.Scene := Scene;
  Loader.FileName := 'C:\Models\part.stl';
  Loader.LoadScene;
  ...
  Loader.FileName := 'C:\Models\part_copy.stl';
  Loader.StoreScene;          // binary; set Ascii := True for text
finally
  Loader.Free;
end;
```

## Loading

- Binary or ASCII is detected from the content. A file whose size matches a
  binary STL's triangle count is binary even if its header starts with
  `solid`, as many exporters write.
- ASCII: keywords in any case, CR/LF or LF, exponents, several `solid`
  blocks (read as one mesh). A facet with more than three vertices is fanned
  into triangles. Numbers always use `.` whatever the locale.
- The whole file is read and checked before the scene is touched: a bad or
  truncated file raises `EvgSTLError` and leaves the scene as it was.
- One `TvgSTLObjectStore` (a `TvgOBJShadedStore`, drawn with the OBJ prebuilt
  shaders) holds the mesh, in `Color` (light grey by default).
- `WeldVertices` (default True) merges the corners STL repeats, so each
  vertex is stored once with an area-weighted normal and the store is shaded
  smooth. `WeldTolerance` merges corners closer than that distance; 0 merges
  only identical ones. Triangles that collapse are dropped with a warning.
  With `WeldVertices` False every triangle keeps its own corners and the
  store is shaded flat.
- The binary attribute word is read into `TvgSTLMesh.Attributes` but not
  shown: colour conventions for it differ between programs.

## Meshes made in code

`LoadMesh(Mesh)` puts a `TvgSTLMesh` into the scene the same way, without a
file: for example a surface from marching cubes. `BuildStore` makes the store
without adding it, for a scene that keeps other data.

## Saving

`StoreScene` writes every triangle of the scene in world coordinates:
triangle lists, strips and fans, indexed or not. Lines and points, hidden
objects, coarser level-of-detail copies and the preview store are left out.
Normals are computed from the triangles. `SceneMesh` returns the same
triangles as a `TvgSTLMesh`.

STL has no units or axis convention. Most medical and 3D-printing files are
millimetres with Z up; positions are written as they are in the scene.

## Mesh tools in `Vulkan_STL`

| Routine | Does |
|---|---|
| `vgReadSTL`, `vgReadSTLStream`, `vgReadSTLBytes` | Read either format |
| `vgWriteSTL`, `vgWriteSTLStream` | Write binary (default) or ASCII |
| `vgWeldSTL` | Merge equal (or near) corners; returns triangles dropped |
| `vgSTLVertexNormals` | Area-weighted unit normal per vertex |
| `vgSTLBounds`, `vgSTLArea`, `vgSTLVolume` | Box, surface area, enclosed volume |
| `vgSTLOpenEdges` | Edges not shared by exactly two triangles; 0 means watertight |
