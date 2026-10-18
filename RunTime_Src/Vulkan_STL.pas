unit Vulkan_STL;

{ STL (stereolithography) triangle meshes: read binary or ASCII, write either.
  Public Vulkan Package, zlib licence.

  No Vulkan, no scene: a plain mesh record and the file formats, so a tool
  that only makes or converts meshes (a marching-cubes surface, a 3D-print
  export) can use it without a device.  Vulkan_LoaderStorer_STL puts these
  meshes into a TvgScene and back.

  Also compiles with Free Pascal 3.2 (Delphi mode), for console tools and
  test runs on machines without Delphi.

  STL has no units and no axis convention.  Medical and 3D-print files are
  usually millimetres, Z up; nothing here changes the numbers. }

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$OVERFLOWCHECKS OFF} // the spatial hash wraps by design

interface

uses
{$IFDEF FPC}
  SysUtils, Classes, Math;
{$ELSE}
  System.SysUtils, System.Classes, System.Math;
{$ENDIF}

type
  EvgSTLError = class(Exception);

  TvgSTLVector = record
    X, Y, Z: Single;
  end;

  { A triangle mesh.  Indices holds three per triangle into Positions.

    Read unwelded, every triangle has its own three positions (the file's
    layout); vgWeldSTL then merges equal positions so that triangles share
    them, which smooth normals and a watertight check need.

    FaceNormals and Attributes are one per triangle, as read: STL normals
    are often zero or stale, so the writers recompute them from the
    positions.  Attributes is the binary format's 16-bit spare word (some
    programs keep a colour there); zero for ASCII.

    Assigning one mesh to another shares the arrays, as dynamic arrays do:
    the routines here replace arrays rather than editing them, so a source
    is never changed, but code that writes elements should Copy first. }
  TvgSTLMesh = record
    Name: string;
    Positions: TArray<TvgSTLVector>;
    Indices: TArray<Cardinal>;
    FaceNormals: TArray<TvgSTLVector>;
    Attributes: TArray<Word>;
    function TriangleCount: Integer;
    function VertexCount: Integer;
    procedure Clear;
    // Room for aTriangles triangles with three positions each, unwelded.
    procedure Allocate(aTriangles: Integer);
    // Sets triangle aIndex of an Allocate'd mesh (its normal from the corners).
    procedure SetTriangle(aIndex: Integer; const A, B, C: TvgSTLVector);
    // Corners of triangle aIndex.
    procedure GetTriangle(aIndex: Integer; out A, B, C: TvgSTLVector);
  end;

  TvgSTLFormat = (sfBinary, sfAscii);

function vgSTLVector(X, Y, Z: Single): TvgSTLVector;

{ Unit normal of the triangle by the right-hand rule (counter-clockwise seen
  from outside); zero for a degenerate one.  Computed in double. }
function vgSTLTriangleNormal(const A, B, C: TvgSTLVector): TvgSTLVector;

{ True if the file looks like ASCII STL.  "solid" at the start is not
  enough: many binary files begin with it in their 80-byte header, so a file
  whose size is exactly that of a binary STL with its triangle count is
  binary whatever it starts with. }
function vgSTLIsAscii(const aBytes: TBytes): Boolean;

// Reads either format, detected from the content.  Raises EvgSTLError.
function vgReadSTL(const aFileName: string): TvgSTLMesh;
function vgReadSTLStream(aStream: TStream): TvgSTLMesh;
function vgReadSTLBytes(const aBytes: TBytes): TvgSTLMesh;

{ Writes binary (the default; a fifth of the size) or ASCII.  Normals are
  computed from the positions.  The binary header carries the mesh name,
  and never starts with "solid", so readers do not take it for ASCII. }
procedure vgWriteSTL(const aMesh: TvgSTLMesh; const aFileName: string;
  aFormat: TvgSTLFormat = sfBinary);
procedure vgWriteSTLStream(const aMesh: TvgSTLMesh; aStream: TStream;
  aFormat: TvgSTLFormat = sfBinary);

