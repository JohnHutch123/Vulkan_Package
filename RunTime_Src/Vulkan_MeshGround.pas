unit Vulkan_MeshGround;

{
  Vulkan_MeshGround.pas

  TvgMeshGround: the ground under a point, from any triangle mesh - a
  terrain, a Delaunay surface shown as triangles, a building's floors.  It
  is the IvgGroundProvider that walk mode (TvgFirstPersonController,
  nmWalk) follows.

  Triangles are kept in world coordinates, in double (survey coordinates
  stay exact), and bucketed in a uniform 2D grid over the two horizontal
  axes - each triangle in every cell its footprint touches.  A query looks
  only at its own cell: a vertical line through the point, the barycentric
  height of each triangle it passes through, and the highest one that is
  not above the limit asked for.  "Highest below a limit" is what lets walk
  mode handle bridges and storeys: the limit is the feet plus a step.

  Vertical triangles (walls) have no footprint and are skipped - this is
  ground following, not collision.

  Up is an axis: +/-X, +/-Y or +/-Z, the dominant component of the vector
  given to Create (vgWorldUp for the package convention).

  Build once, query many times; adding triangles after a query rebuilds the
  grid at the next query.  Not thread-safe: query from one thread.
}

interface

uses
  System.SysUtils,
  System.Math,
  PasVulkan.Math.Double,
  Vulkan_FirstPerson;

type
  TvgMeshGround = class(TInterfacedObject, IvgGroundProvider)
  private
    fUp       : TpvVector3D;
    fUpAxis   : Integer;    // 0..2
    fUpSign   : Double;     // +1 / -1
    fUAxis    : Integer;
    fVAxis    : Integer;

    fVerts    : TArray<TpvVector3D>;
    fVertCount: Integer;
    fTris     : TArray<Integer>;      // 3 per triangle
    fTriCount : Integer;

    fBuilt    : Boolean;
    fMinU     : Double;
    fMinV     : Double;
    fCell     : Double;
    fNU, fNV  : Integer;
    fCellStart: TArray<Integer>;      // fNU*fNV + 1
    fCellTris : TArray<Integer>;

    function  CompU(const P: TpvVector3D): Double; inline;
    function  CompV(const P: TpvVector3D): Double; inline;
    function  CompH(const P: TpvVector3D): Double; inline;
    function  CellOf(aU, aV: Double; out aI, aJ: Integer): Boolean;
    procedure Build;

  public
    constructor Create(const aUp: TpvVector3D);

    procedure Clear;
    procedure AddTriangle(const A, B, C: TpvVector3D);
    { aVertices with aIndices in threes (local numbers into aVertices), as
      TvgObject.GetVertexWorldPositions / GetPrimitives give them.  Triples
      naming a vertex out of range are skipped. }
    procedure AddMesh(const aVertices: TArray<TpvVector3D>; const aIndices: TArray<Integer>);

    // IvgGroundProvider
    function  GroundAt(const aPoint: TpvVector3D; aMaxHeight: Double;
                       out aGround, aNormal: TpvVector3D): Boolean;
    function  GroundUp: TpvVector3D;

    property  TriangleCount : Integer read fTriCount;
    // Grid size, for tests and tuning; 0 until the first query.
    property  CellsU : Integer read fNU;
    property  CellsV : Integer read fNV;
  end;

implementation

const
  // Barycentric slack: a point on a shared edge belongs to both triangles.
  BARY_EPS   = 1e-9;
  MAX_CELLS  = 4 * 1024 * 1024;
  MAX_SIDE   = 4096;

function Comp(const P: TpvVector3D; aAxis: Integer): Double; inline;
begin
  case aAxis of
    0 : Result := P.x;
    1 : Result := P.y;
  else
    Result := P.z;
  end;
end;

{ TvgMeshGround }

constructor TvgMeshGround.Create(const aUp: TpvVector3D);
var
  AX, AY, AZ : Double;
begin
  inherited Create;
  AX := Abs(aUp.x); AY := Abs(aUp.y); AZ := Abs(aUp.z);
  if (AZ >= AX) and (AZ >= AY) then fUpAxis := 2
  else if AY >= AX then fUpAxis := 1
  else fUpAxis := 0;
  if Comp(aUp, fUpAxis) < 0 then fUpSign := -1 else fUpSign := 1;

  fUp := TpvVector3D.Create(0, 0, 0);
  case fUpAxis of
    0 : fUp.x := fUpSign;
    1 : fUp.y := fUpSign;
  else
    fUp.z := fUpSign;
  end;
  fUAxis := (fUpAxis + 1) mod 3;
  fVAxis := (fUpAxis + 2) mod 3;
end;

function TvgMeshGround.CompU(const P: TpvVector3D): Double;
begin
  Result := Comp(P, fUAxis);
end;

function TvgMeshGround.CompV(const P: TpvVector3D): Double;
begin
  Result := Comp(P, fVAxis);
