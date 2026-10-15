unit Vulkan_MeshUtils;

{ Mesh building shared by the loaders (OBJ here; VRML, DXF in PRO):

    vgPolygonNormal      - Newell's normal of a polygon, unnormalised, so
                           its length is twice the area: weights for smooth
                           normals.
    vgTriangulatePolygon - ear clipping of a simple polygon, planar or
                           nearly so, convex or not.
    vgBuildTangents      - a unit tangent frame per vertex from UVs.

  Double precision in, so survey coordinates triangulate as well as small
  ones. }

interface

uses
  System.SysUtils, System.Math, System.Generics.Collections,
  PasVulkan.Math, PasVulkan.Math.Double;

type
  TvgTriangulateResult = (
    trOK,
    trDegenerate,  // no area: all points on a line (or fewer than three)
    trFailed       // not a simple polygon: duplicate or crossing edges
  );

function vgPolygonNormal(const aPoints: array of TpvVector3D): TpvVector3D;

{ Triangles of the polygon aPoints, as indices into it, three a triangle.
  A triangle is passed through as it is, even with no area (exported
  sphere poles have them).  A convex polygon gives the fan from corner 0,
  in order.  aNormal is vgPolygonNormal.  On anything but trOK, aTriangles
  is empty. }
function vgTriangulatePolygon(const aPoints: array of TpvVector3D;
  out aTriangles: TArray<Integer>; out aNormal: TpvVector3D): TvgTriangulateResult;

{ A tangent frame for each vertex: per triangle the UV derivatives give a
  tangent (along +U) and a bitangent (along +V, OpenGL normal-map
  convention), summed per vertex; then the tangent is made perpendicular to
  the vertex normal (Gram-Schmidt) and the bitangent rebuilt as normal x
  tangent, flipped where the UVs are mirrored, so the frame is orthonormal.
  A vertex with no usable UVs gets any unit tangent perpendicular to its
  normal - every vertex when aTriangles is False (lines, points).
  aUV: x = u, y = v.  aIndices: three per triangle when aTriangles. }
procedure vgBuildTangents(const aPositions, aNormals, aUV: TArray<TpvVector3>;
  const aIndices: TArray<Integer>; aTriangles: Boolean;
  out aTangents, aBiTangents: TArray<TpvVector3D>);

implementation

function vgPolygonNormal(const aPoints: array of TpvVector3D): TpvVector3D;
var
  I    : Integer;
  V, N : TpvVector3D;
begin
  Result := TpvVector3D.Create(0, 0, 0);
  for I := 0 to High(aPoints) do
  begin
    V := aPoints[I];
    N := aPoints[(I + 1) mod Length(aPoints)];
    Result.x := Result.x + (V.y - N.y) * (V.z + N.z);
    Result.y := Result.y + (V.z - N.z) * (V.x + N.x);
    Result.z := Result.z + (V.x - N.x) * (V.y + N.y);
  end;
end;

function vgTriangulatePolygon(const aPoints: array of TpvVector3D;
  out aTriangles: TArray<Integer>; out aNormal: TpvVector3D): TvgTriangulateResult;
var
  V          : TpvVector3D;
  XY         : TArray<TpvVector2D>;
  Remaining, Tri : TList<Integer>;
  I, J, A, B, C, Q, Axis : Integer;
  Area, Sign, Eps, Extent : Double;
  Ear, Inside : Boolean;

  function Cross2(U, V, W: Integer): Double;
  begin
    Result := (XY[V].x - XY[U].x) * (XY[W].y - XY[U].y) -
              (XY[V].y - XY[U].y) * (XY[W].x - XY[U].x);
  end;

begin
  aTriangles := nil;
  aNormal := vgPolygonNormal(aPoints);
  if Length(aPoints) < 3 then Exit(trDegenerate);
  // Preserve degenerate triangles (common at exported sphere poles).
  if Length(aPoints) = 3 then
  begin
    aTriangles := TArray<Integer>.Create(0, 1, 2);
    Exit(trOK);
  end;

  // Project onto the plane the normal is most along.
  Axis := 2;
  if (Abs(aNormal.x) > Abs(aNormal.y)) and (Abs(aNormal.x) > Abs(aNormal.z)) then Axis := 0
  else if Abs(aNormal.y) > Abs(aNormal.z) then Axis := 1;
  SetLength(XY, Length(aPoints));
  for I := 0 to High(XY) do
  begin
    V := aPoints[I];
    case Axis of
      0: XY[I] := TpvVector2D.Create(V.y, V.z);
      1: XY[I] := TpvVector2D.Create(V.x, V.z);
    else
      XY[I] := TpvVector2D.Create(V.x, V.y);
    end;
  end;
  Area := 0; Extent := 0;
  for I := 1 to High(XY) - 1 do Area := Area + Cross2(0, I, I + 1);
  for I := 1 to High(XY) do
    Extent := Max(Extent, Max(Abs(XY[I].x - XY[0].x), Abs(XY[I].y - XY[0].y)));
  Eps := Extent * Extent * 1e-12;
  if Abs(Area) <= Eps then Exit(trDegenerate);
  Sign := 1; if Area < 0 then Sign := -1;

  Remaining := TList<Integer>.Create;
  Tri := TList<Integer>.Create;
  try
    for I := 0 to High(XY) do Remaining.Add(I);
    while Remaining.Count > 3 do
    begin
      Ear := False;
      // Start at corner 1 so a convex polygon keeps the fan order.
      for J := 1 to Remaining.Count do
      begin
        I := J mod Remaining.Count;
        A := Remaining[(I + Remaining.Count - 1) mod Remaining.Count];
        B := Remaining[I]; C := Remaining[(I + 1) mod Remaining.Count];
        if Sign * Cross2(A, B, C) <= Eps then Continue;
        Inside := False;
        for Q in Remaining do
          if (Q <> A) and (Q <> B) and (Q <> C) and
             (Sign * Cross2(A, B, Q) >= -Eps) and
             (Sign * Cross2(B, C, Q) >= -Eps) and
             (Sign * Cross2(C, A, Q) >= -Eps) then begin Inside := True; Break; end;
        if Inside then Continue;
        Tri.Add(A); Tri.Add(B); Tri.Add(C);
        Remaining.Delete(I); Ear := True; Break;
      end;
      if not Ear then Exit(trFailed);
    end;
    Tri.Add(Remaining[0]); Tri.Add(Remaining[1]); Tri.Add(Remaining[2]);
    aTriangles := Tri.ToArray;
    Result := trOK;
  finally
    Tri.Free;
    Remaining.Free;
  end;
