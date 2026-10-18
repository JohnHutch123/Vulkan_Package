program STLTest;

{ Vulkan_STL (the file format, no Vulkan) and, under Delphi,
  Vulkan_LoaderStorer_STL (scene load and store, no device).
  The first half also builds with Free Pascal:
    fpc -Mdelphi -Fu../RunTime_Src STLTest.dpr }

{$APPTYPE CONSOLE}
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

uses
{$IFDEF FPC}
  SysUtils, Classes, Math,
{$ELSE}
  System.SysUtils, System.Classes, System.Math, System.IOUtils,
  PasVulkan.Math, PasVulkan.Math.Double, Vulkan_Components_Lookups,
  Vulkan_Components_Scene_Renderer, Vulkan_SceneLoaders, Vulkan_Loader_OBJ,
  Vulkan_LoaderStorer_STL,
{$ENDIF}
  Vulkan_STL;

var
  Failures: Integer = 0;
  TempDir: string;

procedure Check(const Name: string; OK: Boolean);
begin
  if OK then Writeln('  ok   ', Name)
  else begin Writeln('  FAIL ', Name); Inc(Failures); end;
end;

function Near(A, B: Double; Tol: Double = 1e-5): Boolean;
begin
  Result := Abs(A - B) <= Tol;
end;

function V(X, Y, Z: Single): TvgSTLVector;
begin
  Result := vgSTLVector(X, Y, Z);
end;

{ A 2 x 3 x 4 box with one corner at (1, 2, 3), triangles facing out. }
function Box: TvgSTLMesh;
var C: array[0..7] of TvgSTLVector; T: Integer;
const
  F: array[0..11, 0..2] of Integer = (
    (0, 2, 1), (0, 3, 2),   // z = 3, facing -z
    (4, 5, 6), (4, 6, 7),   // z = 7, facing +z
    (0, 1, 5), (0, 5, 4),   // y = 2, facing -y
    (3, 7, 6), (3, 6, 2),   // y = 5, facing +y
    (0, 4, 7), (0, 7, 3),   // x = 1, facing -x
    (1, 2, 6), (1, 6, 5));  // x = 3, facing +x
begin
  C[0] := V(1, 2, 3); C[1] := V(3, 2, 3); C[2] := V(3, 5, 3); C[3] := V(1, 5, 3);
  C[4] := V(1, 2, 7); C[5] := V(3, 2, 7); C[6] := V(3, 5, 7); C[7] := V(1, 5, 7);
  Result.Clear;
  Result.Name := 'box';
  Result.Allocate(12);
  for T := 0 to 11 do Result.SetTriangle(T, C[F[T, 0]], C[F[T, 1]], C[F[T, 2]]);
end;

// Records share their dynamic arrays: a copy to edit without touching the source.
function CopyMesh(const M: TvgSTLMesh): TvgSTLMesh;
begin
  Result := M;
  Result.Positions := Copy(M.Positions);
  Result.Indices := Copy(M.Indices);
  Result.FaceNormals := Copy(M.FaceNormals);
  Result.Attributes := Copy(M.Attributes);
end;

function SameMesh(const A, B: TvgSTLMesh): Boolean;
var I: Integer; P, Q: TvgSTLVector;
begin
  Result := (A.TriangleCount = B.TriangleCount);
  if not Result then Exit;
  for I := 0 to High(A.Indices) do
  begin
    P := A.Positions[A.Indices[I]]; Q := B.Positions[B.Indices[I]];
    if (P.X <> Q.X) or (P.Y <> Q.Y) or (P.Z <> Q.Z) then Exit(False);
  end;
end;

function FileBytes(const FileName: string): TBytes;
var S: TFileStream;
begin
  S := TFileStream.Create(FileName, fmOpenRead);
  try
    SetLength(Result, S.Size);
    if S.Size > 0 then S.ReadBuffer(Result[0], S.Size);
  finally S.Free; end;
end;

procedure WriteText(const FileName, Text: string);
var S: TFileStream; B: TBytes;
begin
  B := TEncoding.UTF8.GetBytes(Text);
  S := TFileStream.Create(FileName, fmCreate);
  try
    if Length(B) > 0 then S.WriteBuffer(B[0], Length(B));
  finally S.Free; end;
end;

procedure Raises(const Name, Text: string);
var Raised: Boolean; M: TvgSTLMesh; FileName: string;
begin
  FileName := TempDir + 'bad.stl';
  WriteText(FileName, Text);
  Raised := False;
  try M := vgReadSTL(FileName);
  except on E: EvgSTLError do Raised := True; end;
  Check(Name, Raised);