{ Merges positions that are bit-for-bit equal (STL repeats each shared corner
  exactly), or within aTolerance when it is above zero, and drops triangles
  that collapse to fewer than three distinct corners.  Returns the number of
  triangles dropped. }
function vgWeldSTL(var aMesh: TvgSTLMesh; aTolerance: Single = 0): Integer;

{ Per-vertex unit normals, each the area-weighted mean of the triangles that
  use the vertex.  Meaningful after vgWeldSTL. }
function vgSTLVertexNormals(const aMesh: TvgSTLMesh): TArray<TvgSTLVector>;

procedure vgSTLBounds(const aMesh: TvgSTLMesh; out aMin, aMax: TvgSTLVector);

{ Surface area, and the signed volume enclosed (divergence theorem): right
  only for a closed mesh, positive when its triangles face outwards. }
function vgSTLArea(const aMesh: TvgSTLMesh): Double;
function vgSTLVolume(const aMesh: TvgSTLMesh): Double;

{ Counts edges of a welded mesh used by other than exactly two triangles
  (holes and non-manifold edges).  Zero for a watertight mesh. }
function vgSTLOpenEdges(const aMesh: TvgSTLMesh): Integer;

implementation

const
  HeaderSize = 80;
  FacetSize = 50;

var
  DotFormat: TFormatSettings;

function vgSTLVector(X, Y, Z: Single): TvgSTLVector;
begin
  Result.X := X; Result.Y := Y; Result.Z := Z;
end;

{ TvgSTLMesh }

function TvgSTLMesh.TriangleCount: Integer;
begin
  Result := Length(Indices) div 3;
end;

function TvgSTLMesh.VertexCount: Integer;
begin
  Result := Length(Positions);
end;

procedure TvgSTLMesh.Clear;
begin
  Name := ''; Positions := nil; Indices := nil; FaceNormals := nil; Attributes := nil;
end;

procedure TvgSTLMesh.Allocate(aTriangles: Integer);
var I: Integer;
begin
  if aTriangles < 0 then raise EvgSTLError.Create('Negative triangle count');
  SetLength(Positions, 3 * aTriangles);
  SetLength(Indices, 3 * aTriangles);
  SetLength(FaceNormals, aTriangles);
  SetLength(Attributes, aTriangles);
  for I := 0 to 3 * aTriangles - 1 do Indices[I] := Cardinal(I);
  if aTriangles > 0 then FillChar(Attributes[0], aTriangles * SizeOf(Word), 0);
end;

procedure TvgSTLMesh.SetTriangle(aIndex: Integer; const A, B, C: TvgSTLVector);
begin
  Positions[Indices[3 * aIndex]] := A;
  Positions[Indices[3 * aIndex + 1]] := B;
  Positions[Indices[3 * aIndex + 2]] := C;
  FaceNormals[aIndex] := vgSTLTriangleNormal(A, B, C);
end;

procedure TvgSTLMesh.GetTriangle(aIndex: Integer; out A, B, C: TvgSTLVector);
begin
  A := Positions[Indices[3 * aIndex]];
  B := Positions[Indices[3 * aIndex + 1]];
  C := Positions[Indices[3 * aIndex + 2]];
end;

{ Geometry }

// Widens before arithmetic (a cast, Double(X), is a reinterpretation in FPC).
function Dbl(X: Single): Double; inline;
begin
  Result := X;
end;

procedure TriangleCross(const A, B, C: TvgSTLVector; out NX, NY, NZ: Double);
var UX, UY, UZ, VX, VY, VZ: Double;
begin
  UX := Dbl(B.X) - A.X; UY := Dbl(B.Y) - A.Y; UZ := Dbl(B.Z) - A.Z;
  VX := Dbl(C.X) - A.X; VY := Dbl(C.Y) - A.Y; VZ := Dbl(C.Z) - A.Z;
  NX := UY * VZ - UZ * VY;
  NY := UZ * VX - UX * VZ;
  NZ := UX * VY - UY * VX;
