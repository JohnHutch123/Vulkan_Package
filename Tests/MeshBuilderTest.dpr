program MeshBuilderTest;

{ Vulkan_MeshBuilder: topology expansion, writing a TvgMeshData into a
  store and reading it back, and walking a scene.  No device needed. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.Math,
  PasVulkan.Math, PasVulkan.Math.Double,
  Vulkan_Components, Vulkan_Components_Lookups, Vulkan_Components_DataStore,
  Vulkan_Components_Scene_Renderer, Vulkan_MeshBuilder;

var
  Failures: Integer = 0;

procedure Check(const Name: string; OK: Boolean);
begin
  if OK then Writeln('  ok   ', Name)
  else begin Writeln('  FAIL ', Name); Inc(Failures); end;
end;

function Near(A, B: Double; Tol: Double = 1e-5): Boolean;
begin
  Result := Abs(A - B) <= Tol;
end;

function SameIndices(const A: TArray<Cardinal>; const B: array of Cardinal): Boolean;
var I: Integer;
begin
  Result := Length(A) = Length(B);
  if Result then
    for I := 0 to High(A) do
      if A[I] <> B[I] then Exit(False);
end;

function Idx(const A: array of Cardinal): TArray<Cardinal>;
var I: Integer;
begin
  SetLength(Result, Length(A));
  for I := 0 to High(A) do Result[I] := A[I];
end;

// A unit square in the XY plane, two triangles.
function Quad: TvgMeshData;
begin
  Result.Clear;
  Result.Topology := TRIANGLE_LIST;
  Result.Positions := [TpvVector3.Create(0, 0, 0), TpvVector3.Create(1, 0, 0),
                       TpvVector3.Create(1, 1, 0), TpvVector3.Create(0, 1, 0)];
  Result.Indices := Idx([0, 1, 2, 0, 2, 3]);
end;

procedure TestTopology;
begin
  Writeln('Topology');
  Check('list stays', SameIndices(vgTriangleIndices(TRIANGLE_LIST, Idx([0, 1, 2, 3, 4, 5])),
    [0, 1, 2, 3, 4, 5]));
  Check('list drops a partial triangle', SameIndices(vgTriangleIndices(TRIANGLE_LIST, Idx([0, 1, 2, 3])),
    [0, 1, 2]));
  Check('strip keeps winding', SameIndices(vgTriangleIndices(TRIANGLE_STRIP, Idx([0, 1, 2, 3])),
    [0, 1, 2, 2, 1, 3]));
  Check('fan', SameIndices(vgTriangleIndices(TRIANGLE_FAN, Idx([0, 1, 2, 3])),
    [0, 1, 2, 0, 2, 3]));
  Check('degenerate kept by default', Length(vgTriangleIndices(TRIANGLE_STRIP, Idx([0, 1, 1, 2]))) = 6);
  Check('degenerate dropped on request', SameIndices(
    vgTriangleIndices(TRIANGLE_STRIP, Idx([0, 1, 2, 2, 3, 4]), True), [0, 1, 2, 3, 2, 4]));
  Check('lines are not triangles', Length(vgTriangleIndices(LINE_LIST, Idx([0, 1]))) = 0);
  Check('line strip to segments', SameIndices(vgLineIndices(LINE_STRIP, Idx([0, 1, 2])), [0, 1, 1, 2]));
  Check('line list stays', SameIndices(vgLineIndices(LINE_LIST, Idx([0, 1, 2, 3])), [0, 1, 2, 3]));
end;

procedure TestWriteRead;
var
  Store: TvgObjectStore;
  M, R: TvgMeshData;
  Obj: TvgObject;
  Raised: Boolean;
begin
  Writeln('Write and read');
  Store := TvgObjectStore.Create(nil);
  try
    Obj := vgSetupShadedStore(Store, TRIANGLE_LIST);
    Check('shaded store layout', Store.IsVertexTypeSet(vdtTangent) and (Store.GetIndexType = itUInt32));
    M := Quad;
    vgWriteMesh(Store, Obj.ObjIndex, M, TpvVector4.Create(0.5, 0.25, 1, 1));
    Check('reads back', vgReadMesh(Obj, R));
    Check('4 vertices', R.VertexCount = 4);
    Check('positions', Near(R.Positions[2].x, 1) and Near(R.Positions[2].y, 1));
    Check('indices', SameIndices(R.Indices, [0, 1, 2, 0, 2, 3]));
    Check('missing normals are made', (Length(R.Normals) = 4) and Near(R.Normals[0].z, 1));
    Check('missing colours are the default', (Length(R.Colors) = 4) and Near(R.Colors[3].y, 0.25));
    Check('missing UVs are zero', (Length(R.TexCoords) = 4) and Near(R.TexCoords[1].x, 0));

    M.Colors := [TpvVector4.Create(1, 0, 0, 1), TpvVector4.Create(0, 1, 0, 1),
                 TpvVector4.Create(0, 0, 1, 1), TpvVector4.Create(1, 1, 1, 0.5)];
    M.TexCoords := [TpvVector2.Create(0, 0), TpvVector2.Create(1, 0),
                    TpvVector2.Create(1, 1), TpvVector2.Create(0, 1)];
    vgWriteMesh(Store, Obj.ObjIndex, M, TpvVector4.Create(0, 0, 0, 1));
    vgReadMesh(Obj, R);
    Check('given colours kept', Near(R.Colors[1].y, 1) and Near(R.Colors[3].w, 0.5));
    Check('given UVs kept', Near(R.TexCoords[2].x, 1) and Near(R.TexCoords[2].y, 1));

    M.Indices := Idx([0, 1, 7]);
    Raised := False;
    try vgWriteMesh(Store, Obj.ObjIndex, M, TpvVector4.Create(0, 0, 0, 1));
    except on EvgMeshError do Raised := True; end;
    Check('index out of range raises', Raised);

    M := Quad;
    SetLength(M.Normals, 2);
    Raised := False;
    try vgWriteMesh(Store, Obj.ObjIndex, M, TpvVector4.Create(0, 0, 0, 1));
    except on EvgMeshError do Raised := True; end;
    Check('wrong normal count raises', Raised);
  finally
    Store.Free;
  end;
end;

procedure TestSceneWalk;
var
  Scene: TvgScene;
  Store, Lines: TvgObjectStore;
  Obj, Hidden: TvgObject;
  M: TvgMeshData;
  Count, Verts: Integer;
begin
  Writeln('Scene walk');
  Scene := TvgScene.Create(nil);
  try
    Store := TvgObjectStore.Create(nil);
    Obj := vgSetupShadedStore(Store, TRIANGLE_LIST);
    vgWriteMesh(Store, Obj.ObjIndex, Quad, TpvVector4.Create(1, 1, 1, 1));
    Hidden := Store.AddObject(True);
    vgWriteMesh(Store, Hidden.ObjIndex, Quad, TpvVector4.Create(1, 1, 1, 1));
    Hidden.VisibleON := False;

    Lines := TvgObjectStore.Create(nil);
    Obj := vgSetupShadedStore(Lines, LINE_LIST);
    M.Clear;
    M.Topology := LINE_LIST;
    M.Positions := [TpvVector3.Create(0, 0, 0), TpvVector3.Create(2, 0, 0)];
    vgWriteMesh(Lines, Obj.ObjIndex, M, TpvVector4.Create(1, 1, 1, 1));

    Check('scene accepts the stores', Scene.Load_Begin);
    try
      Scene.AddDataStore(Store);
      Scene.AddDataStore(Lines);
    finally
      Scene.Load_End;
    end;

    Count := 0; Verts := 0;
    vgForEachSceneMesh(Scene,
      procedure(const aItem: TvgSceneMesh)
      begin
        Inc(Count);
        Inc(Verts, Length(aItem.World));
      end);
    Check('hidden object skipped', Count = 2);
    Check('world positions for each vertex', Verts = 6);

    Count := 0;
    vgForEachSceneMesh(Scene,
      procedure(const aItem: TvgSceneMesh)
      begin
        Inc(Count);
      end, vgTriangleTopologies);
    Check('topology filter', Count = 1);

    Count := 0;
    vgForEachSceneMesh(Scene,
      procedure(const aItem: TvgSceneMesh)
      begin
        Inc(Count);
      end, vgAllTopologies, [smoIncludeHidden]);
    Check('hidden included on request', Count = 3);
  finally
    Scene.Free;
  end;
end;

begin
  try
    TestTopology;
    TestWriteRead;
    TestSceneWalk;
    if Failures = 0 then
      Writeln('ALL CHECKS PASSED')
    else
    begin
      Writeln(Format('%d CHECK(S) FAILED', [Failures]));
      ExitCode := 1;
    end;
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION: ', E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
