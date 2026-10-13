program InstancingTest;

{$APPTYPE CONSOLE}

{ Vulkan_Instancing without a device: the placement matrix, the scatter, and
  a TvgInstanceSet writing the same copies into every store of a model.
  Run under the default Y-up convention, then the flat surface again Z-up. }

uses
  System.SysUtils, System.Math,
  PasVulkan.Math, PasVulkan.Math.Double,
  Vulkan_Components, Vulkan_Components_Lookups, Vulkan_Components_Camera,
  Vulkan_Components_Descriptors, Vulkan_Components_DataStore,
  Vulkan_Components_Scene_Renderer, Vulkan_WorldAxes, Vulkan_Instancing;

var
  Failures: Integer = 0;

procedure Check(const Name: string; OK: Boolean);
begin
  if OK then Writeln('  ok   ', Name)
  else begin Inc(Failures); Writeln('  FAIL ', Name); end;
end;

function Near(A, B: Double; Tol: Double = 1E-4): Boolean;
begin Result := Abs(A - B) < Tol; end;

function NearV(const V: TpvVector3D; X, Y, Z: Double): Boolean;
begin Result := Near(V.x, X) and Near(V.y, Y) and Near(V.z, Z); end;

function V3(X, Y, Z: Double): TpvVector3D;
begin Result := TpvVector3D.Create(X, Y, Z); end;

// What the shader does: M * vec4(P, 1), columns RawComponents[c].
function Transform(const M: TvgMatrix4x4S; const P: TpvVector3D): TpvVector3D;
begin
  Result.x := M.RawComponents[0, 0] * P.x + M.RawComponents[1, 0] * P.y + M.RawComponents[2, 0] * P.z + M.RawComponents[3, 0];
  Result.y := M.RawComponents[0, 1] * P.x + M.RawComponents[1, 1] * P.y + M.RawComponents[2, 1] * P.z + M.RawComponents[3, 1];
  Result.z := M.RawComponents[0, 2] * P.x + M.RawComponents[1, 2] * P.y + M.RawComponents[2, 2] * P.z + M.RawComponents[3, 2];
end;

// Accepts only the half x >= 0, on a flat plane at height 2.
type
  THalfPlane = class(TInterfacedObject, IvgSurfaceSampler)
    function Sample(const aPoint: TpvVector3D; out aSurface, aNormal: TpvVector3D): Boolean;
  end;

function THalfPlane.Sample(const aPoint: TpvVector3D; out aSurface, aNormal: TpvVector3D): Boolean;
begin
  aNormal  := vgWorldUp;
  aSurface := aPoint + aNormal * (2 - vgUpComponent(aPoint));
  Result   := aPoint.x >= 0;
end;

procedure TestPlacement;
var M: TvgMatrix4x4S; Pivot: TpvVector3D;
begin
  Writeln('--- placement matrix (Y up) ---');
  Pivot := V3(0.5, 0, 0.5);
  M := vgPlacementMatrix(Pivot, V3(10, 3, -4), V3(0, 0, 0), 0, 1, vgWorldUp);
  Check('pivot lands on the position', NearV(Transform(M, Pivot), 10, 3, -4));
  Check('no turn, no scale: a plain move', NearV(Transform(M, V3(1.5, 1, 0.5)), 11, 4, -4));

  // +90 degrees about +Y (right handed): +X goes to -Z.
  M := vgPlacementMatrix(V3(0, 0, 0), V3(0, 0, 0), V3(0, 0, 0), 90, 1, vgWorldUp);
  Check('spin about up: +X turns to -Z', NearV(Transform(M, V3(1, 0, 0)), 0, 0, -1));
  Check('spin about up: up stays up', NearV(Transform(M, V3(0, 1, 0)), 0, 1, 0));

  M := vgPlacementMatrix(V3(0, 0, 0), V3(0, 0, 0), V3(0, 0, 0), 0, 2.5, vgWorldUp);
  Check('scale about the pivot', NearV(Transform(M, V3(1, 1, 1)), 2.5, 2.5, 2.5));

  M := vgPlacementMatrix(V3(0, 0, 0), V3(0, 0, 0), V3(0, 0, 0), 0, 1, V3(1, 0, 0));
  Check('tilt: the model''s up becomes the given up', NearV(Transform(M, V3(0, 1, 0)), 1, 0, 0));

  M := vgPlacementMatrix(V3(0, 0, 0), V3(0, 0, 0), V3(1, 0, 0), 90, 1, vgWorldUp);
  Check('spin about another axis: +Y about +X goes to +Z', NearV(Transform(M, V3(0, 1, 0)), 0, 0, 1));
end;

procedure TestScatter;
var S: TvgScatterSettings; A, B: TvgMatrixArray; I, J: Integer; P, Q: TpvVector3D;
  Flat, Half: IvgSurfaceSampler; AllOK: Boolean;