end;

function vgSTLTriangleNormal(const A, B, C: TvgSTLVector): TvgSTLVector;
var NX, NY, NZ, L: Double;
begin
  TriangleCross(A, B, C, NX, NY, NZ);
  L := Sqrt(NX * NX + NY * NY + NZ * NZ);
  if L > 0 then Result := vgSTLVector(NX / L, NY / L, NZ / L)
  else Result := vgSTLVector(0, 0, 0);
end;

procedure vgSTLBounds(const aMesh: TvgSTLMesh; out aMin, aMax: TvgSTLVector);
var I: Integer; P: TvgSTLVector;
begin
  if Length(aMesh.Positions) = 0 then
  begin
    aMin := vgSTLVector(0, 0, 0); aMax := aMin; Exit;
  end;
  aMin := aMesh.Positions[0]; aMax := aMin;
  for I := 1 to High(aMesh.Positions) do
  begin
    P := aMesh.Positions[I];
    if P.X < aMin.X then aMin.X := P.X; if P.X > aMax.X then aMax.X := P.X;
    if P.Y < aMin.Y then aMin.Y := P.Y; if P.Y > aMax.Y then aMax.Y := P.Y;
    if P.Z < aMin.Z then aMin.Z := P.Z; if P.Z > aMax.Z then aMax.Z := P.Z;
  end;
end;

function vgSTLArea(const aMesh: TvgSTLMesh): Double;
var I: Integer; A, B, C: TvgSTLVector; NX, NY, NZ: Double;
begin
  Result := 0;
  for I := 0 to aMesh.TriangleCount - 1 do
  begin
    aMesh.GetTriangle(I, A, B, C);
    TriangleCross(A, B, C, NX, NY, NZ);
    Result := Result + 0.5 * Sqrt(NX * NX + NY * NY + NZ * NZ);
  end;
end;

function vgSTLVolume(const aMesh: TvgSTLMesh): Double;
var I: Integer; A, B, C: TvgSTLVector;
begin
  Result := 0;
  // Sum of tetrahedra from the origin to each triangle: A . (B x C) / 6.
  for I := 0 to aMesh.TriangleCount - 1 do
  begin
    aMesh.GetTriangle(I, A, B, C);
    Result := Result +
      (Dbl(A.X) * (Dbl(B.Y) * C.Z - Dbl(B.Z) * C.Y) +
       Dbl(A.Y) * (Dbl(B.Z) * C.X - Dbl(B.X) * C.Z) +
       Dbl(A.Z) * (Dbl(B.X) * C.Y - Dbl(B.Y) * C.X)) / 6;
  end;
end;

function vgSTLVertexNormals(const aMesh: TvgSTLMesh): TArray<TvgSTLVector>;
var
  Acc: array of array[0..2] of Double;
  I, K, V: Integer; A, B, C: TvgSTLVector; NX, NY, NZ, L: Double;
begin
  SetLength(Acc, Length(aMesh.Positions));
  for I := 0 to High(Acc) do begin Acc[I][0] := 0; Acc[I][1] := 0; Acc[I][2] := 0; end;
  for I := 0 to aMesh.TriangleCount - 1 do
  begin
    aMesh.GetTriangle(I, A, B, C);
    TriangleCross(A, B, C, NX, NY, NZ); // length is twice the area: the weight
    for K := 0 to 2 do
    begin
      V := aMesh.Indices[3 * I + K];
      Acc[V][0] := Acc[V][0] + NX; Acc[V][1] := Acc[V][1] + NY; Acc[V][2] := Acc[V][2] + NZ;
    end;
  end;
  SetLength(Result, Length(Acc));
  for I := 0 to High(Acc) do
  begin
    L := Sqrt(Sqr(Acc[I][0]) + Sqr(Acc[I][1]) + Sqr(Acc[I][2]));
    if L > 0 then Result[I] := vgSTLVector(Acc[I][0] / L, Acc[I][1] / L, Acc[I][2] / L)
    else Result[I] := vgSTLVector(0, 0, 1);
  end;
