unit Vulkan_LoaderStorer_STL;

{ STL scene loader and storer.  Public Vulkan Package, zlib licence.

  Load: one store per file, triangles, drawn with the OBJ prebuilt shaders
  (TvgOBJShadedStore) in one colour.  WeldVertices (the default) merges the
  corners STL repeats, so the store holds each vertex once with a smooth,
  area-weighted normal; off, every triangle keeps its own corners and the
  store is shaded flat.

  Store: every triangle of the scene, in world coordinates, as binary STL
  (or ASCII).  Triangle lists, strips and fans are written; lines, points,
  hidden objects, coarser level-of-detail copies and the preview store are
  not.

  LoadMesh puts a mesh made in code (a TvgSTLMesh: a marching-cubes surface,
  say) into the scene the same way, with no file.  SceneMesh returns what
  StoreScene would write.

  The file format itself is in Vulkan_STL, which needs no Vulkan. }

interface

uses
  System.SysUtils, System.Classes, PasVulkan.Math, Vulkan_Components,
  Vulkan_Components_Scene_Renderer, Vulkan_Components_Lookups,
  Vulkan_Loader_OBJ, Vulkan_STL,
  PasVulkan.Math.Double,
  Vulkan_Components_DataStore,
  Vulkan_SceneLoaders,
  Vulkan_MeshBuilder;

type
  // A store made from an STL mesh.  Shading and Ambient are inherited.
  TvgSTLObjectStore = class(TvgOBJShadedStore)
  private
    fSolidName: string;
    fTriangleCount: Integer;
    fWelded: Boolean;
  public
    property SolidName: string read fSolidName;
    property TriangleCount: Integer read fTriangleCount;
    // True if corners were merged (smooth normals), False for one per triangle.
    property Welded: Boolean read fWelded;
  end;

  TvgSceneLoaderStorer_STL = class(TvgSceneLoaderStorer)
  private
    fFileName: string;
    fWeldVertices: Boolean;
    fAscii: Boolean;
    fColor: TpvVector4;
    fWeldTolerance: Single;
    procedure ReplaceScene(aStore: TvgSTLObjectStore);
  public
    constructor Create(AOwner: TComponent); override;
    procedure LoadScene; override;
    procedure StoreScene; override;

    // Replaces the scene's contents with aMesh, as LoadScene does with a file.
    procedure LoadMesh(const aMesh: TvgSTLMesh);
    // Every exportable triangle of the scene in world coordinates, unwelded.
    function SceneMesh: TvgSTLMesh;
    { A store holding aMesh, not yet in any scene (the caller owns it until it
      is added).  aWeld merges corners first - aMesh itself is unchanged.
      aTolerance as vgWeldSTL. }
    class function BuildStore(const aMesh: TvgSTLMesh; aWeld: Boolean;
      const aColor: TpvVector4; aTolerance: Single = 0): TvgSTLObjectStore; overload;
    // As above, also giving the number of triangles the weld dropped.
    class function BuildStore(const aMesh: TvgSTLMesh; aWeld: Boolean;
      const aColor: TpvVector4; aTolerance: Single; out aDropped: Integer): TvgSTLObjectStore; overload;

    // Vertex colour of loaded meshes, RGBA 0..1.  Light grey by default.
    property Color: TpvVector4 read fColor write fColor;
  published
    property FileName: string read fFileName write fFileName;
    property WeldVertices: Boolean read fWeldVertices write fWeldVertices default True;
    // Weld distance in file units; 0 (the default) merges only equal corners.
    property WeldTolerance: Single read fWeldTolerance write fWeldTolerance;
    // StoreScene writes ASCII instead of binary.
    property Ascii: Boolean read fAscii write fAscii default False;
  end;

implementation


{ TvgSceneLoaderStorer_STL }

constructor TvgSceneLoaderStorer_STL.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  fWeldVertices := True;
  fColor := TpvVector4.Create(0.85, 0.85, 0.82, 1.0);
end;

