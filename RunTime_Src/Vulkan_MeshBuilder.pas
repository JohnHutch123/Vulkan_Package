unit Vulkan_MeshBuilder;

{ Shared mesh plumbing for scene loaders and storers.  Public Vulkan
  Package, zlib licence.

  Loading: a reader fills a TvgMeshData (positions, and normals, colours,
  texture coordinates and indices where the file has them) and hands it to
  vgWriteMesh, which writes it into a store in bulk and builds the tangent
  frames.  vgSetupShadedStore gives a store the vertex layout and prebuilt
  OBJ shaders most loaders draw with.

  Storing: vgForEachSceneMesh walks every exportable object of a scene and
  hands each one over as a TvgMeshData in the store's own coordinates plus
  its positions in world coordinates.  vgTriangleIndices and
  vgLineIndices turn strips and fans into plain lists for formats that
  have only those. }

interface

uses
  System.SysUtils, System.Classes, System.Math,
  PasVulkan.Math, PasVulkan.Math.Double,
  Vulkan_Components, Vulkan_Components_Lookups, Vulkan_Components_DataStore,
  Vulkan_Components_Scene_Renderer, Vulkan_MeshUtils, Vulkan_LOD;

type
  EvgMeshError = class(Exception);

  TvgPrimitiveTopologies = set of TvgPrimitiveTopology;

  { One object's geometry.  Positions are required.  Normals, Colors and
    TexCoords are optional: empty, or one per position.  Indices are
    optional too: empty means the vertices in order. }
  TvgMeshData = record
    Name      : string;
    Topology  : TvgPrimitiveTopology;
    Positions : TArray<TpvVector3>;
    Normals   : TArray<TpvVector3>;
    Colors    : TArray<TpvVector4>;
    TexCoords : TArray<TpvVector2>;
    Indices   : TArray<Cardinal>;
    procedure Clear;
    function VertexCount: Integer;
    // Indices, or 0..VertexCount-1 when there are none.
    function IndicesOrOrder: TArray<Cardinal>;
  end;

  // One object handed over by vgForEachSceneMesh.
  TvgSceneMesh = record
    Store : TvgObjectStore;
    Obj   : TvgObject;
    // In the store's own coordinates, as stored; Indices always filled.
    Mesh  : TvgMeshData;
    // Mesh.Positions in world coordinates (TvgScene.LocalToWorld).
    World : TArray<TpvVector3D>;
  end;

  TvgSceneMeshProc = reference to procedure(const aItem: TvgSceneMesh);

  TvgSceneMeshOption = (
    smoIncludeHidden,       // objects with VisibleON False too
    smoIncludeLodProxies    // the coarser level-of-detail copies too
  );
  TvgSceneMeshOptions = set of TvgSceneMeshOption;

const
  vgAllTopologies = [Low(TvgPrimitiveTopology)..High(TvgPrimitiveTopology)];
  vgTriangleTopologies = [TRIANGLE_LIST, TRIANGLE_STRIP, TRIANGLE_FAN];
  vgLineTopologies = [LINE_LIST, LINE_STRIP];

{ Gives aStore the layout most loaders use - position, colour, normal,
  texture coordinate, tangent and bitangent; an object ID per instance;
  32-bit indices - drawn with the prebuilt OBJ shaders (OBJTexture when
  aTextured).  Adds its first object, with an object ID, and returns it. }
function vgSetupShadedStore(aStore: TvgObjectStore; aTopology: TvgPrimitiveTopology;
  aTextured: Boolean = False): TvgObject;

{ Writes aMesh into object aObjIndex of aStore, replacing its vertices and
  indices.  Only the attributes the store has are written.  Missing
  normals are made smooth (area-weighted) for triangles and (0,0,1) for
  lines and points; missing colours are aColor; missing texture
  coordinates are 0.  Tangents and bitangents, where the store has them,
  are built with vgBuildTangents. }
procedure vgWriteMesh(aStore: TvgObjectStore; aObjIndex: Integer;
  const aMesh: TvgMeshData; const aColor: TpvVector4);

// Area-weighted vertex normals of a mesh's triangles; (0,0,1) where none.
function vgMeshNormals(const aMesh: TvgMeshData): TArray<TpvVector3>;

{ Reads object aObj back as a TvgMeshData (store coordinates), Indices
  always filled.  False if it has no positions. }
