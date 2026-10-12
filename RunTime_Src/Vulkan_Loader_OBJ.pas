unit Vulkan_Loader_OBJ;

{ Load-only Wavefront polygon/line/point OBJ and MTL importer.
  Public Vulkan Package, zlib licence. Material lighting data is retained;
  this unit does not create lights or implement a lighting model. }

interface

uses
  System.SysUtils, System.Classes, PasVulkan.Math, Vulkan_Components,
  Vulkan_Components_Scene_Renderer;

type
  EvgOBJError = class(Exception);

  TvgOBJTextureMap = record
    Kind, FileName, Options: string;
    Offset, Scale, Turbulence: TpvVector3;
    Clamp, BlendU, BlendV: Boolean;
    BumpMultiplier, Brightness, Contrast: Single;
    Channel, Projection, ColorSpace: string;
    Resolution: Integer;
    // Binding in the owning store's ObjectStoreRes, after texture loading.
    Binding: Integer;
  end;

  TvgOBJMaterial = record
    Name, LibraryFile: string;
    Ambient, Diffuse, Specular, Emissive, Transmission: TpvVector3;
    Shininess, OpticalDensity, Opacity, Sharpness: Single;
    IlluminationModel: Integer;
    Halo: Boolean;
    Roughness, Metallic, Sheen, Clearcoat, ClearcoatRoughness: Single;
    Anisotropy, AnisotropyRotation: Single;
    Maps: TArray<TvgOBJTextureMap>;
    // Unrecognised material statements survive for future shading support.
    ExtraStatements: TArray<string>;
  end;

  // Scene-owned data: remains available even when vgLoadSceneFile frees its
  // temporary loader. One store per contiguous object/group/material/topology.
  TvgOBJObjectStore = class(TvgObjectStore)
  private
    fMaterial: TvgOBJMaterial;
    fObjectName, fGroupNames: string;
  protected
    procedure ConfigureGraphicPipeline(GP: TvgGraphicPipeline); override;
  public
    property Material: TvgOBJMaterial read fMaterial;
    property ObjectName: string read fObjectName;
    property GroupNames: string read fGroupNames;
  end;

  TvgSceneLoader_OBJ = class(TvgSceneLoaderStorer)
  private
    fFileName: string;
    procedure LoadTextures(aStore: TvgOBJObjectStore);
  public
    procedure LoadScene; override;
    procedure StoreScene; override;
  published
    property FileName: string read fFileName write fFileName;
  end;

implementation

uses
  System.Math, System.IOUtils, System.Generics.Collections,
  PasVulkan.Math.Double, PasVulkan.Framework,
  PasVulkan.Image.TGA,
  Vulkan_Components_DataStore,
  Vulkan_Components_Descriptors, Vulkan_Components_TextureInspector,
  Vulkan_Components_Lookups, Vulkan_SceneLoaders;

type
  TCorner = record
    P, T, N: Integer;
  end;
  TPrimitive = class
    Corners: TArray<TCorner>;
    Triangles: TArray<Integer>; // indices into Corners
    ObjectName, Groups, MaterialName, Smooth: string;
    Kind: TvgPrimitiveTopology;
    Normal: TpvVector3D; // unnormalised Newell normal, for area weighting
    LineNo: Integer;
  end;
  TMaterial = class
    Data: TvgOBJMaterial;
  end;
  TOBJReader = class
    FileName: string;
    LineNo: Integer;
    FS: TFormatSettings;
    Positions, Colors, Normals, UVs: TList<TpvVector3>;
    HasColors: TList<Boolean>;
    Primitives: TObjectList<TPrimitive>;
    Materials: TObjectDictionary<string, TMaterial>;
    Libraries: TList<string>;
    SmoothNormals: TDictionary<string, TpvVector3D>;
    constructor Create;
    destructor Destroy; override;
    procedure Error(const S: string);
    function Number(const S: string): Double;
    function IntegerValue(const S: string): Integer;
    function Tokens(const S: string): TArray<string>;
    function Lines(const Path: string): TArray<string>;
    function Index(const S: string; Count: Integer): Integer;
    function Corner(const S: string): TCorner;
    procedure ReadOBJ(const Path: string);
    procedure ReadMTL(const Path: string);
    function ReadMap(const W: TArray<string>): TvgOBJTextureMap;
    procedure Triangulate(P: TPrimitive);
    procedure BuildNormals;
    function BuildStores: TObjectList<TvgOBJObjectStore>;
  end;