class function TvgSceneLoaderStorer_STL.BuildStore(const aMesh: TvgSTLMesh;
  aWeld: Boolean; const aColor: TpvVector4; aTolerance: Single): TvgSTLObjectStore;
var Dropped: Integer;
begin
  Result := BuildStore(aMesh, aWeld, aColor, aTolerance, Dropped);
end;

class function TvgSceneLoaderStorer_STL.BuildStore(const aMesh: TvgSTLMesh;
  aWeld: Boolean; const aColor: TpvVector4; aTolerance: Single;
  out aDropped: Integer): TvgSTLObjectStore;
var
  Mesh: TvgSTLMesh;
  Normals: TArray<TvgSTLVector>;
  Data: TvgMeshData;
  K, T: Integer;
  N: TvgSTLVector;
begin
  Mesh := aMesh;   // arrays are shared, but vgWeldSTL replaces rather than edits them
  aDropped := 0;
  if aWeld then
  begin
    aDropped := vgWeldSTL(Mesh, aTolerance);
    Normals := vgSTLVertexNormals(Mesh);
  end
  else
  begin
    // One normal per corner: the triangle's own, from its positions.
    SetLength(Normals, Length(Mesh.Positions));
    for T := 0 to Mesh.TriangleCount - 1 do
    begin
      N := vgSTLTriangleNormal(Mesh.Positions[Mesh.Indices[3 * T]],
        Mesh.Positions[Mesh.Indices[3 * T + 1]], Mesh.Positions[Mesh.Indices[3 * T + 2]]);
      for K := 0 to 2 do Normals[Mesh.Indices[3 * T + K]] := N;
    end;
  end;

  Result := TvgSTLObjectStore.Create(nil);
  try
    Result.fSolidName := Mesh.Name;
    Result.fTriangleCount := Mesh.TriangleCount;
    Result.fWelded := aWeld;
    vgSetupShadedStore(Result, TRIANGLE_LIST);
    if aWeld then Result.Shading := osSmooth else Result.Shading := osFlat;
    if Mesh.TriangleCount = 0 then Exit;

    // STL has no colours or texture coordinates: vgWriteMesh fills in aColor
    // and builds a tangent frame about each normal, which the OBJ shaders'
    // vertex layout needs.
    Data.Clear;
    Data.Topology := TRIANGLE_LIST;
    SetLength(Data.Positions, Length(Mesh.Positions));
    SetLength(Data.Normals, Length(Mesh.Positions));
    for K := 0 to High(Mesh.Positions) do
    begin
      Data.Positions[K] := TpvVector3.Create(Mesh.Positions[K].X, Mesh.Positions[K].Y, Mesh.Positions[K].Z);
      Data.Normals[K] := TpvVector3.Create(Normals[K].X, Normals[K].Y, Normals[K].Z);
    end;
    SetLength(Data.Indices, Length(Mesh.Indices));
    for K := 0 to High(Mesh.Indices) do Data.Indices[K] := Mesh.Indices[K];
    vgWriteMesh(Result, 0, Data, aColor);
  except
    Result.Free; raise;
  end;
end;

procedure TvgSceneLoaderStorer_STL.ReplaceScene(aStore: TvgSTLObjectStore);
begin
  try
    if not fScene.Load_Begin then raise EvgSTLError.Create('Scene is not ready to load an STL mesh');
  except
    aStore.Free; raise;
  end;
  fCurrentObjectStore := nil;
  try
    fScene.AddDataStore(aStore);
    fCurrentObjectStore := aStore;
  finally fScene.Load_End; end;
end;

procedure TvgSceneLoaderStorer_STL.LoadMesh(const aMesh: TvgSTLMesh);
begin
  ClearWarnings;
  if not Assigned(fScene) then raise EvgSTLError.Create('STL loader requires a Scene');
  ReplaceScene(BuildStore(aMesh, fWeldVertices, fColor, fWeldTolerance));
end;