function vgReadMesh(aObj: TvgObject; out aMesh: TvgMeshData): Boolean;

{ Every object of aScene whose store's topology is in aTopologies, skipping
  the preview store, deleted objects and empty ones, and - unless aOptions
  says otherwise - hidden objects and level-of-detail copies. }
procedure vgForEachSceneMesh(aScene: TvgScene; const aProc: TvgSceneMeshProc;
  aTopologies: TvgPrimitiveTopologies = vgAllTopologies;
  aOptions: TvgSceneMeshOptions = []);

{ Three indices per triangle from a triangle list, strip or fan (strip
  winding kept); empty for other topologies.  aDropDegenerate leaves out
  triangles with a repeated corner, such as strip padding. }
function vgTriangleIndices(aTopology: TvgPrimitiveTopology;
  const aIndices: TArray<Cardinal>; aDropDegenerate: Boolean = False): TArray<Cardinal>;

// Two indices per segment from a line list or strip; empty for others.
function vgLineIndices(aTopology: TvgPrimitiveTopology;
  const aIndices: TArray<Cardinal>): TArray<Cardinal>;

implementation

{ TvgMeshData }

procedure TvgMeshData.Clear;
begin
  Name := '';
  Topology := TRIANGLE_LIST;
  Positions := nil;
  Normals := nil;
  Colors := nil;
  TexCoords := nil;
  Indices := nil;
end;

function TvgMeshData.VertexCount: Integer;
begin
  Result := Length(Positions);
end;

function TvgMeshData.IndicesOrOrder: TArray<Cardinal>;
var
  I: Integer;
begin
  if Length(Indices) > 0 then
    Exit(Indices);
  SetLength(Result, Length(Positions));
  for I := 0 to High(Result) do
    Result[I] := I;
end;

{ Topology }

function vgTriangleIndices(aTopology: TvgPrimitiveTopology;
  const aIndices: TArray<Cardinal>; aDropDegenerate: Boolean): TArray<Cardinal>;
var
  N, Count, J: Integer;
  T: TArray<Cardinal>;

  procedure Add(A, B, C: Cardinal);
  begin
    if aDropDegenerate and ((A = B) or (B = C) or (A = C)) then Exit;
    T[N] := A; T[N + 1] := B; T[N + 2] := C;
    Inc(N, 3);
  end;

begin
  T := nil;
  Count := Length(aIndices);
  N := 0;
  case aTopology of
    TRIANGLE_LIST:
      begin
        SetLength(T, (Count div 3) * 3);
        for J := 0 to Count div 3 - 1 do
          Add(aIndices[3 * J], aIndices[3 * J + 1], aIndices[3 * J + 2]);
      end;
    TRIANGLE_STRIP:
      if Count >= 3 then
      begin
        SetLength(T, (Count - 2) * 3);
        for J := 0 to Count - 3 do
          if Odd(J) then Add(aIndices[J + 1], aIndices[J], aIndices[J + 2])
          else Add(aIndices[J], aIndices[J + 1], aIndices[J + 2]);
      end;
    TRIANGLE_FAN:
      if Count >= 3 then
      begin
        SetLength(T, (Count - 2) * 3);
        for J := 1 to Count - 2 do
          Add(aIndices[0], aIndices[J], aIndices[J + 1]);
      end;
  end;
  SetLength(T, N);
  Result := T;
end;

function vgLineIndices(aTopology: TvgPrimitiveTopology;
  const aIndices: TArray<Cardinal>): TArray<Cardinal>;
var
  Count, J: Integer;
begin
  Result := nil;
  Count := Length(aIndices);
  case aTopology of
    LINE_LIST:
      begin
        SetLength(Result, (Count div 2) * 2);
        if Length(Result) > 0 then
          Move(aIndices[0], Result[0], Length(Result) * SizeOf(Cardinal));
      end;
    LINE_STRIP:
      if Count >= 2 then
      begin
        SetLength(Result, (Count - 1) * 2);
        for J := 0 to Count - 2 do
        begin
          Result[2 * J] := aIndices[J];
          Result[2 * J + 1] := aIndices[J + 1];
        end;
      end;
  end;
end;

{ Writing }

function vgSetupShadedStore(aStore: TvgObjectStore; aTopology: TvgPrimitiveTopology;
  aTextured: Boolean): TvgObject;