procedure TvgOBJObjectStore.ConfigureGraphicPipeline(GP: TvgGraphicPipeline);
var Map: TvgOBJTextureMap;
  procedure SetFloat(ID: Integer; const Name: string; Value: Single);
  var I: Integer; Item: TvgShaderSpecialisationItem;
  begin
    Item := nil;
    for I := 0 to GP.FragmentS.SpecialConst.Count - 1 do
      if GP.FragmentS.SpecialConst[I].ConstantID = ID then Item := GP.FragmentS.SpecialConst[I];
    if Item = nil then Item := GP.FragmentS.SpecialConst.Add;
    Item.Name := Name; Item.ConstantID := ID; Item.SpecType := TS_SINGLE;
    // The shared specialization setter parses using the current locale.
    Item.SpecTValue := FloatToStr(Value);
  end;
begin
  // Shader names (OBJ / OBJTexture and their Double, Pick and PickImage
  // variants) come from inherited: BaseVertName, BaseFragName and
  // PrebuiltShaderVariants are set when the store is built.
  inherited;
  for Map in fMaterial.Maps do
    if Map.Kind = 'map_Kd' then
    begin
      SetFloat(3, 'UV_SCALE_U', Map.Scale.x); SetFloat(4, 'UV_SCALE_V', Map.Scale.y);
      SetFloat(5, 'UV_OFFSET_U', Map.Offset.x); SetFloat(6, 'UV_OFFSET_V', Map.Offset.y);
      SetFloat(7, 'MAP_BRIGHTNESS', Map.Brightness); SetFloat(8, 'MAP_CONTRAST', Map.Contrast);
    end;
end;

function DefaultMaterial: TvgOBJMaterial;
begin
  Result := Default(TvgOBJMaterial);
  Result.Diffuse := TpvVector3.Create(0.8, 0.8, 0.8);
  Result.Transmission := TpvVector3.Create(1, 1, 1);
  Result.Opacity := 1;
  Result.OpticalDensity := 1;
  Result.IlluminationModel := 2;
end;

function Join(const W: TArray<string>; First: Integer): string;
var I: Integer;
begin
  Result := '';
  for I := First to High(W) do
  begin
    if I > First then Result := Result + ' ';
    Result := Result + W[I];
  end;
end;

function UnitNormal(const V: TpvVector3D): TpvVector3;
var L: Double;
begin
  L := Sqrt(V.x * V.x + V.y * V.y + V.z * V.z);
  if L > 0 then Result := TpvVector3.Create(V.x / L, V.y / L, V.z / L)
  else Result := TpvVector3.Create(0, 0, 1);
end;

function SmoothKey(P: TPrimitive; Vertex: Integer): string;
begin
  // Length-prefix names to avoid collisions when names contain separators.
  Result := IntToStr(Length(P.ObjectName)) + ':' + P.ObjectName + ':' +
    IntToStr(Length(P.Smooth)) + ':' + P.Smooth + ':' + IntToStr(Vertex);
end;

constructor TOBJReader.Create;
begin
  inherited;
  FS := TFormatSettings.Create;
  FS.DecimalSeparator := '.';
  FS.ThousandSeparator := #0;
  Positions := TList<TpvVector3>.Create;
  Colors := TList<TpvVector3>.Create;
  HasColors := TList<Boolean>.Create;
  Normals := TList<TpvVector3>.Create;
  UVs := TList<TpvVector3>.Create;
  Primitives := TObjectList<TPrimitive>.Create;
  Materials := TObjectDictionary<string, TMaterial>.Create([doOwnsValues]);
  Libraries := TList<string>.Create;
  SmoothNormals := TDictionary<string, TpvVector3D>.Create;
end;

destructor TOBJReader.Destroy;
begin
  SmoothNormals.Free;
  Libraries.Free;
  Materials.Free;
  Primitives.Free;
  UVs.Free;
  Normals.Free;
  HasColors.Free;
  Colors.Free;
  Positions.Free;
  inherited;
end;

procedure TOBJReader.Error(const S: string);
begin
  raise EvgOBJError.CreateFmt('%s, line %d: %s', [FileName, LineNo, S]);
end;

function TOBJReader.Number(const S: string): Double;
begin
  if not TryStrToFloat(S, Result, FS) then Error('Invalid number: ' + S);
  if IsNan(Result) or IsInfinite(Result) or (Abs(Result) > MaxSingle) then
    Error('Number outside finite single-precision range: ' + S);
end;

function TOBJReader.IntegerValue(const S: string): Integer;
begin
  if not TryStrToInt(S, Result) then Error('Invalid integer: ' + S);
end;