procedure TvgSceneLoaderStorer_STL.LoadScene;
var Mesh: TvgSTLMesh; Store: TvgSTLObjectStore; Dropped: Integer;
begin
  ClearWarnings;
  if not Assigned(fScene) then raise EvgSTLError.Create('STL loader requires a Scene');
  if Trim(fFileName) = '' then raise EvgSTLError.Create('STL loader requires a FileName');
  // The whole file is read and checked before the current scene is touched.
  Mesh := vgReadSTL(ExpandFileName(fFileName));
  if Mesh.TriangleCount = 0 then AddWarning('The STL file has no triangles');
  Store := BuildStore(Mesh, fWeldVertices, fColor, fWeldTolerance, Dropped);
  if Dropped > 0 then
    AddWarning(Format('%d degenerate triangles (corners that coincide) were dropped', [Dropped]));
  if Store.fSolidName = '' then Store.fSolidName := ChangeFileExt(ExtractFileName(fFileName), '');
  ReplaceScene(Store);
end;

function TvgSceneLoaderStorer_STL.SceneMesh: TvgSTLMesh;
var
  Positions: TArray<TvgSTLVector>;
  NP, I: Integer;
  MeshName: string;
begin
  Result.Clear;
  if not Assigned(fScene) then raise EvgSTLError.Create('STL storer requires a Scene');
  NP := 0;
  Positions := nil;
  MeshName := '';
  vgForEachSceneMesh(fScene,
    procedure(const aItem: TvgSceneMesh)
    var
      Tris: TArray<Cardinal>;
      J: Integer;
    begin
      if MeshName = '' then
        if aItem.Store is TvgSTLObjectStore then MeshName := TvgSTLObjectStore(aItem.Store).SolidName
        else if aItem.Store is TvgOBJObjectStore then MeshName := TvgOBJObjectStore(aItem.Store).ObjectName;
      Tris := vgTriangleIndices(aItem.Mesh.Topology, aItem.Mesh.Indices, True);
      if Length(Tris) = 0 then Exit;
      if NP + Length(Tris) > Length(Positions) then
        SetLength(Positions, 2 * Length(Positions) + Length(Tris));
      for J := 0 to High(Tris) do
        Positions[NP + J] := vgSTLVector(aItem.World[Tris[J]].x, aItem.World[Tris[J]].y,
          aItem.World[Tris[J]].z);
      Inc(NP, Length(Tris));
    end,
    vgTriangleTopologies);
  Result.Name := MeshName;
  Result.Allocate(NP div 3);
  if NP > 0 then Move(Positions[0], Result.Positions[0], NP * SizeOf(TvgSTLVector));
  for I := 0 to Result.TriangleCount - 1 do
    Result.FaceNormals[I] := vgSTLTriangleNormal(Result.Positions[3 * I],
      Result.Positions[3 * I + 1], Result.Positions[3 * I + 2]);
end;

procedure TvgSceneLoaderStorer_STL.StoreScene;
var Mesh: TvgSTLMesh;
begin
  ClearWarnings;
  if Trim(fFileName) = '' then raise EvgSTLError.Create('STL storer requires a FileName');
  Mesh := SceneMesh;
  if Mesh.TriangleCount = 0 then raise EvgSTLError.Create('The scene has no triangles to store as STL');
  if Mesh.Name = '' then Mesh.Name := ChangeFileExt(ExtractFileName(fFileName), '');
  if fAscii then vgWriteSTL(Mesh, ExpandFileName(fFileName), sfAscii)
  else vgWriteSTL(Mesh, ExpandFileName(fFileName), sfBinary);
end;

initialization
  RegisterSceneLoader(TvgSceneLoaderStorer_STL, 'STL', 'STL triangle mesh (binary or ASCII)', '.stl', 'FileName');
  RegisterClass(TvgSceneLoaderStorer_STL);
finalization
  UnregisterClass(TvgSceneLoaderStorer_STL);
  UnregisterSceneLoader(TvgSceneLoaderStorer_STL);
end.