end;

function TvgMeshGround.CompH(const P: TpvVector3D): Double;
begin
  Result := fUpSign * Comp(P, fUpAxis);
end;

procedure TvgMeshGround.Clear;
begin
  fVerts     := nil;  fVertCount := 0;
  fTris      := nil;  fTriCount  := 0;
  fCellStart := nil;  fCellTris  := nil;
  fNU := 0; fNV := 0;
  fBuilt := False;
end;

procedure TvgMeshGround.AddTriangle(const A, B, C: TpvVector3D);
begin
  if fVertCount + 3 > Length(fVerts) then
    SetLength(fVerts, Max(64, (fVertCount + 3) * 2));
  if (fTriCount + 1) * 3 > Length(fTris) then
    SetLength(fTris, Max(96, (fTriCount + 1) * 6));
  fVerts[fVertCount]     := A;
  fVerts[fVertCount + 1] := B;
  fVerts[fVertCount + 2] := C;
  fTris[fTriCount * 3]     := fVertCount;
  fTris[fTriCount * 3 + 1] := fVertCount + 1;
  fTris[fTriCount * 3 + 2] := fVertCount + 2;
  Inc(fVertCount, 3);
  Inc(fTriCount);
  fBuilt := False;
end;

procedure TvgMeshGround.AddMesh(const aVertices: TArray<TpvVector3D>; const aIndices: TArray<Integer>);
var
  Base, N, I, T : Integer;
  A, B, C       : Integer;
begin
  N := Length(aVertices);
  if (N = 0) or (Length(aIndices) < 3) then exit;

  Base := fVertCount;
  if fVertCount + N > Length(fVerts) then
    SetLength(fVerts, fVertCount + N);
  for I := 0 to N - 1 do
    fVerts[fVertCount + I] := aVertices[I];
  Inc(fVertCount, N);

  T := Length(aIndices) div 3;
  if (fTriCount + T) * 3 > Length(fTris) then
    SetLength(fTris, (fTriCount + T) * 3);
  for I := 0 to T - 1 do
  begin
    A := aIndices[I * 3];
    B := aIndices[I * 3 + 1];
    C := aIndices[I * 3 + 2];
    if (A < 0) or (B < 0) or (C < 0) or (A >= N) or (B >= N) or (C >= N) then
      Continue;
    fTris[fTriCount * 3]     := Base + A;
    fTris[fTriCount * 3 + 1] := Base + B;
    fTris[fTriCount * 3 + 2] := Base + C;
    Inc(fTriCount);
  end;
  fBuilt := False;
end;

function TvgMeshGround.CellOf(aU, aV: Double; out aI, aJ: Integer): Boolean;
var
  FI, FJ : Double;
begin
  Result := False;
  aI := 0; aJ := 0;
  if (fNU = 0) or (fNV = 0) then exit;
  FI := (aU - fMinU) / fCell;
  FJ := (aV - fMinV) / fCell;
  // A point just on the far edge belongs to the last cell.
  if (FI < -BARY_EPS) or (FJ < -BARY_EPS) or
     (FI > fNU + BARY_EPS) or (FJ > fNV + BARY_EPS) then exit;
  aI := EnsureRange(Trunc(FI), 0, fNU - 1);
  aJ := EnsureRange(Trunc(FJ), 0, fNV - 1);
  Result := True;
end;

procedure TvgMeshGround.Build;
var
  T, K, I, J      : Integer;
  I0, I1, J0, J1  : Integer;
  MaxU, MaxV, Area: Double;
  U, V            : Double;
  TMinU, TMaxU,
  TMinV, TMaxV    : Double;
  Fill            : TArray<Integer>;
  Total           : Integer;

  procedure TriRange(aT: Integer);
  var
    C : Integer;
  begin
    TMinU := MaxDouble; TMaxU := -MaxDouble;
    TMinV := MaxDouble; TMaxV := -MaxDouble;
    for C := 0 to 2 do
    begin
      U := CompU(fVerts[fTris[aT * 3 + C]]);
      V := CompV(fVerts[fTris[aT * 3 + C]]);
      if U < TMinU then TMinU := U;
      if U > TMaxU then TMaxU := U;
      if V < TMinV then TMinV := V;
      if V > TMaxV then TMaxV := V;
    end;
  end;