begin
  aStore.SetupVertexAttributes([vdtPosition, vdtColor, vdtNormal, vdtTexCoord,
                                vdtTangent, vdtBiTangent]);
  aStore.SetupInstanceAttributes([idtObjID]);
  aStore.SetIndexType(itUInt32);
  aStore.Topology := aTopology;
  aStore.PrebuiltShaderVariants := True;
  aStore.BaseVertName := 'OBJ';
  if aTextured then
    aStore.BaseFragName := 'OBJTexture'
  else
    aStore.BaseFragName := 'OBJ';
  Result := aStore.AddObject(True);
  Result.AddObjectID;
end;

function vgMeshNormals(const aMesh: TvgMeshData): TArray<TpvVector3>;
var
  Sum: TArray<TpvVector3D>;
  Tris: TArray<Cardinal>;
  I, K: Integer;
  A, B, C: TpvVector3;
  N: TpvVector3D;
  L: Double;
begin
  SetLength(Result, Length(aMesh.Positions));
  SetLength(Sum, Length(aMesh.Positions));
  for I := 0 to High(Sum) do
    Sum[I] := TpvVector3D.Create(0, 0, 0);

  Tris := vgTriangleIndices(aMesh.Topology, aMesh.IndicesOrOrder, True);
  for I := 0 to Length(Tris) div 3 - 1 do
  begin
    if (Tris[3 * I] >= Cardinal(Length(Sum))) or (Tris[3 * I + 1] >= Cardinal(Length(Sum))) or
       (Tris[3 * I + 2] >= Cardinal(Length(Sum))) then
      raise EvgMeshError.Create('Mesh index out of range of its vertices');
    A := aMesh.Positions[Tris[3 * I]];
    B := aMesh.Positions[Tris[3 * I + 1]];
    C := aMesh.Positions[Tris[3 * I + 2]];
    // Unnormalised: its length is twice the triangle's area, so larger
    // triangles count for more.
    N := TpvVector3D.Create(
      (Double(B.y) - A.y) * (Double(C.z) - A.z) - (Double(B.z) - A.z) * (Double(C.y) - A.y),
      (Double(B.z) - A.z) * (Double(C.x) - A.x) - (Double(B.x) - A.x) * (Double(C.z) - A.z),
      (Double(B.x) - A.x) * (Double(C.y) - A.y) - (Double(B.y) - A.y) * (Double(C.x) - A.x));
    for K := 0 to 2 do
      Sum[Tris[3 * I + K]] := TpvVector3D.Create(Sum[Tris[3 * I + K]].x + N.x,
        Sum[Tris[3 * I + K]].y + N.y, Sum[Tris[3 * I + K]].z + N.z);
  end;

  for I := 0 to High(Result) do
  begin
    L := Sqrt(Sqr(Sum[I].x) + Sqr(Sum[I].y) + Sqr(Sum[I].z));
    if L > 0 then
      Result[I] := TpvVector3.Create(Sum[I].x / L, Sum[I].y / L, Sum[I].z / L)
    else
      Result[I] := TpvVector3.Create(0, 0, 1);
  end;
end;

procedure vgWriteMesh(aStore: TvgObjectStore; aObjIndex: Integer;
  const aMesh: TvgMeshData; const aColor: TpvVector4);
var
  N, I: Integer;
  Buf: TArray<Single>;
  Nrm, UV3: TArray<TpvVector3>;
  Idx, Tris: TArray<Cardinal>;
  TanIdx: TArray<Integer>;
  Tan, Bit: TArray<TpvVector3D>;