end;

{ Hashing for welding and edge counting: open addressing over arrays, so the
  unit needs no generics library and stays light on a million-triangle scan. }

function HashCell(X, Y, Z: Int64): Cardinal;
begin
  Result := Cardinal((X * 73856093) xor (Y * 19349663) xor (Z * 83492791));
end;

function TableSizeFor(aCount: Integer): Integer;
begin
  Result := 16;
  while Result < 2 * aCount + 1 do Result := Result * 2;
end;

function vgWeldSTL(var aMesh: TvgSTLMesh; aTolerance: Single): Integer;
var
  Table: array of Integer;       // into NewPositions, -1 empty
  Remap: array of Integer;
  NewPositions: TArray<TvgSTLVector>;
  NewIndices: TArray<Cardinal>;
  NewNormals: TArray<TvgSTLVector>;
  NewAttributes: TArray<Word>;
  Mask, I, Count, Slot, T, TriCount, A, B, C: Integer;
  P: TvgSTLVector;
  Inv: Double;

  function Cell(const V: TvgSTLVector; out CX, CY, CZ: Int64): Boolean;
  begin
    Result := aTolerance > 0;
    if Result then
    begin
      CX := Floor(V.X * Inv); CY := Floor(V.Y * Inv); CZ := Floor(V.Z * Inv);
    end;
  end;

  function SameAs(const U, V: TvgSTLVector): Boolean;
  begin
    if aTolerance > 0 then
      Result := (Abs(U.X - V.X) <= aTolerance) and (Abs(U.Y - V.Y) <= aTolerance) and
        (Abs(U.Z - V.Z) <= aTolerance)
    else
      Result := CompareMem(@U, @V, SizeOf(TvgSTLVector));
  end;

  function HashOf(const V: TvgSTLVector): Cardinal;
  var CX, CY, CZ: Int64; Bits: array[0..2] of Cardinal;
  begin
    if Cell(V, CX, CY, CZ) then Result := HashCell(CX, CY, CZ)
    else
    begin
      Move(V, Bits[0], 12);
      Result := HashCell(Bits[0], Bits[1], Bits[2]);
    end;
  end;

  // With a tolerance, a match can sit in a neighbouring cell.
  function FindNear(const V: TvgSTLVector): Integer;
  var CX, CY, CZ: Int64; DX, DY, DZ: Integer; S: Integer;
  begin
    Result := -1;
    if aTolerance > 0 then
    begin
      Cell(V, CX, CY, CZ);
      for DX := -1 to 1 do for DY := -1 to 1 do for DZ := -1 to 1 do
      begin
        S := HashCell(CX + DX, CY + DY, CZ + DZ) and Mask;
        while Table[S] >= 0 do
        begin
          if SameAs(NewPositions[Table[S]], V) then Exit(Table[S]);
          S := (S + 1) and Mask;
        end;
      end;
    end
    else
    begin
      S := HashOf(V) and Mask;
      while Table[S] >= 0 do
      begin
        if SameAs(NewPositions[Table[S]], V) then Exit(Table[S]);
        S := (S + 1) and Mask;
      end;
    end;
  end;