function TOBJReader.Tokens(const S: string): TArray<string>;
var I: Integer; Token: string; Quoted, Started: Boolean; List: TList<string>;
begin
  List := TList<string>.Create;
  try
    Token := ''; Quoted := False; Started := False;
    for I := 1 to Length(S) do
    begin
      if S[I] = '"' then begin Quoted := not Quoted; Started := True; end
      else if (S[I] = '#') and not Quoted then Break
      else if CharInSet(S[I], [' ', #9]) and not Quoted then
      begin
        if Started then List.Add(Token);
        Token := ''; Started := False;
      end
      else begin Token := Token + S[I]; Started := True; end;
    end;
    if Quoted then Error('Unterminated quoted name');
    if Started then List.Add(Token);
    Result := List.ToArray;
  finally List.Free; end;
end;

function TOBJReader.Lines(const Path: string): TArray<string>;
var L: TStringList; I, First: Integer; S: string;
begin
  FileName := Path;
  L := TStringList.Create;
  try
    L.LoadFromFile(Path, TEncoding.UTF8);
    Result := L.ToStringArray;
    // Join backslash continuations, keeping physical line numbers stable.
    First := -1;
    for I := 0 to High(Result) do
    begin
      S := TrimRight(Result[I]);
      if First < 0 then First := I;
      if (S <> '') and (S[Length(S)] = '\') then
      begin
        Delete(S, Length(S), 1);
        if I = First then Result[First] := S + ' '
        else begin Result[First] := Result[First] + S + ' '; Result[I] := ''; end;
        if I = High(Result) then begin LineNo := I + 1; Error('Unfinished continuation'); end;
      end
      else
      begin
        if I <> First then begin Result[First] := Result[First] + S; Result[I] := ''; end;
        First := -1;
      end;
    end;
  finally L.Free; end;
end;

function TOBJReader.Index(const S: string; Count: Integer): Integer;
begin
  Result := IntegerValue(S);
  if Result = 0 then Error('OBJ indices must not be zero');
  if Result < 0 then Result := Count + Result else Dec(Result);
  if (Result < 0) or (Result >= Count) then Error('Index out of range: ' + S);
end;

function TOBJReader.Corner(const S: string): TCorner;
var W: TArray<string>;
begin
  Result.T := -1; Result.N := -1;
  W := S.Split(['/']);
  if (Length(W) < 1) or (Length(W) > 3) then Error('Invalid face corner: ' + S);
  Result.P := Index(W[0], Positions.Count);
  if Length(W) >= 2 then
  begin
    if W[1] <> '' then Result.T := Index(W[1], UVs.Count)
    else if Length(W) = 2 then Error('Missing texture index: ' + S);
  end;
  if Length(W) = 3 then Result.N := Index(W[2], Normals.Count);
end;

procedure TOBJReader.ReadOBJ(const Path: string);
var
  Text, W: TArray<string>;
  I, J: Integer;
  V, C: TpvVector3;
  X, Y, Z, Weight: Double;
  ObjectName, Groups, MaterialName, Smooth, Lib: string;
  P: TPrimitive;
begin
  Text := Lines(Path);
  for I := 0 to High(Text) do
  begin
    LineNo := I + 1;
    W := Tokens(Text[I]);
    if Length(W) = 0 then Continue;
    if W[0] = 'v' then
    begin
      if not (Length(W) in [4, 5, 7]) then Error('Expected v x y z [w] or v x y z r g b');
      X := Number(W[1]); Y := Number(W[2]); Z := Number(W[3]); Weight := 1;
      if Length(W) = 5 then Weight := Number(W[4]);
      if Weight = 0 then Error('Vertex weight must not be zero');
      X := X / Weight; Y := Y / Weight; Z := Z / Weight;
      if (Abs(X) > MaxSingle) or (Abs(Y) > MaxSingle) or (Abs(Z) > MaxSingle) then
        Error('Weighted vertex outside single-precision range');
      Positions.Add(TpvVector3.Create(X, Y, Z));
      C := TpvVector3.Create(1, 1, 1);
      if Length(W) = 7 then
        C := TpvVector3.Create(EnsureRange(Number(W[4]), 0, 1),
          EnsureRange(Number(W[5]), 0, 1), EnsureRange(Number(W[6]), 0, 1));
      Colors.Add(C); HasColors.Add(Length(W) = 7);
    end
    else if (W[0] = 'vn') or (W[0] = 'vt') then
    begin
      if ((W[0] = 'vn') and (Length(W) <> 4)) or
         ((W[0] = 'vt') and not (Length(W) in [2, 3, 4])) then
        Error('Invalid ' + W[0] + ' coordinate');
      V := TpvVector3.Create(Number(W[1]), 0, 0);
      if Length(W) > 2 then V.y := Number(W[2]);
      if Length(W) > 3 then V.z := Number(W[3]);
      if W[0] = 'vn' then Normals.Add(V) else UVs.Add(V);
    end
    else if (W[0] = 'f') or (W[0] = 'l') or (W[0] = 'p') then
    begin
      if (Length(W) < 2) or ((W[0] = 'f') and (Length(W) < 4)) or
         ((W[0] = 'l') and (Length(W) < 3)) then Error('Too few primitive vertices');
      P := TPrimitive.Create;
      Primitives.Add(P);
      P.ObjectName := ObjectName; P.Groups := Groups; P.MaterialName := MaterialName;
      P.Smooth := Smooth; P.LineNo := LineNo;
      P.Kind := TRIANGLE_LIST;
      if W[0] = 'l' then P.Kind := LINE_LIST;
      if W[0] = 'p' then P.Kind := POINT_LIST;
      SetLength(P.Corners, Length(W) - 1);
      for J := 1 to High(W) do P.Corners[J - 1] := Corner(W[J]);
      if P.Kind = TRIANGLE_LIST then Triangulate(P);
    end
    else if W[0] = 'o' then ObjectName := Join(W, 1)
    else if W[0] = 'g' then Groups := Join(W, 1)
    else if W[0] = 'usemtl' then MaterialName := Join(W, 1)
    else if W[0] = 's' then
    begin
      if Length(W) <> 2 then Error('Expected smoothing group or off');
      Smooth := W[1];
      if (Smooth = 'off') or (Smooth = '0') then Smooth := '';
      if Smooth = 'on' then Smooth := '1';
    end
    else if W[0] = 'mtllib' then
    begin
      if Length(W) < 2 then Error('Missing material library name');
      // Accept an unquoted filename with spaces when the whole path exists.
      Lib := ExpandFileName(ExtractFilePath(Path) + Join(W, 1));
      if FileExists(Lib) then Libraries.Add(Lib)
      else for J := 1 to High(W) do
        Libraries.Add(TPath.GetFullPath(TPath.Combine(ExtractFilePath(Path), W[J])));
    end
    else if (W[0] = 'vp') or (W[0] = 'curv') or (W[0] = 'curv2') or
      (W[0] = 'surf') or (W[0] = 'cstype') or (W[0] = 'call') then
      Error('Unsupported free-form/external geometry statement: ' + W[0]);
  end;
  if Primitives.Count = 0 then Error('OBJ file contains no faces, lines or points');
  // OBJ files are often distributed without their companion libraries.
  // Available libraries still load; absent ones leave default materials.
  for Lib in Libraries do
    if FileExists(Lib) then ReadMTL(Lib);
  FileName := Path;
  BuildNormals;
end;

procedure TOBJReader.Triangulate(P: TPrimitive);
var
  V, NextV: TpvVector3;
  XY: TArray<TpvVector2D>;
  Remaining, Tri: TList<Integer>;
  I, J, A, B, C, Q, Axis: Integer;
  Area, Sign, Eps, Extent: Double;
  Ear, Inside: Boolean;
  function Cross2(U, V, W: Integer): Double;
  begin
    Result := (XY[V].x - XY[U].x) * (XY[W].y - XY[U].y) -
              (XY[V].y - XY[U].y) * (XY[W].x - XY[U].x);
  end;
begin
  P.Normal := TpvVector3D.Create(0, 0, 0);
  for I := 0 to High(P.Corners) do
  begin
    V := Positions[P.Corners[I].P];
    NextV := Positions[P.Corners[(I + 1) mod Length(P.Corners)].P];
    P.Normal.x := P.Normal.x + (Double(V.y) - NextV.y) * (Double(V.z) + NextV.z);
    P.Normal.y := P.Normal.y + (Double(V.z) - NextV.z) * (Double(V.x) + NextV.x);
    P.Normal.z := P.Normal.z + (Double(V.x) - NextV.x) * (Double(V.y) + NextV.y);
  end;
  // Preserve degenerate triangles (common at exported sphere poles).
  if Length(P.Corners) = 3 then begin P.Triangles := TArray<Integer>.Create(0, 1, 2); Exit; end;
  Axis := 2;
  if (Abs(P.Normal.x) > Abs(P.Normal.y)) and (Abs(P.Normal.x) > Abs(P.Normal.z)) then Axis := 0
  else if Abs(P.Normal.y) > Abs(P.Normal.z) then Axis := 1;
  SetLength(XY, Length(P.Corners));
  for I := 0 to High(XY) do
  begin
    V := Positions[P.Corners[I].P];
    case Axis of
      0: XY[I] := TpvVector2D.Create(V.y, V.z);
      1: XY[I] := TpvVector2D.Create(V.x, V.z);
      2: XY[I] := TpvVector2D.Create(V.x, V.y);
    end;
  end;
  Area := 0; Extent := 0;
  for I := 1 to High(XY) - 1 do Area := Area + Cross2(0, I, I + 1);
  for I := 1 to High(XY) do
    Extent := Max(Extent, Max(Abs(XY[I].x - XY[0].x), Abs(XY[I].y - XY[0].y)));
  Eps := Extent * Extent * 1e-12;
  if Abs(Area) <= Eps then Error('Degenerate polygon');
  Sign := 1; if Area < 0 then Sign := -1;
  Remaining := TList<Integer>.Create;
  Tri := TList<Integer>.Create;
  try
    for I := 0 to High(XY) do Remaining.Add(I);
    while Remaining.Count > 3 do
    begin
      Ear := False;
      // Start at corner 1 so a convex polygon retains the old fan order.
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
      if not Ear then Error('Cannot triangulate polygon (duplicate or intersecting edges)');
    end;
    Tri.Add(Remaining[0]); Tri.Add(Remaining[1]); Tri.Add(Remaining[2]);
    P.Triangles := Tri.ToArray;
  finally Tri.Free; Remaining.Free; end;
end;

function TOBJReader.ReadMap(const W: TArray<string>): TvgOBJTextureMap;
var I, J, Count: Integer; Option: string; Values: array[0..2] of Single; D: Double;
  function Next: string;
  begin
    if I >= Length(W) then Error('Missing texture option value');
    Result := W[I]; Inc(I);
  end;
  function Toggle: Boolean;
  var S: string;
  begin
    S := Next;
    if (S <> 'on') and (S <> 'off') then Error('Expected on/off texture option');
    Result := S = 'on';
  end;
begin
  Result := Default(TvgOBJTextureMap);
  Result.Kind := W[0]; Result.Binding := -1;
  Result.Scale := TpvVector3.Create(1, 1, 1);
  Result.BumpMultiplier := 1; Result.Contrast := 1;
  Result.BlendU := True; Result.BlendV := True;
  I := 1;
  while (I < Length(W)) and (W[I] <> '') and (W[I][1] = '-') do
  begin
    Option := Next;
    if (Option = '-o') or (Option = '-s') or (Option = '-t') then
    begin
      for J := 0 to 2 do begin Values[J] := 0; if Option = '-s' then Values[J] := 1; end;
      Count := 0;
      while (I < Length(W)) and (Count < 3) and TryStrToFloat(W[I], D, FS) do
      begin Values[Count] := Number(Next); Inc(Count); end;
      if Count = 0 then Error('Missing vector for ' + Option);
      if Option = '-o' then Result.Offset := TpvVector3.Create(Values[0], Values[1], Values[2]);
      if Option = '-s' then Result.Scale := TpvVector3.Create(Values[0], Values[1], Values[2]);
      if Option = '-t' then Result.Turbulence := TpvVector3.Create(Values[0], Values[1], Values[2]);
    end
    else if Option = '-clamp' then Result.Clamp := Toggle
    else if Option = '-blendu' then Result.BlendU := Toggle
    else if Option = '-blendv' then Result.BlendV := Toggle
    else if Option = '-bm' then Result.BumpMultiplier := Number(Next)
    else if Option = '-mm' then begin Result.Brightness := Number(Next); Result.Contrast := Number(Next); end
    else if Option = '-imfchan' then Result.Channel := Next
    else if Option = '-type' then Result.Projection := Next
    else if Option = '-colorspace' then Result.ColorSpace := Next
    else if Option = '-texres' then Result.Resolution := IntegerValue(Next)
    else if (Option = '-boost') then D := Number(Next)
    else if Option = '-cc' then Toggle
    else Error('Unsupported texture option: ' + Option);
  end;
  for J := 1 to I - 1 do Result.Options := Result.Options + W[J] + ' ';
  if I >= Length(W) then Error('Missing texture filename');
  Result.FileName := TPath.GetFullPath(TPath.Combine(ExtractFilePath(FileName), Join(W, I)));
end;

procedure TOBJReader.ReadMTL(const Path: string);
var
  Text, W: TArray<string>;
  I, J, N, Start: Integer;
  M: TMaterial;
  V: TpvVector3;
  X, Y, Z: Double;
  Map: TvgOBJTextureMap;
  Key: string;
  procedure Arity(Count: Integer);
  begin if Length(W) <> Count then Error('Invalid ' + W[0] + ' value count'); end;
begin
  Text := Lines(Path); M := nil;
  for I := 0 to High(Text) do
  begin
    LineNo := I + 1; W := Tokens(Text[I]);
    if Length(W) = 0 then Continue;
    Key := W[0];
    if Key = 'newmtl' then
    begin
      if Length(W) < 2 then Error('Missing material name');
      M := TMaterial.Create; M.Data := DefaultMaterial;
      M.Data.Name := Join(W, 1); M.Data.LibraryFile := Path;
      Materials.AddOrSetValue(M.Data.Name, M);
      Continue;
    end;
    if M = nil then Error('Material property before newmtl');
    if (Key = 'Ka') or (Key = 'Kd') or (Key = 'Ks') or (Key = 'Ke') or (Key = 'Tf') then
    begin
      Start := 1;
      if (Length(W) > 1) and (W[1] = 'xyz') then Start := 2;
      if not ((Length(W) = Start + 1) or (Length(W) = Start + 3)) then
        Error('Expected RGB or XYZ material colour');
      X := Number(W[Start]); Y := X; Z := X;
      if Length(W) = Start + 3 then begin Y := Number(W[Start + 1]); Z := Number(W[Start + 2]); end;
      if Start = 2 then
        V := TpvVector3.Create(3.2406 * X - 1.5372 * Y - 0.4986 * Z,
          -0.9689 * X + 1.8758 * Y + 0.0415 * Z, 0.0557 * X - 0.2040 * Y + 1.0570 * Z)
      else V := TpvVector3.Create(X, Y, Z);
      if Key = 'Ka' then M.Data.Ambient := V;
      if Key = 'Kd' then M.Data.Diffuse := V;
      if Key = 'Ks' then M.Data.Specular := V;
      if Key = 'Ke' then M.Data.Emissive := V;
      if Key = 'Tf' then M.Data.Transmission := V;
    end
    else if (Copy(Key, 1, 4) = 'map_') or (Key = 'bump') or (Key = 'disp') or
      (Key = 'decal') or (Key = 'refl') or (Key = 'norm') then
    begin
      Map := ReadMap(W); N := Length(M.Data.Maps);
      for J := 0 to High(M.Data.Maps) do
        if (M.Data.Maps[J].Kind = Map.Kind) and (M.Data.Maps[J].Projection = Map.Projection) then
        begin N := J; Break; end;
      if N = Length(M.Data.Maps) then SetLength(M.Data.Maps, N + 1);
      M.Data.Maps[N] := Map;
    end
    else if (Key = 'd') or (Key = 'Tr') then
    begin
      Start := 1;
      M.Data.Halo := False;
      if (Length(W) > 1) and (W[1] = '-halo') and (Key = 'd') then
      begin Start := 2; M.Data.Halo := True; end;
      Arity(Start + 1); X := Number(W[Start]);
      if Key = 'Tr' then X := 1 - X;
      M.Data.Opacity := EnsureRange(X, 0, 1);
    end
    else if Key = 'illum' then begin Arity(2); M.Data.IlluminationModel := IntegerValue(W[1]); end
    else if (Key = 'Ns') or (Key = 'Ni') or (Key = 'sharpness') or (Key = 'Pr') or
      (Key = 'Pm') or (Key = 'Ps') or (Key = 'Pc') or (Key = 'Pcr') or
      (Key = 'aniso') or (Key = 'anisor') then
    begin
      Arity(2); X := Number(W[1]);
      if Key = 'Ns' then M.Data.Shininess := X;
      if Key = 'Ni' then M.Data.OpticalDensity := X;
      if Key = 'sharpness' then M.Data.Sharpness := X;
      if Key = 'Pr' then M.Data.Roughness := X;
      if Key = 'Pm' then M.Data.Metallic := X;
      if Key = 'Ps' then M.Data.Sheen := X;
      if Key = 'Pc' then M.Data.Clearcoat := X;
      if Key = 'Pcr' then M.Data.ClearcoatRoughness := X;
      if Key = 'aniso' then M.Data.Anisotropy := X;
      if Key = 'anisor' then M.Data.AnisotropyRotation := X;
    end
    else
    begin
      N := Length(M.Data.ExtraStatements); SetLength(M.Data.ExtraStatements, N + 1);
      M.Data.ExtraStatements[N] := Text[I];
    end;
  end;
end;

procedure TOBJReader.BuildNormals;
var P: TPrimitive; C: TCorner; Key: string; V: TpvVector3D;
begin
  for P in Primitives do
    if (P.Kind = TRIANGLE_LIST) and (P.Smooth <> '') then
      for C in P.Corners do
      begin
        Key := SmoothKey(P, C.P);
        if not SmoothNormals.TryGetValue(Key, V) then V := TpvVector3D.Create(0, 0, 0);
        SmoothNormals.AddOrSetValue(Key, V + P.Normal);
      end;
end;

function TOBJReader.BuildStores: TObjectList<TvgOBJObjectStore>;
var
  P, Prev: TPrimitive;
  Store: TvgOBJObjectStore;
  Obj: TvgObject;
  M: TMaterial;
  Vertices: TDictionary<string, Integer>;
  C: TCorner;
  Position, Color, Normal, UV: TpvVector3;
  Key: string;
  I, J, FaceID, VertexIndex: Integer;
  HasDiffuseMap: Boolean;
  Map: TvgOBJTextureMap;
  procedure AddCorner(CornerIndex: Integer);
  begin
    C := P.Corners[CornerIndex];
    Key := IntToStr(C.P) + '/' + IntToStr(C.T) + '/' + IntToStr(C.N);
    if (C.N < 0) and (P.Kind = TRIANGLE_LIST) then
      if P.Smooth <> '' then Key := Key + '/s' + P.Smooth
      else Key := Key + '/f' + IntToStr(FaceID);
    if not Vertices.TryGetValue(Key, VertexIndex) then
    begin
      Position := Positions[C.P]; Color := Store.fMaterial.Diffuse;
      if HasColors[C.P] then
      begin
        // Explicit vertex colours keep their original brightness when there
        // is no material, otherwise they modulate the material diffuse colour.
        if Store.fMaterial.LibraryFile = '' then Color := Colors[C.P]
        else Color := TpvVector3.Create(Color.x * Colors[C.P].x,
          Color.y * Colors[C.P].y, Color.z * Colors[C.P].z);
      end;
      Normal := TpvVector3.Create(0, 0, 1);
      if C.N >= 0 then Normal := Normals[C.N]
      else if P.Kind = TRIANGLE_LIST then
        if P.Smooth <> '' then Normal := UnitNormal(SmoothNormals[SmoothKey(P, C.P)])
        else Normal := UnitNormal(P.Normal);
      UV := TpvVector3.Create(0, 0, 0);
      if C.T >= 0 then UV := UVs[C.T];
      VertexIndex := Obj.AddVertex;
      Obj.SetVertexPosition(Position.x, Position.y, Position.z);
      Obj.SetVertexColor(Color.x, Color.y, Color.z, Store.fMaterial.Opacity);
      Obj.SetVertexNormal(Normal.x, Normal.y, Normal.z);
      // Retain source UVs; each map may have its own transform. The diffuse
      // shader applies its transform and the image-origin V flip at sampling.
      Obj.SetVertexTexCoord(UV.x, UV.y);
      Vertices.Add(Key, VertexIndex);
    end;
    Obj.AddIndex(VertexIndex);
  end;
begin
  Result := TObjectList<TvgOBJObjectStore>.Create;
  Vertices := TDictionary<string, Integer>.Create;
  try
    try
      Prev := nil; Store := nil; Obj := nil;
      for FaceID := 0 to Primitives.Count - 1 do
      begin
        P := Primitives[FaceID]; LineNo := P.LineNo;
        if (Prev = nil) or (Prev.ObjectName <> P.ObjectName) or (Prev.Groups <> P.Groups) or
          (Prev.MaterialName <> P.MaterialName) or (Prev.Kind <> P.Kind) then
        begin
          Store := TvgOBJObjectStore.Create(nil); Result.Add(Store);
          Store.fObjectName := P.ObjectName; Store.fGroupNames := P.Groups;
          Store.fMaterial := DefaultMaterial;
          Store.fMaterial.Name := P.MaterialName;
          if (P.MaterialName <> '') and Materials.TryGetValue(P.MaterialName, M) then
          begin
            Store.fMaterial := M.Data;
            Store.fMaterial.Maps := Copy(M.Data.Maps); // bindings are per store
          end;
          Store.SetupVertexAttributes([vdtPosition, vdtColor, vdtNormal, vdtTexCoord]);
          Store.SetupInstanceAttributes([idtObjID]); Store.SetIndexType(itUInt32);
          Store.Topology := P.Kind;
          HasDiffuseMap := False;
          for Map in Store.fMaterial.Maps do if Map.Kind = 'map_Kd' then HasDiffuseMap := True;
          Store.PrebuiltShaderVariants := True;
          Store.BaseVertName := 'OBJ';
          Store.BaseFragName := 'OBJ';
          if HasDiffuseMap then Store.BaseFragName := 'OBJTexture';
          Obj := Store.AddObject(True); Obj.AddObjectID;
          Vertices.Clear;
        end;
        if P.Kind = TRIANGLE_LIST then
          for J in P.Triangles do AddCorner(J)
        else if P.Kind = LINE_LIST then
          for I := 0 to High(P.Corners) - 1 do begin AddCorner(I); AddCorner(I + 1); end
        else for I := 0 to High(P.Corners) do AddCorner(I);
        Prev := P;
      end;
    except Result.Free; raise; end;
  finally Vertices.Free; end;
end;

procedure TvgSceneLoader_OBJ.LoadTextures(aStore: TvgOBJObjectStore);
var
  I, J, Binding: Integer;
  Map: TvgOBJTextureMap;
  Stream: TFileStream;
  Info: TTextureInfo;
  Tex: TvgDescriptorArray_Texture;
  Data: TBytes;
  Pixels: Pointer;
  Width, Height: Integer;
begin
  fCurrentObjectStore := aStore;
  Binding := 0;
  // Diffuse is always binding zero for OBJTexture_frag, irrespective of MTL order.
  for J := 0 to 1 do
    for I := 0 to High(aStore.fMaterial.Maps) do
    begin
      Map := aStore.fMaterial.Maps[I];
      if ((J = 0) and (Map.Kind <> 'map_Kd')) or ((J = 1) and (Map.Kind = 'map_Kd')) then Continue;
      Stream := TFileStream.Create(Map.FileName, fmOpenRead or fmShareDenyWrite);
      try
        if (Stream.Size = 0) or not InspectTexture(Stream, Info) then
          raise EvgOBJError.Create('Invalid texture: ' + Map.FileName);
        // The shared inspector returns True for unknown formats because the
        // Vulkan image loader falls back to TGA. Validate that fallback here.
        if Info.FormatKind = tfUnknown then
        begin
          if Stream.Size > MaxInt then raise EvgOBJError.Create('Texture too large: ' + Map.FileName);
          SetLength(Data, Stream.Size); Stream.Position := 0;
          Stream.ReadBuffer(Data[0], Length(Data));
          Pixels := nil;
          try
            if not LoadTGAImage(@Data[0], Length(Data), Pixels, Width, Height, False) then
              raise EvgOBJError.Create('Invalid or unsupported texture: ' + Map.FileName);
          finally FreeMem(Pixels); end;
          Data := nil;
        end;
        Stream.Position := 0;
        Tex := PrepareTextureDescriptor('OBJMap' + IntToStr(Binding));
        if Tex = nil then raise EvgOBJError.Create('Could not create OBJ texture descriptor');
        Tex.Binding := Binding;
        if Tex.AddSharedTexture('OBJMap' + IntToStr(Binding), Stream) < 0 then
          raise EvgOBJError.Create('Could not load texture: ' + Map.FileName);
        if not Tex.TextureData[0].TextureFrame[0].HasTextureSource then
          raise EvgOBJError.Create('Texture data unavailable: ' + Map.FileName);
        if Map.Clamp then
        begin
          Tex.TextureData[0].WrapModeU := TpvVulkanTextureWrapMode.ClampToEdge;
          Tex.TextureData[0].WrapModeV := TpvVulkanTextureWrapMode.ClampToEdge;
        end;
        aStore.fMaterial.Maps[I].Binding := Binding;
        Inc(Binding);
      finally Stream.Free; end;
    end;
end;

procedure TvgSceneLoader_OBJ.LoadScene;
var Reader: TOBJReader; Stores: TObjectList<TvgOBJObjectStore>; Store: TvgOBJObjectStore;
  PreviousStore: TvgObjectStore;
begin
  if not Assigned(fScene) then raise EvgOBJError.Create('OBJ loader requires a Scene');
  if Trim(fFileName) = '' then raise EvgOBJError.Create('OBJ loader requires a FileName');
  Reader := TOBJReader.Create;
  try
    Reader.ReadOBJ(ExpandFileName(fFileName));
    Stores := Reader.BuildStores;
    try
      PreviousStore := fCurrentObjectStore;
      try
        for Store in Stores do LoadTextures(Store);
      finally fCurrentObjectStore := PreviousStore; end;
      // All files and CPU data are ready before replacing the current scene.
      if not fScene.Load_Begin then raise EvgOBJError.Create('Scene is not ready to load an OBJ file');
      fCurrentObjectStore := nil;
      try
        while Stores.Count > 0 do
        begin
          Store := Stores[0];
          fScene.AddDataStore(Store);
          Stores.Extract(Store);
          fCurrentObjectStore := Store;
        end;
      finally fScene.Load_End; end;
    finally Stores.Free; end;
  finally Reader.Free; end;
end;

procedure TvgSceneLoader_OBJ.StoreScene;
begin
  raise EvgOBJError.Create('OBJ loader is load-only; saving is not supported');
end;

initialization
  RegisterSceneLoader(TvgSceneLoader_OBJ, 'OBJ', 'Wavefront OBJ scene', '.obj', 'FileName');
  RegisterClass(TvgSceneLoader_OBJ);
finalization
  UnregisterClass(TvgSceneLoader_OBJ);
  UnregisterSceneLoader(TvgSceneLoader_OBJ);
end.