begin
  N := Length(aMesh.Positions);
  if (Length(aMesh.Normals) <> 0) and (Length(aMesh.Normals) <> N) then
    raise EvgMeshError.Create('A mesh needs one normal per position, or none');
  if (Length(aMesh.Colors) <> 0) and (Length(aMesh.Colors) <> N) then
    raise EvgMeshError.Create('A mesh needs one colour per position, or none');
  if (Length(aMesh.TexCoords) <> 0) and (Length(aMesh.TexCoords) <> N) then
    raise EvgMeshError.Create('A mesh needs one texture coordinate per position, or none');
  for I := 0 to High(aMesh.Indices) do
    if aMesh.Indices[I] >= Cardinal(N) then
      raise EvgMeshError.CreateFmt('Mesh index %d is out of range (%d vertices)', [aMesh.Indices[I], N]);

  aStore.AllocateVertices(aObjIndex, N);
  if aStore.GetIndexType <> itNONE then
  begin
    aStore.AllocateIndices(aObjIndex, Length(aMesh.Indices), amUninitialized);
    aStore.SetObjectIndices(aObjIndex, 0, aMesh.Indices);
  end
  else if Length(aMesh.Indices) > 0 then
    raise EvgMeshError.Create('The store has no index buffer for the mesh''s indices');
  if N = 0 then Exit;

  if aStore.IsVertexTypeSet(vdtPosition) then
  begin
    SetLength(Buf, N * 3);
    for I := 0 to N - 1 do
    begin
      Buf[3 * I] := aMesh.Positions[I].x;
      Buf[3 * I + 1] := aMesh.Positions[I].y;
      Buf[3 * I + 2] := aMesh.Positions[I].z;
    end;
    aStore.SetObjectVertexPositions(aObjIndex, 0, Buf);
  end;

  if Length(aMesh.Normals) = N then
    Nrm := aMesh.Normals
  else if aStore.IsVertexTypeSet(vdtNormal) or aStore.IsVertexTypeSet(vdtTangent) or
          aStore.IsVertexTypeSet(vdtBiTangent) then
    Nrm := vgMeshNormals(aMesh);

  if aStore.IsVertexTypeSet(vdtNormal) then
  begin
    SetLength(Buf, N * 3);
    for I := 0 to N - 1 do
    begin
      Buf[3 * I] := Nrm[I].x;
      Buf[3 * I + 1] := Nrm[I].y;
      Buf[3 * I + 2] := Nrm[I].z;
    end;
    aStore.SetObjectVertexNormals(aObjIndex, 0, Buf);
  end;

  if aStore.IsVertexTypeSet(vdtColor) then
  begin
    SetLength(Buf, N * 4);
    for I := 0 to N - 1 do
      if Length(aMesh.Colors) = N then
      begin
        Buf[4 * I] := aMesh.Colors[I].x;
        Buf[4 * I + 1] := aMesh.Colors[I].y;
        Buf[4 * I + 2] := aMesh.Colors[I].z;
        Buf[4 * I + 3] := aMesh.Colors[I].w;
      end
      else
      begin
        Buf[4 * I] := aColor.x;
        Buf[4 * I + 1] := aColor.y;
        Buf[4 * I + 2] := aColor.z;
        Buf[4 * I + 3] := aColor.w;
      end;
    aStore.SetObjectVertexColors(aObjIndex, 0, Buf);
  end;

  if aStore.IsVertexTypeSet(vdtTexCoord) then
  begin
    SetLength(Buf, N * 2);
    for I := 0 to N - 1 do
      if Length(aMesh.TexCoords) = N then
      begin
        Buf[2 * I] := aMesh.TexCoords[I].x;
        Buf[2 * I + 1] := aMesh.TexCoords[I].y;
      end
      else
      begin
        Buf[2 * I] := 0;
        Buf[2 * I + 1] := 0;
      end;
    aStore.SetObjectVertexTexCoords(aObjIndex, 0, Buf);
  end;

  if aStore.IsVertexTypeSet(vdtTangent) or aStore.IsVertexTypeSet(vdtBiTangent) then
  begin
    SetLength(UV3, N);
    for I := 0 to N - 1 do
      if Length(aMesh.TexCoords) = N then
        UV3[I] := TpvVector3.Create(aMesh.TexCoords[I].x, aMesh.TexCoords[I].y, 0)
      else
        UV3[I] := TpvVector3.Create(0, 0, 0);
    Idx := aMesh.IndicesOrOrder;
    Tris := vgTriangleIndices(aMesh.Topology, Idx);
    if Length(Tris) > 0 then
    begin
      SetLength(TanIdx, Length(Tris));
      for I := 0 to High(Tris) do TanIdx[I] := Tris[I];
    end
    else
    begin
      SetLength(TanIdx, Length(Idx));
      for I := 0 to High(Idx) do TanIdx[I] := Idx[I];
    end;
    vgBuildTangents(aMesh.Positions, Nrm, UV3, TanIdx, Length(Tris) > 0, Tan, Bit);

    SetLength(Buf, N * 3);
    if aStore.IsVertexTypeSet(vdtTangent) then
    begin
      for I := 0 to N - 1 do
      begin
        Buf[3 * I] := Tan[I].x;
        Buf[3 * I + 1] := Tan[I].y;
        Buf[3 * I + 2] := Tan[I].z;
      end;
      aStore.SetObjectVertexTangents(aObjIndex, 0, Buf);
    end;
    if aStore.IsVertexTypeSet(vdtBiTangent) then
    begin
      for I := 0 to N - 1 do
      begin
        Buf[3 * I] := Bit[I].x;
        Buf[3 * I + 1] := Bit[I].y;
        Buf[3 * I + 2] := Bit[I].z;
      end;
      aStore.SetObjectVertexBiTangents(aObjIndex, 0, Buf);
    end;
  end;
