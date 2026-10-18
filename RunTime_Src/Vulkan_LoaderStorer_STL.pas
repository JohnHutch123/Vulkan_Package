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
  Vulkan_MeshUtils,
  Vulkan_LOD;

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
  Pos, Nrm, UV: TArray<TpvVector3>;
  Idx: TArray<Integer>;
  Tan, Bit: TArray<TpvVector3D>;
  Obj: TvgObject;
  K, T: Integer;
  P, N: TvgSTLVector;
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
    Result.SetupVertexAttributes([vdtPosition, vdtColor, vdtNormal, vdtTexCoord,
                                  vdtTangent, vdtBiTangent]);
    Result.SetupInstanceAttributes([idtObjID]);
    Result.SetIndexType(itUInt32);
    Result.Topology := TRIANGLE_LIST;
    Result.PrebuiltShaderVariants := True;
    Result.BaseVertName := 'OBJ';
    Result.BaseFragName := 'OBJ';
    if aWeld then Result.Shading := osSmooth else Result.Shading := osFlat;
    Obj := Result.AddObject(True); Obj.AddObjectID;
    if Mesh.TriangleCount = 0 then Exit;

    Result.AllocateVertices(0, Length(Mesh.Positions));
    Result.AllocateIndices(0, Length(Mesh.Indices), amUninitialized);
    SetLength(Pos, Length(Mesh.Positions)); SetLength(Nrm, Length(Mesh.Positions));
    SetLength(UV, Length(Mesh.Positions));
    for K := 0 to High(Mesh.Positions) do
    begin
      P := Mesh.Positions[K]; N := Normals[K];
      Pos[K] := TpvVector3.Create(P.X, P.Y, P.Z);
      Nrm[K] := TpvVector3.Create(N.X, N.Y, N.Z);
      UV[K] := TpvVector3.Create(0, 0, 0);
      Result.SetObjectVertexPosition(0, K, P.X, P.Y, P.Z);
      Result.SetObjectVertexColor(0, K, aColor.x, aColor.y, aColor.z, aColor.w);
      Result.SetObjectVertexNormal(0, K, N.X, N.Y, N.Z);
      Result.SetObjectVertexTexCoord(0, K, 0, 0);
    end;
    SetLength(Idx, Length(Mesh.Indices));
    for K := 0 to High(Mesh.Indices) do
    begin
      Result.SetObjectIndex(0, K, Mesh.Indices[K]);
      Idx[K] := Mesh.Indices[K];
    end;
    // STL has no texture coordinates: vgBuildTangents gives a frame about
    // each normal, which the OBJ shaders' vertex layout needs.
    vgBuildTangents(Pos, Nrm, UV, Idx, True, Tan, Bit);
    for K := 0 to High(Tan) do
    begin
      Result.SetObjectVertexTangent(0, K, Tan[K].x, Tan[K].y, Tan[K].z);
      Result.SetObjectVertexBiTangent(0, K, Bit[K].x, Bit[K].y, Bit[K].z);
    end;
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
  Store: TvgObjectStore;
  Obj: TvgObject;
  I, J, NT, Count: Integer;
  Local: TArray<TpvVector3>;
  World: TArray<TvgSTLVector>;
  Indices: TArray<Cardinal>;
  W: TpvVector3D;
  Tris: TArray<Cardinal>; // object-relative corners, three per triangle
  Positions: TArray<TvgSTLVector>;
  NP: Integer;

  procedure AddTri(A, B, C: Cardinal);
  begin
    if (A = B) or (B = C) or (A = C) then Exit; // strip padding
    if NT + 3 > Length(Tris) then SetLength(Tris, 2 * Length(Tris) + 48);
    Tris[NT] := A; Tris[NT + 1] := B; Tris[NT + 2] := C; Inc(NT, 3);
  end;

begin
  Result.Clear;
  if not Assigned(fScene) then raise EvgSTLError.Create('STL storer requires a Scene');
  NP := 0;
  Positions := nil;
  if fScene.SceneData <> nil then
    for Store in fScene.SceneData do
    begin
      if Store = fScene.PreviewStore then Continue;
      if not (Store.Topology in [TRIANGLE_LIST, TRIANGLE_STRIP, TRIANGLE_FAN]) then Continue;
      if Result.Name = '' then
        if Store is TvgSTLObjectStore then Result.Name := TvgSTLObjectStore(Store).SolidName
        else if Store is TvgOBJObjectStore then Result.Name := TvgOBJObjectStore(Store).ObjectName;
      for I := 0 to Store.GetObjectCount - 1 do
      begin
        Obj := Store.GetObjectItem(I);
        if (Obj = nil) or vgIsLodProxy(Obj) or not Obj.VisibleON then Continue;
        Local := Store.GetObjectVertexPositions(Obj.ObjIndex);
        if Length(Local) = 0 then Continue;
        if (Store.GetIndexType <> itNONE) and (Store.GetObjectIndexCount(Obj.ObjIndex) > 0) then
          Indices := Store.GetObjectIndices(Obj.ObjIndex)
        else
        begin
          // Drawn without indices: the vertices in order.
          SetLength(Indices, Length(Local));
          for J := 0 to High(Local) do Indices[J] := J;
        end;
        Count := Length(Indices);
        NT := 0; Tris := nil;
        case Store.Topology of
          TRIANGLE_LIST:
            for J := 0 to Count div 3 - 1 do
              AddTri(Indices[3 * J], Indices[3 * J + 1], Indices[3 * J + 2]);
          TRIANGLE_STRIP:
            for J := 0 to Count - 3 do
              if Odd(J) then AddTri(Indices[J + 1], Indices[J], Indices[J + 2])
              else AddTri(Indices[J], Indices[J + 1], Indices[J + 2]);
          TRIANGLE_FAN:
            for J := 1 to Count - 2 do AddTri(Indices[0], Indices[J], Indices[J + 1]);
        end;
        if NT = 0 then Continue;
        SetLength(World, Length(Local));
        for J := 0 to High(Local) do
        begin
          W := fScene.LocalToWorld(TpvVector3D.Create(Local[J].x, Local[J].y, Local[J].z));
          World[J] := vgSTLVector(W.x, W.y, W.z);
        end;
        if NP + NT > Length(Positions) then SetLength(Positions, 2 * Length(Positions) + NT);
        for J := 0 to NT - 1 do
        begin
          if Tris[J] >= Cardinal(Length(World)) then
            raise EvgSTLError.Create('Scene index out of range of its object''s vertices');
          Positions[NP + J] := World[Tris[J]];
        end;
        Inc(NP, NT);
      end;
    end;
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