begin
  Result := 0;
  if Length(aMesh.Positions) = 0 then Exit;
  if aTolerance > 0 then Inv := 1 / aTolerance else Inv := 0;
  SetLength(Table, TableSizeFor(Length(aMesh.Positions)));
  Mask := High(Table);
  for I := 0 to Mask do Table[I] := -1;
  SetLength(Remap, Length(aMesh.Positions));
  SetLength(NewPositions, Length(aMesh.Positions));
  Count := 0;
  for I := 0 to High(aMesh.Positions) do
  begin
    P := aMesh.Positions[I];
    Remap[I] := FindNear(P);
    if Remap[I] < 0 then
    begin
      NewPositions[Count] := P; Remap[I] := Count;
      Slot := HashOf(P) and Mask;
      while Table[Slot] >= 0 do Slot := (Slot + 1) and Mask;
      Table[Slot] := Count;
      Inc(Count);
    end;
  end;
  Table := nil;
  SetLength(NewPositions, Count);

  TriCount := 0;
  SetLength(NewIndices, Length(aMesh.Indices));
  SetLength(NewNormals, aMesh.TriangleCount);
  SetLength(NewAttributes, aMesh.TriangleCount);
  for T := 0 to aMesh.TriangleCount - 1 do
  begin
    A := Remap[aMesh.Indices[3 * T]];
    B := Remap[aMesh.Indices[3 * T + 1]];
    C := Remap[aMesh.Indices[3 * T + 2]];
    if (A = B) or (B = C) or (A = C) then begin Inc(Result); Continue; end;
    NewIndices[3 * TriCount] := A; NewIndices[3 * TriCount + 1] := B; NewIndices[3 * TriCount + 2] := C;
    if T < Length(aMesh.FaceNormals) then NewNormals[TriCount] := aMesh.FaceNormals[T]
    else NewNormals[TriCount] := vgSTLTriangleNormal(NewPositions[A], NewPositions[B], NewPositions[C]);
    if T < Length(aMesh.Attributes) then NewAttributes[TriCount] := aMesh.Attributes[T]
    else NewAttributes[TriCount] := 0;
    Inc(TriCount);
  end;
  SetLength(NewIndices, 3 * TriCount);
  SetLength(NewNormals, TriCount);
  SetLength(NewAttributes, TriCount);
  aMesh.Positions := NewPositions;
  aMesh.Indices := NewIndices;
  aMesh.FaceNormals := NewNormals;
  aMesh.Attributes := NewAttributes;
end;

function vgSTLOpenEdges(const aMesh: TvgSTLMesh): Integer;
var
  Keys: array of Int64;     // (min shl 32) or max, -1 empty
  Counts: array of Integer;
  Mask, T, K, S: Integer;
  A, B, Lo, Hi: Cardinal;
  Key: Int64;
begin
  Result := 0;
  if aMesh.TriangleCount = 0 then Exit;
  SetLength(Keys, TableSizeFor(3 * aMesh.TriangleCount));
  SetLength(Counts, Length(Keys));
  Mask := High(Keys);
  for S := 0 to Mask do begin Keys[S] := -1; Counts[S] := 0; end;
  for T := 0 to aMesh.TriangleCount - 1 do
    for K := 0 to 2 do
    begin
      A := aMesh.Indices[3 * T + K];
      B := aMesh.Indices[3 * T + (K + 1) mod 3];
      if A < B then begin Lo := A; Hi := B; end else begin Lo := B; Hi := A; end;
      Key := (Int64(Lo) shl 32) or Hi;
      S := HashCell(Lo, Hi, 0) and Mask;
      while (Keys[S] <> -1) and (Keys[S] <> Key) do S := (S + 1) and Mask;
      Keys[S] := Key; Inc(Counts[S]);
    end;
  for S := 0 to Mask do
    if (Keys[S] <> -1) and (Counts[S] <> 2) then Inc(Result);
end;

{ Reading }

function vgSTLIsAscii(const aBytes: TBytes): Boolean;
var Count: Cardinal; I: Integer; S: string;
begin
  if Length(aBytes) >= HeaderSize + 4 then
  begin
    Move(aBytes[HeaderSize], Count, 4);
    if Int64(HeaderSize) + 4 + Int64(Count) * FacetSize = Length(aBytes) then Exit(False);
  end;
  // Skip leading white space, then "solid".
  I := 0;
  while (I < Length(aBytes)) and (aBytes[I] in [9, 10, 13, 32]) do Inc(I);
  if Length(aBytes) - I < 5 then Exit(False);
  S := LowerCase(string(TEncoding.ASCII.GetString(aBytes, I, 5)));
  Result := S = 'solid';
end;