end;

{ Reading }

function vgReadMesh(aObj: TvgObject; out aMesh: TvgMeshData): Boolean;
var
  Store: TvgObjectStore;
  Buf: TArray<Single>;
  N, I: Integer;
begin
  aMesh.Clear;
  Result := False;
  if not Assigned(aObj) or not Assigned(aObj.DataStore) then Exit;
  Store := aObj.DataStore;
  aMesh.Topology := Store.Topology;
  aMesh.Positions := Store.GetObjectVertexPositions(aObj.ObjIndex);
  N := Length(aMesh.Positions);
  if N = 0 then Exit;

  Buf := Store.GetObjectVertexAttribute(aObj.ObjIndex, vdtNormal);
  if Length(Buf) = N * 3 then
  begin
    SetLength(aMesh.Normals, N);
    for I := 0 to N - 1 do
      aMesh.Normals[I] := TpvVector3.Create(Buf[3 * I], Buf[3 * I + 1], Buf[3 * I + 2]);
  end;
  Buf := Store.GetObjectVertexAttribute(aObj.ObjIndex, vdtColor);
  if Length(Buf) = N * 4 then
  begin
    SetLength(aMesh.Colors, N);
    for I := 0 to N - 1 do
      aMesh.Colors[I] := TpvVector4.Create(Buf[4 * I], Buf[4 * I + 1], Buf[4 * I + 2], Buf[4 * I + 3]);
  end;
  Buf := Store.GetObjectVertexAttribute(aObj.ObjIndex, vdtTexCoord);
  if Length(Buf) = N * 2 then
  begin
    SetLength(aMesh.TexCoords, N);
    for I := 0 to N - 1 do
      aMesh.TexCoords[I] := TpvVector2.Create(Buf[2 * I], Buf[2 * I + 1]);
  end;

  if (Store.GetIndexType <> itNONE) and (Store.GetObjectIndexCount(aObj.ObjIndex) > 0) then
    aMesh.Indices := Store.GetObjectIndices(aObj.ObjIndex)
  else
    aMesh.Indices := aMesh.IndicesOrOrder;
  for I := 0 to High(aMesh.Indices) do
    if aMesh.Indices[I] >= Cardinal(N) then
      raise EvgMeshError.Create('Scene index out of range of its object''s vertices');
  Result := True;
end;

procedure vgForEachSceneMesh(aScene: TvgScene; const aProc: TvgSceneMeshProc;
  aTopologies: TvgPrimitiveTopologies; aOptions: TvgSceneMeshOptions);
var
  Store: TvgObjectStore;
  Item: TvgSceneMesh;
  I, J: Integer;
  P: TpvVector3;
begin
  if not Assigned(aScene) or not Assigned(aScene.SceneData) then Exit;
  for Store in aScene.SceneData do
  begin
    if Store = aScene.PreviewStore then Continue;
    if not (Store.Topology in aTopologies) then Continue;
    for I := 0 to Store.GetObjectCount - 1 do
    begin
      Item.Obj := Store.GetObjectItem(I);
      if not Assigned(Item.Obj) then Continue;
      if not (smoIncludeLodProxies in aOptions) and vgIsLodProxy(Item.Obj) then Continue;
      if not (smoIncludeHidden in aOptions) and not Item.Obj.VisibleON then Continue;
      if not vgReadMesh(Item.Obj, Item.Mesh) then Continue;
      Item.Store := Store;
      SetLength(Item.World, Length(Item.Mesh.Positions));
      for J := 0 to High(Item.World) do
      begin
        P := Item.Mesh.Positions[J];
        Item.World[J] := aScene.LocalToWorld(TpvVector3D.Create(P.x, P.y, P.z));
      end;
      aProc(Item);
    end;
  end;
end;

end.