end;

procedure TestFormat;
var
  M, R, W: TvgSTLMesh;
  BMin, BMax, N: TvgSTLVector;
  FileName: string;
  Bytes: TBytes;
  Normals: TArray<TvgSTLVector>;
  Dropped, I: Integer;
  OldSep: Char;
  Count: Cardinal;
  S: TFileStream;
begin
  Writeln('Geometry');
  M := Box;
  Check('12 triangles', M.TriangleCount = 12);
  Check('unwelded: 36 positions', M.VertexCount = 36);
  Check('area 2(6+8+12) = 52', Near(vgSTLArea(M), 52));
  Check('volume 24, outward', Near(vgSTLVolume(M), 24));
  vgSTLBounds(M, BMin, BMax);
  Check('bounds', (BMin.X = 1) and (BMin.Y = 2) and (BMin.Z = 3) and
    (BMax.X = 3) and (BMax.Y = 5) and (BMax.Z = 7));
  N := vgSTLTriangleNormal(V(0, 0, 0), V(1, 0, 0), V(0, 1, 0));
  Check('counter-clockwise normal is +z', (N.X = 0) and (N.Y = 0) and (N.Z = 1));
  N := vgSTLTriangleNormal(V(0, 0, 0), V(1, 0, 0), V(2, 0, 0));
  Check('degenerate normal is zero', (N.X = 0) and (N.Y = 0) and (N.Z = 0));
  Check('first face normal stored', M.FaceNormals[0].Z = -1);

  Writeln('Weld');
  W := M;
  Dropped := vgWeldSTL(W);
  Check('weld drops nothing', Dropped = 0);
  Check('8 corners after weld', W.VertexCount = 8);
  Check('still 12 triangles', W.TriangleCount = 12);
  Check('source mesh untouched', M.VertexCount = 36);
  Check('same triangles', SameMesh(M, W));
  Check('welded box is watertight', vgSTLOpenEdges(W) = 0);
  Check('welded volume unchanged', Near(vgSTLVolume(W), 24));
  Normals := vgSTLVertexNormals(W);
  N := Normals[0];
  Check('corner normal points out along the diagonal',
    (N.X < 0) and (N.Y < 0) and (N.Z < 0) and Near(Sqrt(N.X * N.X + N.Y * N.Y + N.Z * N.Z), 1));
  R := CopyMesh(W);
  SetLength(R.Indices, 33);
  Check('a missing triangle opens three edges', vgSTLOpenEdges(R) = 3);
  R := CopyMesh(M);
  R.Positions[R.Indices[0]] := V(1.00001, 2, 3);
  W := R;
  vgWeldSTL(W);
  Check('exact weld keeps a near corner apart', W.VertexCount = 9);
  W := R;
  vgWeldSTL(W, 0.001);
  Check('tolerance weld merges it', W.VertexCount = 8);
  R := CopyMesh(M);
  R.Positions[R.Indices[1]] := R.Positions[R.Indices[0]];
  W := R;
  Dropped := vgWeldSTL(W);
  Check('collapsed triangle dropped', (Dropped = 1) and (W.TriangleCount = 11));

  Writeln('Binary');
  FileName := TempDir + 'box.stl';
  vgWriteSTL(M, FileName);
  Bytes := FileBytes(FileName);
  Check('binary size 84 + 50n', Length(Bytes) = 84 + 50 * 12);
  Check('detected as binary', not vgSTLIsAscii(Bytes));
  R := vgReadSTL(FileName);
  Check('binary round trip', SameMesh(M, R));
  Check('name kept', R.Name = 'box');
  Check('normal written from geometry', R.FaceNormals[2].Z = 1);
  W := M; W.Name := 'solid trouble';
  vgWriteSTL(W, FileName);
  Bytes := FileBytes(FileName);
  Check('header never starts "solid"', not vgSTLIsAscii(Bytes) and (Bytes[0] <> Ord('s')));
  // A binary file whose header does start "solid" (as many tools write).
  Bytes[0] := Ord('s'); Bytes[1] := Ord('o'); Bytes[2] := Ord('l');
  Bytes[3] := Ord('i'); Bytes[4] := Ord('d');
  Check('"solid" binary still detected by size', not vgSTLIsAscii(Bytes));
  R := vgReadSTLBytes(Bytes);
  Check('and read as binary', SameMesh(M, R));
  W := CopyMesh(M); W.Attributes[3] := $8123;
  vgWriteSTL(W, FileName);
  R := vgReadSTL(FileName);
  Check('attribute word kept', R.Attributes[3] = $8123);
  // Truncated: header says 12 triangles, fewer follow.
  S := TFileStream.Create(FileName, fmOpenReadWrite);
  try S.Size := 84 + 50 * 11 + 10; finally S.Free; end;
  Bytes := FileBytes(FileName);
  Check('truncated binary is not ASCII', not vgSTLIsAscii(Bytes));
  try
    vgReadSTLBytes(Bytes); Check('truncated binary raises', False);
  except on E: EvgSTLError do Check('truncated binary raises', Pos('truncated', E.Message) > 0); end;
  W.Clear;
  vgWriteSTL(W, FileName);
  R := vgReadSTL(FileName);
  Check('empty mesh round trip', (Length(FileBytes(FileName)) = 84) and (R.TriangleCount = 0));
  Bytes := nil; SetLength(Bytes, 84); Count := 0; Move(Count, Bytes[80], 4);
  Check('zero-triangle binary', vgReadSTLBytes(Bytes).TriangleCount = 0);

  Writeln('ASCII');
  OldSep := {$IFDEF FPC}DefaultFormatSettings{$ELSE}FormatSettings{$ENDIF}.DecimalSeparator;
  try
    // Neither writing nor reading may follow a comma locale.
    {$IFDEF FPC}DefaultFormatSettings{$ELSE}FormatSettings{$ENDIF}.DecimalSeparator := ',';
    W := CopyMesh(M); W.Positions[0] := V(1.5e-7, -2.25, 1e6);
    vgWriteSTL(W, FileName, sfAscii);
    Bytes := FileBytes(FileName);
    Check('detected as ASCII', vgSTLIsAscii(Bytes));
    Check('no comma decimals', Pos(',', TEncoding.ASCII.GetString(Bytes)) = 0);
    R := vgReadSTL(FileName);
  finally
    {$IFDEF FPC}DefaultFormatSettings{$ELSE}FormatSettings{$ENDIF}.DecimalSeparator := OldSep;
  end;
  Check('ASCII round trip is exact', SameMesh(W, R));
  Check('ASCII name', R.Name = 'box');
  WriteText(FileName,
    '  SOLID  my part '#13#10 +
    'facet normal 0 0 1'#13#10' outer loop'#13#10 +
    '  vertex 0 0 0'#13#10'  vertex 1 0 0'#13#10'  vertex 1 1 0'#13#10'  vertex 0 1 0'#13#10 +
    ' endloop'#13#10'endfacet'#13#10'endsolid my part'#13#10 +
    'solid second'#10'facet normal 0 0 0 outer loop vertex 0 0 1 vertex 1 0 1 vertex 0 1 1.5E+0 ' +
    'endloop endfacet endsolid');
  R := vgReadSTL(FileName);
  Check('upper case and CRLF accepted', R.Name = 'my part');
  Check('quad facet fans to two triangles, second solid appended', R.TriangleCount = 3);
  Check('exponent parsed', R.Positions[8].Z = 1.5);
  Check('file normal kept', R.FaceNormals[0].Z = 1);
  Raises('missing endloop raises', 'solid x'#10'facet normal 0 0 1 outer loop vertex 0 0 0 vertex 1 0 0 vertex 0 1 0 endfacet');
  Raises('two vertices raise', 'solid x'#10'facet normal 0 0 1 outer loop vertex 0 0 0 vertex 1 0 0 endloop endfacet');
  Raises('bad number raises', 'solid x'#10'facet normal 0 0 1 outer loop vertex 0 0 0 vertex 1 0 0 vertex 0 1,5 0 endloop endfacet');
  Raises('stray keyword raises', 'solid x'#10'polygon');

  Writeln('Size');
  // 200 000 triangles: a fine strip, welded through the hash.
  W.Clear; W.Allocate(200000);
  for I := 0 to 99999 do
  begin
    W.SetTriangle(2 * I, V(I, 0, 0), V(I + 1, 0, 0), V(I + 1, 1, 0));
    W.SetTriangle(2 * I + 1, V(I, 0, 0), V(I + 1, 1, 0), V(I, 1, 0));
  end;
  vgWeldSTL(W);
  Check('strip welds to 200 002 corners', W.VertexCount = 200002);
  Check('strip has 200 002 border edges', vgSTLOpenEdges(W) = 200002);
  Check('source box never edited', Near(vgSTLVolume(M), 24) and (M.Positions[0].X = 1));
end;

{$IFNDEF FPC}
procedure TestScene;
var
  Scene: TvgScene;
  Loader: TvgSceneLoaderStorer_STL;
  Info: TvgSceneLoaderInfo;
  Store: TvgSTLObjectStore;
  M, R: TvgSTLMesh;
  BMin, BMax: TpvVector3D;
  FileName, OutName: string;
  Raised: Boolean;
begin
  Writeln('Scene');
  Check('registered for .STL', FindSceneLoaderForFile('part.STL', Info));
  Check('registered class', Info.LoaderClass = TvgSceneLoaderStorer_STL);
  Check('published file property', Info.FileNameProp = 'FileName');
  FileName := TempDir + 'scene.stl';
  OutName := TempDir + 'scene_out.stl';
  M := Box;
  vgWriteSTL(M, FileName);
  Scene := TvgScene.Create(nil);
  Loader := TvgSceneLoaderStorer_STL.Create(nil);
  try
    Raised := False;
    try Loader.LoadScene; except on E: EvgSTLError do Raised := True; end;
    Check('missing scene reported', Raised);
    Loader.Scene := Scene;
    vgLoadSceneFile(Scene, FileName);
    Check('registry loads one store', (Scene.SceneData.Count = 1) and
      (Scene.SceneData[0] is TvgSTLObjectStore));
    Store := Scene.SceneData[0] as TvgSTLObjectStore;
    Check('welded by default: 8 vertices', Store.GetObjectVertexCount(0) = 8);
    Check('36 indices', Store.GetObjectIndexCount(0) = 36);
    Check('triangle list', Store.Topology = TRIANGLE_LIST);
    Check('smooth shading', Store.Shading = osSmooth);
    Check('solid name', Store.SolidName = 'box');
    Check('scene bounds', Scene.GetDataBounds(BMin, BMax) and Near(BMin.x, 1) and Near(BMax.z, 7));

    Loader.FileName := FileName;
    Loader.WeldVertices := False;
    Loader.LoadScene;
    Store := Scene.SceneData[0] as TvgSTLObjectStore;
    Check('reload replaces the store', Scene.SceneData.Count = 1);
    Check('unwelded: 36 vertices', Store.GetObjectVertexCount(0) = 36);
    Check('flat shading', Store.Shading = osFlat);

    Loader.FileName := OutName;
    Loader.StoreScene;
    R := vgReadSTL(OutName);
    Check('store writes every triangle', SameMesh(M, R));
    Check('stored name', R.Name = 'box');
    Loader.Ascii := True;
    Loader.StoreScene;
    Check('Ascii writes text', vgSTLIsAscii(TFile.ReadAllBytes(OutName)));
    Check('ASCII store reads back', SameMesh(M, vgReadSTL(OutName)));

    Loader.WeldVertices := True;
    M.Name := 'made in code';
    Loader.LoadMesh(M);
    Store := Scene.SceneData[0] as TvgSTLObjectStore;
    Check('LoadMesh replaces the scene', (Scene.SceneData.Count = 1) and (Store.SolidName = 'made in code'));
    Check('LoadMesh welds', Store.GetObjectVertexCount(0) = 8);
    R := Loader.SceneMesh;
    Check('SceneMesh gives the triangles back', SameMesh(M, R));
    Check('SceneMesh is watertight once welded', (vgWeldSTL(R) = 0) and (vgSTLOpenEdges(R) = 0));

    Store.GetObjectItem(0).VisibleON := False;
    Check('hidden object not exported', Loader.SceneMesh.TriangleCount = 0);
    Raised := False;
    try Loader.StoreScene; except on E: EvgSTLError do Raised := True; end;
    Check('nothing to store raises', Raised);

    Loader.FileName := TempDir + 'missing.stl';
    Raised := False;
    try Loader.LoadScene; except on E: EFOpenError do Raised := True; end;
    Check('missing file reported', Raised);
    Check('failed load keeps the scene', Scene.SceneData.Count = 1);
    WriteText(TempDir + 'bad.stl', 'solid x'#10'polygon');
    Loader.FileName := TempDir + 'bad.stl';
    Raised := False;
    try Loader.LoadScene; except on E: EvgSTLError do Raised := True; end;
    Check('bad file reported, scene kept', Raised and (Scene.SceneData.Count = 1));
  finally
    Loader.Free;
    Scene.Free;
  end;
end;
{$ENDIF}

begin
  TempDir := IncludeTrailingPathDelimiter(GetTempDir) + 'vg_stl_test' + PathDelim;
  ForceDirectories(TempDir);
  try
    TestFormat;
    {$IFNDEF FPC}TestScene;{$ENDIF}
  except on E: Exception do begin
    Writeln(E.ClassName, ': ', E.Message); Inc(Failures);
  end; end;
  Writeln('Failures: ', Failures);
  if Failures <> 0 then Halt(1);
end.