function ReadBinary(const aBytes: TBytes): TvgSTLMesh;
var
  Count: Cardinal; T, K, P: Integer; Header: AnsiString; V: array[0..2] of TvgSTLVector;
begin
  Result.Clear;
  if Length(aBytes) < HeaderSize + 4 then
    raise EvgSTLError.Create('STL file is too short to be binary STL');
  Move(aBytes[HeaderSize], Count, 4);
  if Int64(HeaderSize) + 4 + Int64(Count) * FacetSize > Length(aBytes) then
    raise EvgSTLError.CreateFmt('Binary STL is truncated: header says %d triangles, file holds %d',
      [Count, (Length(aBytes) - HeaderSize - 4) div FacetSize]);
  SetLength(Header, HeaderSize);
  Move(aBytes[0], Header[1], HeaderSize);
  K := Pos(#0, string(Header));
  if K > 0 then SetLength(Header, K - 1);
  Result.Name := Trim(string(Header));
  Result.Allocate(Count);
  P := HeaderSize + 4;
  for T := 0 to Integer(Count) - 1 do
  begin
    Move(aBytes[P], Result.FaceNormals[T], 12);
    Move(aBytes[P + 12], V[0], 36);
    for K := 0 to 2 do Result.Positions[3 * T + K] := V[K];
    Move(aBytes[P + 48], Result.Attributes[T], 2);
    Inc(P, FacetSize);
  end;
end;

type
  // Token reader over the bytes of an ASCII STL.
  TAsciiReader = record
    Bytes: TBytes;
    Pos, Line: Integer;
    function Next(out aToken: string): Boolean;
    function Expect(const aWord: string): Boolean;
    function Number: Single;
    function RestOfLine: string;
  end;

function TAsciiReader.Next(out aToken: string): Boolean;
var Start: Integer;
begin
  while (Pos < Length(Bytes)) and (Bytes[Pos] in [9, 10, 13, 32]) do
  begin
    if Bytes[Pos] = 10 then Inc(Line);
    Inc(Pos);
  end;
  Result := Pos < Length(Bytes);
  if not Result then begin aToken := ''; Exit; end;
  Start := Pos;
  while (Pos < Length(Bytes)) and not (Bytes[Pos] in [9, 10, 13, 32]) do Inc(Pos);
  aToken := string(TEncoding.ASCII.GetString(Bytes, Start, Pos - Start));
end;

function TAsciiReader.Expect(const aWord: string): Boolean;
var S: string;
begin
  Result := Next(S) and SameText(S, aWord);
  if not Result then
    raise EvgSTLError.CreateFmt('ASCII STL line %d: expected "%s", found "%s"', [Line, aWord, S]);
end;

function TAsciiReader.Number: Single;
var S: string; D: Double;
begin
  if not Next(S) or not TryStrToFloat(S, D, DotFormat) then
    raise EvgSTLError.CreateFmt('ASCII STL line %d: expected a number, found "%s"', [Line, S]);
  Result := D;
end;

function TAsciiReader.RestOfLine: string;
var Start: Integer;
begin
  while (Pos < Length(Bytes)) and (Bytes[Pos] in [9, 32]) do Inc(Pos);
  Start := Pos;
  while (Pos < Length(Bytes)) and not (Bytes[Pos] in [10, 13]) do Inc(Pos);
  Result := Trim(string(TEncoding.UTF8.GetString(Bytes, Start, Pos - Start)));
end;

function ReadAscii(const aBytes: TBytes): TvgSTLMesh;
var
  R: TAsciiReader;
  Tok: string;
  Corners: array of TvgSTLVector;
  Normal: TvgSTLVector;
  Positions: TArray<TvgSTLVector>;
  Normals: TArray<TvgSTLVector>;
  NP, NT, K, I: Integer;

  procedure AddTriangle(const A, B, C: TvgSTLVector);
  begin
    if NP + 3 > Length(Positions) then SetLength(Positions, 2 * Length(Positions) + 48);
    if NT + 1 > Length(Normals) then SetLength(Normals, 2 * Length(Normals) + 16);
    Positions[NP] := A; Positions[NP + 1] := B; Positions[NP + 2] := C;
    Normals[NT] := Normal;
    Inc(NP, 3); Inc(NT);
  end;

begin
  Result.Clear;
  R.Bytes := aBytes; R.Pos := 0; R.Line := 1;
  NP := 0; NT := 0;
  R.Expect('solid');
  Result.Name := R.RestOfLine;
  // Several solids may follow one another; they are read as one mesh.
  while R.Next(Tok) do
  begin
    if SameText(Tok, 'facet') then
    begin
      R.Expect('normal');
      Normal.X := R.Number; Normal.Y := R.Number; Normal.Z := R.Number;
      R.Expect('outer'); R.Expect('loop');
      SetLength(Corners, 0);
      while R.Next(Tok) and SameText(Tok, 'vertex') do
      begin
        K := Length(Corners); SetLength(Corners, K + 1);
        Corners[K].X := R.Number; Corners[K].Y := R.Number; Corners[K].Z := R.Number;
      end;
      if not SameText(Tok, 'endloop') then
        raise EvgSTLError.CreateFmt('ASCII STL line %d: expected "endloop", found "%s"', [R.Line, Tok]);
      if Length(Corners) < 3 then
        raise EvgSTLError.CreateFmt('ASCII STL line %d: a facet needs three vertices', [R.Line]);
      // Strictly three; a few writers emit polygons, which fan out.
      for I := 1 to High(Corners) - 1 do AddTriangle(Corners[0], Corners[I], Corners[I + 1]);
      R.Expect('endfacet');
    end
    else if SameText(Tok, 'endsolid') then R.RestOfLine
    else if SameText(Tok, 'solid') then R.RestOfLine
    else
      raise EvgSTLError.CreateFmt('ASCII STL line %d: unexpected "%s"', [R.Line, Tok]);
  end;
  Result.Allocate(NT);
  if NT > 0 then
  begin
    Move(Positions[0], Result.Positions[0], NP * SizeOf(TvgSTLVector));
    Move(Normals[0], Result.FaceNormals[0], NT * SizeOf(TvgSTLVector));
  end;
end;

function vgReadSTLBytes(const aBytes: TBytes): TvgSTLMesh;
begin
  if vgSTLIsAscii(aBytes) then Result := ReadAscii(aBytes)
  else Result := ReadBinary(aBytes);
end;

function vgReadSTLStream(aStream: TStream): TvgSTLMesh;
var Bytes: TBytes; N: Int64;
begin
  N := aStream.Size - aStream.Position;
  if N > MaxInt then raise EvgSTLError.Create('STL file is too large');
  SetLength(Bytes, N);
  if N > 0 then aStream.ReadBuffer(Bytes[0], N);
  Result := vgReadSTLBytes(Bytes);
end;

function vgReadSTL(const aFileName: string): TvgSTLMesh;
var S: TFileStream;
begin
  S := TFileStream.Create(aFileName, fmOpenRead or fmShareDenyWrite);
  try
    Result := vgReadSTLStream(S);
  finally S.Free; end;
end;

{ Writing }

procedure WriteBinary(const aMesh: TvgSTLMesh; aStream: TStream);
const BufferFacets = 2048;
var
  Header: array[0..HeaderSize - 1] of Byte;
  Name: AnsiString;
  Buffer: TBytes;
  Count: Cardinal;
  T, InBuffer, P: Integer;
  A, B, C, N: TvgSTLVector;
  Attr: Word;
begin
  FillChar(Header, SizeOf(Header), 0);
  Name := AnsiString(aMesh.Name);
  if Name = '' then Name := 'Vulkan_Package STL';
  // Readers that sniff "solid" would take the file for ASCII.
  if SameText(Copy(string(Name), 1, 5), 'solid') then Name := 'mesh ' + Name;
  if Length(Name) > HeaderSize then SetLength(Name, HeaderSize);
  Move(Name[1], Header[0], Length(Name));
  aStream.WriteBuffer(Header, HeaderSize);
  Count := aMesh.TriangleCount;
  aStream.WriteBuffer(Count, 4);
  SetLength(Buffer, BufferFacets * FacetSize);
  InBuffer := 0;
  for T := 0 to aMesh.TriangleCount - 1 do
  begin
    aMesh.GetTriangle(T, A, B, C);
    N := vgSTLTriangleNormal(A, B, C);
    if T < Length(aMesh.Attributes) then Attr := aMesh.Attributes[T] else Attr := 0;
    P := InBuffer * FacetSize;
    Move(N, Buffer[P], 12);
    Move(A, Buffer[P + 12], 12);
    Move(B, Buffer[P + 24], 12);
    Move(C, Buffer[P + 36], 12);
    Move(Attr, Buffer[P + 48], 2);
    Inc(InBuffer);
    if InBuffer = BufferFacets then
    begin
      aStream.WriteBuffer(Buffer[0], InBuffer * FacetSize); InBuffer := 0;
    end;
  end;
  if InBuffer > 0 then aStream.WriteBuffer(Buffer[0], InBuffer * FacetSize);
end;

procedure WriteAscii(const aMesh: TvgSTLMesh; aStream: TStream);
var
  SB: TStringBuilder;
  Name: string;
  T, K: Integer;
  V: array[0..2] of TvgSTLVector;
  N: TvgSTLVector;

  procedure Flush;
  var Bytes: TBytes;
  begin
    Bytes := TEncoding.UTF8.GetBytes(SB.ToString);
    if Length(Bytes) > 0 then aStream.WriteBuffer(Bytes[0], Length(Bytes));
    SB.Clear;
  end;

  function F(X: Single): string;
  begin
    Result := FloatToStrF(X, ffExponent, 9, 2, DotFormat); // round-trips a Single
  end;

begin
  Name := StringReplace(StringReplace(aMesh.Name, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
  SB := TStringBuilder.Create;
  try
    SB.Append('solid ').Append(Name).Append(#10);
    for T := 0 to aMesh.TriangleCount - 1 do
    begin
      aMesh.GetTriangle(T, V[0], V[1], V[2]);
      N := vgSTLTriangleNormal(V[0], V[1], V[2]);
      SB.Append('  facet normal ').Append(F(N.X)).Append(' ').Append(F(N.Y)).Append(' ')
        .Append(F(N.Z)).Append(#10).Append('    outer loop').Append(#10);
      for K := 0 to 2 do
        SB.Append('      vertex ').Append(F(V[K].X)).Append(' ').Append(F(V[K].Y)).Append(' ')
          .Append(F(V[K].Z)).Append(#10);
      SB.Append('    endloop').Append(#10).Append('  endfacet').Append(#10);
      if SB.Length > 1 shl 20 then Flush;
    end;
    SB.Append('endsolid ').Append(Name).Append(#10);
    Flush;
  finally SB.Free; end;
end;

procedure vgWriteSTLStream(const aMesh: TvgSTLMesh; aStream: TStream; aFormat: TvgSTLFormat);
begin
  if Length(aMesh.Indices) mod 3 <> 0 then
    raise EvgSTLError.Create('Mesh index count is not a multiple of three');
  if aFormat = sfAscii then WriteAscii(aMesh, aStream) else WriteBinary(aMesh, aStream);
end;

procedure vgWriteSTL(const aMesh: TvgSTLMesh; const aFileName: string; aFormat: TvgSTLFormat);
var S: TFileStream;
begin
  S := TFileStream.Create(aFileName, fmCreate);
  try
    vgWriteSTLStream(aMesh, S, aFormat);
  finally S.Free; end;
end;

initialization
{$IFDEF FPC}
  DotFormat := DefaultFormatSettings;
{$ELSE}
  DotFormat := TFormatSettings.Create('en-US');
{$ENDIF}
  DotFormat.DecimalSeparator := '.';
  DotFormat.ThousandSeparator := ',';
end.