begin
  fBuilt := True;
  fNU := 0; fNV := 0;
  fCellStart := nil; fCellTris := nil;
  if fTriCount = 0 then exit;

  fMinU := MaxDouble; MaxU := -MaxDouble;
  fMinV := MaxDouble; MaxV := -MaxDouble;
  for T := 0 to fTriCount - 1 do
  begin
    TriRange(T);
    fMinU := Min(fMinU, TMinU); MaxU := Max(MaxU, TMaxU);
    fMinV := Min(fMinV, TMinV); MaxV := Max(MaxV, TMaxV);
  end;

  // About two triangles per cell over the footprint.
  Area  := Max(MaxU - fMinU, 1e-9) * Max(MaxV - fMinV, 1e-9);
  fCell := Sqrt(Area / Max(1, fTriCount div 2));
  if fCell <= 0 then fCell := 1;
  fNU := Max(1, Ceil((MaxU - fMinU) / fCell));
  fNV := Max(1, Ceil((MaxV - fMinV) / fCell));
  while (fNU > MAX_SIDE) or (fNV > MAX_SIDE) or (Int64(fNU) * fNV > MAX_CELLS) do
  begin
    fCell := fCell * 1.5;
    fNU := Max(1, Ceil((MaxU - fMinU) / fCell));
    fNV := Max(1, Ceil((MaxV - fMinV) / fCell));
  end;

  // Counting pass, prefix sum, filling pass (CSR).
  SetLength(fCellStart, fNU * fNV + 1);
  for K := 0 to High(fCellStart) do fCellStart[K] := 0;

  for T := 0 to fTriCount - 1 do
  begin
    TriRange(T);
    CellOf(TMinU, TMinV, I0, J0);
    CellOf(TMaxU, TMaxV, I1, J1);
    for J := J0 to J1 do
      for I := I0 to I1 do
        Inc(fCellStart[J * fNU + I + 1]);
  end;
  for K := 1 to High(fCellStart) do
    Inc(fCellStart[K], fCellStart[K - 1]);
  Total := fCellStart[High(fCellStart)];

  SetLength(fCellTris, Total);
  SetLength(Fill, fNU * fNV);
  for K := 0 to High(Fill) do Fill[K] := fCellStart[K];

  for T := 0 to fTriCount - 1 do
  begin
    TriRange(T);
    CellOf(TMinU, TMinV, I0, J0);
    CellOf(TMaxU, TMaxV, I1, J1);
    for J := J0 to J1 do
      for I := I0 to I1 do
      begin
        K := J * fNU + I;
        fCellTris[Fill[K]] := T;
        Inc(Fill[K]);
      end;
  end;
end;

function TvgMeshGround.GroundAt(const aPoint: TpvVector3D; aMaxHeight: Double;
                                out aGround, aNormal: TpvVector3D): Boolean;
var
  I, J, K, T      : Integer;
  PU, PV          : Double;
  A, B, C         : TpvVector3D;
  X1, Y1, X2, Y2,
  X3, Y3          : Double;
  Det, L1, L2, L3 : Double;
  H, Best         : Double;
  BestT           : Integer;
  N               : TpvVector3D;
begin
  Result  := False;
  aGround := aPoint;
  aNormal := fUp;
  if not fBuilt then Build;

  PU := CompU(aPoint);
  PV := CompV(aPoint);
  if not CellOf(PU, PV, I, J) then exit;

  Best  := -MaxDouble;
  BestT := -1;
  K := J * fNU + I;
  for K := fCellStart[K] to fCellStart[K + 1] - 1 do
  begin
    T := fCellTris[K];
    A := fVerts[fTris[T * 3]];
    B := fVerts[fTris[T * 3 + 1]];
    C := fVerts[fTris[T * 3 + 2]];

    // Relative to the point: survey-sized coordinates cancel before the
    // products are formed.
    X1 := CompU(A) - PU;  Y1 := CompV(A) - PV;
    X2 := CompU(B) - PU;  Y2 := CompV(B) - PV;
    X3 := CompU(C) - PU;  Y3 := CompV(C) - PV;

    Det := (Y2 - Y3) * (X1 - X3) + (X3 - X2) * (Y1 - Y3);
    if Abs(Det) < 1e-18 then Continue;     // no footprint: a wall

    L1 := ((Y2 - Y3) * (-X3) + (X3 - X2) * (-Y3)) / Det;
    L2 := ((Y3 - Y1) * (-X3) + (X1 - X3) * (-Y3)) / Det;
    L3 := 1 - L1 - L2;
    if (L1 < -BARY_EPS) or (L2 < -BARY_EPS) or (L3 < -BARY_EPS) then Continue;

    H := L1 * CompH(A) + L2 * CompH(B) + L3 * CompH(C);
    if (H <= aMaxHeight + BARY_EPS) and (H > Best) then
    begin
      Best  := H;
      BestT := T;
    end;
  end;

  if BestT < 0 then exit;

  A := fVerts[fTris[BestT * 3]];
  B := fVerts[fTris[BestT * 3 + 1]];
  C := fVerts[fTris[BestT * 3 + 2]];
  N := (B - A).Cross(C - A);
  if N.Dot(fUp) < 0 then N := -N;
  if N.Length > 0 then aNormal := N.Normalize;

  // The point itself, moved along up onto the surface.
  aGround := aPoint + fUp * (Best - CompH(aPoint));
  Result  := True;
end;

function TvgMeshGround.GroundUp: TpvVector3D;
begin
  Result := fUp;
end;

end.