begin
  Writeln('--- scatter (Y up) ---');
  Flat := TvgFlatSurface.Create(5);
  S := TvgScatterSettings.Default(200, V3(-50, 0, -20), V3(50, 0, 20));
  S.Seed := 42; S.ScaleMin := 0.5; S.ScaleMax := 2; S.HeightOffset := 0.25;
  A := vgScatterMatrices(S, Flat, V3(0, 0, 0));
  B := vgScatterMatrices(S, Flat, V3(0, 0, 0));
  Check('all 200 copies placed', Length(A) = 200);
  Check('same seed, same matrices', (Length(A) = Length(B)) and CompareMem(@A[0], @B[0], Length(A) * SizeOf(A[0])));
  S.Seed := 43;
  B := vgScatterMatrices(S, Flat, V3(0, 0, 0));
  Check('another seed, other matrices', not CompareMem(@A[0], @B[0], Length(A) * SizeOf(A[0])));

  AllOK := True;
  for I := 0 to High(A) do
  begin
    P := Transform(A[I], V3(0, 0, 0));
    if not (Near(P.y, 5.25) and InRange(P.x, -50, 50) and InRange(P.z, -20, 20)) then AllOK := False;
  end;
  Check('every pivot on the surface (+offset), inside the region', AllOK);

  AllOK := True;
  for I := 0 to High(A) do
  begin
    Q := Transform(A[I], V3(0, 1, 0)) - Transform(A[I], V3(0, 0, 0));
    if not (InRange(Q.Length, 0.5 - 1E-4, 2 + 1E-4) and Near(Q.x, 0) and Near(Q.z, 0)) then AllOK := False;
  end;
  Check('upright, scale within range', AllOK);

  S := TvgScatterSettings.Default(100, V3(-50, 0, -50), V3(50, 0, 50));
  Half := THalfPlane.Create;
  A := vgScatterMatrices(S, Half, V3(0, 0, 0));
  AllOK := Length(A) = 100;
  for I := 0 to High(A) do
  begin
    P := Transform(A[I], V3(0, 0, 0));
    if (P.x < 0) or not Near(P.y, 2) then AllOK := False;
  end;
  Check('rejected points are drawn again; only accepted ones kept', AllOK);

  S := TvgScatterSettings.Default(1000, V3(0, 0, 0), V3(20, 0, 20));
  S.MinSpacing := 2;
  A := vgScatterMatrices(S, Flat, V3(0, 0, 0));
  AllOK := (Length(A) > 20) and (Length(A) < 1000);
  for I := 0 to High(A) do
    for J := I + 1 to High(A) do
    begin
      P := Transform(A[I], V3(0, 0, 0)); Q := Transform(A[J], V3(0, 0, 0));
      if Sqr(P.x - Q.x) + Sqr(P.z - Q.z) < Sqr(2) - 1E-6 then AllOK := False;
    end;
  Check(Format('min spacing kept; gave up at %d of 1000', [Length(A)]), AllOK);

  S := TvgScatterSettings.Default(50, V3(0, 0, 0), V3(10, 0, 10));
  S.AlignToSlope := 1;
  A := vgScatterMatrices(S, Flat, V3(0, 0, 0));
  Q := Transform(A[0], V3(0, 1, 0)) - Transform(A[0], V3(0, 0, 0));
  Check('align to a level surface: still upright', NearV(Q, 0, 1, 0));
end;

// A two-triangle unit square in its own store, built and ID'd as a loader
// builds one (TvgObject API, AddObjectID).
function MakeStore(aLeft: Double): TvgObjectStore;
var Obj: TvgObject; I: Integer;
begin
  Result := TvgObjectStore.Create(nil);
  Result.SetupVertexAttributes([vdtPosition, vdtColor]);
  Result.SetupInstanceAttributes([idtObjID]);
  Result.SetIndexType(itUInt32);
  Obj := Result.AddObject(True);
  Obj.AddObjectID;
  for I := 0 to 3 do
  begin
    Obj.AddVertex;
    Obj.SetVertexPosition(aLeft + (I mod 2), I div 2, 0);
  end;
  Obj.AddIndex(0, 1, 2); Obj.AddIndex(2, 1, 3);
end;

procedure TestInstanceSet;
var A, B: TvgObjectStore; Set_: TvgInstanceSet; M: TvgMatrixArray; Box: TvgAABB;
  ID1, ID2, A1, A2, B1, B2: Cardinal; J: Integer; AllOK, Raised: Boolean; P: TpvVector3D;