end;

procedure vgBuildTangents(const aPositions, aNormals, aUV: TArray<TpvVector3>;
  const aIndices: TArray<Integer>; aTriangles: Boolean;
  out aTangents, aBiTangents: TArray<TpvVector3D>);
var
  Bit : TArray<TpvVector3D>;
  A, B, CI, K, N : Integer;
  E1, E2, NV, TV, BV : TpvVector3D;
  DU1, DV1, DU2, DV2, Det, R, Len : Double;

  function V3(const V: TpvVector3): TpvVector3D;
  begin Result := TpvVector3D.Create(V.x, V.y, V.z); end;
  function Cross(const X, Y: TpvVector3D): TpvVector3D;
  begin
    Result := TpvVector3D.Create(X.y * Y.z - X.z * Y.y, X.z * Y.x - X.x * Y.z, X.x * Y.y - X.y * Y.x);
  end;
  function Dot(const X, Y: TpvVector3D): Double;
  begin Result := X.x * Y.x + X.y * Y.y + X.z * Y.z; end;
  procedure AddTo(I: Integer; const T, U: TpvVector3D);
  begin
    aTangents[I] := TpvVector3D.Create(aTangents[I].x + T.x, aTangents[I].y + T.y, aTangents[I].z + T.z);
    Bit[I] := TpvVector3D.Create(Bit[I].x + U.x, Bit[I].y + U.y, Bit[I].z + U.z);
  end;

begin
  N := Length(aPositions);
  SetLength(aTangents, N); SetLength(Bit, N); SetLength(aBiTangents, N);   // zeroed
  if aTriangles then
  begin
    K := 0;
    while K + 2 < Length(aIndices) do
    begin
      A := aIndices[K]; B := aIndices[K + 1]; CI := aIndices[K + 2]; Inc(K, 3);
      E1 := TpvVector3D.Create(aPositions[B].x - aPositions[A].x, aPositions[B].y - aPositions[A].y, aPositions[B].z - aPositions[A].z);
      E2 := TpvVector3D.Create(aPositions[CI].x - aPositions[A].x, aPositions[CI].y - aPositions[A].y, aPositions[CI].z - aPositions[A].z);
      DU1 := aUV[B].x - aUV[A].x; DV1 := aUV[B].y - aUV[A].y;
      DU2 := aUV[CI].x - aUV[A].x; DV2 := aUV[CI].y - aUV[A].y;
      Det := DU1 * DV2 - DU2 * DV1;
      if Abs(Det) < 1e-12 then Continue;   // no UV mapping on this triangle
      R := 1 / Det;
      TV := TpvVector3D.Create((E1.x * DV2 - E2.x * DV1) * R, (E1.y * DV2 - E2.y * DV1) * R,
                               (E1.z * DV2 - E2.z * DV1) * R);
      BV := TpvVector3D.Create((E2.x * DU1 - E1.x * DU2) * R, (E2.y * DU1 - E1.y * DU2) * R,
                               (E2.z * DU1 - E1.z * DU2) * R);
      AddTo(A, TV, BV); AddTo(B, TV, BV); AddTo(CI, TV, BV);
    end;
  end;
  for K := 0 to N - 1 do
  begin
    NV := V3(aNormals[K]);
    Len := Sqrt(Dot(NV, NV));   // a file's normal need not be unit length
    if Len > 1e-12 then NV := TpvVector3D.Create(NV.x / Len, NV.y / Len, NV.z / Len)
    else NV := TpvVector3D.Create(0, 0, 1);
    TV := aTangents[K];
    R := Dot(NV, TV);
    TV := TpvVector3D.Create(TV.x - NV.x * R, TV.y - NV.y * R, TV.z - NV.z * R);
    Len := Sqrt(Dot(TV, TV));
    if Len < 1e-9 then
    begin
      // any perpendicular: across whichever axis is least like the normal
      if Abs(NV.x) < 0.9 then TV := Cross(NV, TpvVector3D.Create(1, 0, 0))
      else TV := Cross(NV, TpvVector3D.Create(0, 1, 0));
      Len := Sqrt(Dot(TV, TV));
    end;
    TV := TpvVector3D.Create(TV.x / Len, TV.y / Len, TV.z / Len);
    BV := Cross(NV, TV);
    if Dot(BV, Bit[K]) < 0 then BV := TpvVector3D.Create(-BV.x, -BV.y, -BV.z);   // mirrored UVs
    aTangents[K]   := TV;
    aBiTangents[K] := BV;
  end;
end;

end.