begin
  Writeln('--- instance set ---');
  A := MakeStore(0); B := MakeStore(1);
  A.GetObjectInstanceObjID(0, 0, A1, A2);
  B.GetObjectInstanceObjID(0, 0, B1, B2);
  Check('the two objects have different IDs', (A1 <> B1) or (A2 <> B2));
  Set_ := TvgInstanceSet.Create([A, B]);
  try
    Box := Set_.ModelBounds;
    Check('model bounds: union of both stores', Box.Valid and Near(Box.Min.x, 0) and Near(Box.Max.x, 2) and Near(Box.Max.y, 1));
    P := Set_.BasePivot;
    Check('base pivot: middle across, bottom along up', NearV(P, 1, 0, 0));

    SetLength(M, 3);
    for J := 0 to 2 do
      M[J] := vgPlacementMatrix(Set_.BasePivot, V3(10 * J, 0, 0), V3(0, 0, 0), 0, 1, vgWorldUp);
    Set_.SetMatrices(M);
    Check('stores made instanced', A.IsInstanceTypeSet(idtMatrix) and B.IsInstanceTypeSet(idtMatrix));
    Check('three copies in each store', (A.GetObjectInstanceCount(0) = 3) and (B.GetObjectInstanceCount(0) = 3));
    AllOK := True;
    for J := 0 to 2 do
    begin
      A.GetObjectInstanceObjID(0, J, ID1, ID2);
      if (ID1 <> A1) or (ID2 <> A2) then AllOK := False;
      B.GetObjectInstanceObjID(0, J, ID1, ID2);
      if (ID1 <> B1) or (ID2 <> B2) then AllOK := False;
    end;
    Check('every copy keeps its store''s object ID', AllOK);
    Check('vertices not copied', (A.GetObjectVertexCount(0) = 4) and (B.GetObjectVertexCount(0) = 4));
    Box := A.GetObjectWorldBounds(0);
    Check('world bound covers every copy', Box.Valid and Near(Box.Min.x, -1) and Near(Box.Max.x, 20));

    SetLength(M, 1);
    Set_.SetMatrices(M);
    Check('fewer copies: count cut to 1', (A.GetObjectInstanceCount(0) = 1) and (B.GetObjectInstanceCount(0) = 1));
    Set_.SetMatrices(nil);
    Check('no copies: nothing drawn', (A.GetObjectInstanceCount(0) = 0) and A.ShouldSkipObject(0));
    SetLength(M, 2);
    M[0] := TvgMatrix4x4S.Identity; M[1] := TvgMatrix4x4S.Identity;
    Set_.SetMatrices(M);
    A.GetObjectInstanceObjID(0, 1, ID1, ID2);
    Check('back from none: copies drawn again, object ID kept',
      (A.GetObjectInstanceCount(0) = 2) and not A.ShouldSkipObject(0) and (ID1 = A1) and (ID2 = A2));

    B.Free;
    Check('a freed store leaves the set', Set_.StoreCount = 1);
  finally
    Set_.Free; A.Free;
  end;

  A := MakeStore(0);
  try
    A.PrebuiltShaderVariants := True; A.BaseVertName := 'NoSuchShader'; A.BaseFragName := 'NoSuchShader';
    Raised := False;
    try vgMakeStoreInstanced(A); except on E: EvgInstancingError do Raised := True; end;
    Check('a prebuilt shader with no Inst variant is refused', Raised and not A.IsInstanceTypeSet(idtMatrix));
    A.BaseVertName := 'OBJ';
    vgMakeStoreInstanced(A);
    Check('one that has it is converted', A.IsInstanceTypeSet(idtMatrix));
  finally
    A.Free;
  end;
end;

procedure TestZUp;
var S: TvgScatterSettings; A: TvgMatrixArray; I: Integer; P, Q: TpvVector3D; AllOK: Boolean;
  Flat: IvgSurfaceSampler;
begin
  Writeln('--- scatter (Z up) ---');
  if not vgSetAxisConvention(acZUp) then
  begin
    Check('switch to Z up', False);
    Exit;
  end;
  try
    S := TvgScatterSettings.Default(100, V3(-10, -10, 0), V3(10, 10, 0));
    Flat := TvgFlatSurface.Create(3);
    A := vgScatterMatrices(S, Flat, V3(0, 0, 0));
    AllOK := Length(A) = 100;
    for I := 0 to High(A) do
    begin
      P := Transform(A[I], V3(0, 0, 0));
      Q := Transform(A[I], V3(0, 0, 1)) - P;
      if not (Near(P.z, 3) and NearV(Q, 0, 0, 1)) then AllOK := False;
    end;
    Check('Z up: every copy at z = 3, upright along +Z', AllOK);
  finally
    vgSetAxisConvention(acYUp);
  end;
end;

begin
  // The package may be built Z up (VulkanPackage.inc); these run Y up first.
  if not vgSetAxisConvention(acYUp) then
  begin
    Writeln('FAIL could not switch to Y up');
    Halt(1);
  end;
  try
    TestPlacement;
    TestScatter;
    TestInstanceSet;
    TestZUp;
  except
    on E: Exception do begin Inc(Failures); Writeln(E.ClassName, ': ', E.Message); end;
  end;
  if Failures = 0 then Writeln('ALL CHECKS PASSED')
  else Writeln('Failures: ', Failures);
  if Failures <> 0 then Halt(1);
end.
