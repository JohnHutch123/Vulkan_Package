unit Vulkan_Loader_OBJ;

{ Load-only Wavefront polygon/line/point OBJ and MTL importer.
  Public Vulkan Package, zlib licence. Material lighting data is retained;
  this unit does not create lights or implement a lighting model. }

interface

uses
  System.SysUtils, System.Classes, PasVulkan.Math, Vulkan_Components,
  Vulkan_Components_Scene_Renderer, Vulkan_Components_Lookups;

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

  // How OBJ.frag lights a store: not at all, by each triangle's own plane, or
  // by the interpolated vertex normals.  The order is the shader's SHADING.
  TvgOBJShading = (osUnlit, osFlat, osSmooth);

  // A store drawn with the OBJ prebuilt shaders (OBJ / OBJTexture and their
  // variants), lit by their headlight.  TvgOBJObjectStore is one; another
  // loader that borrows the shaders derives its stores from this too.
  TvgOBJShadedStore = class(TvgObjectStore)
  private
    fShading: TvgOBJShading;
    fAmbient: Single;
    procedure SetShading(const Value: TvgOBJShading);
    procedure SetAmbient(const Value: Single);
    procedure RebuildPipelines;
  protected
    procedure ConfigureGraphicPipeline(GP: TvgGraphicPipeline); override;
    // Adds or replaces one of the fragment shader's specialization constants.
    class procedure SetFragmentConstant(GP: TvgGraphicPipeline; ID: Integer;
      const Name: string; SpecType: TvgSpecialisationType; const Value: string);
  public
    constructor Create(AOwner: TComponent); override;
  published
    { The loader sets it from the file.  Lines and points are always drawn
      unlit, having no surface to light.  Both are shader specialization
      constants: changing either on a store already drawing rebuilds just
      its pipelines (main thread). }
    property Shading: TvgOBJShading read fShading write SetShading default osSmooth;
    // Brightness of a surface seen edge-on, 0..1; face-on it is 1.
    property Ambient: Single read fAmbient write SetAmbient;
  end;

  // Scene-owned data: remains available even when vgLoadSceneFile frees its
  // temporary loader. One store per contiguous object/group/material/topology.
  // Shading starts flat for faces with no normals and smoothing off, as the
  // OBJ format says (unless the loader's SmoothWhenNoNormals), else smooth.
  TvgOBJObjectStore = class(TvgOBJShadedStore)
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
    fSmoothWhenNoNormals: Boolean;
    procedure LoadTextures(aStore: TvgOBJObjectStore);
  public
    procedure LoadScene; override;
    procedure StoreScene; override;
  published
    property FileName: string read fFileName write fFileName;
    { Faces with no normals and smoothing off are flat in the OBJ format, so
      their stores start with Shading osFlat.  True starts them osSmooth -
      for scans, which are usually exported that way but meant smooth.  The
      vertices are the same either way: Shading can still be changed after. }
    property SmoothWhenNoNormals: Boolean read fSmoothWhenNoNormals
      write fSmoothWhenNoNormals default False;
  end;

implementation

uses
  System.Math, System.IOUtils, System.Generics.Collections,
  PasVulkan.Math.Double, PasVulkan.Framework,
  PasVulkan.Image.TGA,
  Vulkan_Components_DataStore,
  Vulkan_Components_Descriptors, Vulkan_Components_TextureInspector,
  Vulkan_SceneLoaders, Vulkan_MeshUtils, Vulkan_MeshBuilder;

type
  TCorner = record
    P, T, N: Integer;
  end;
  // The o/g/usemtl/s statements in force for a run of primitives.
  TPrimitiveState = record
    ObjectName, Groups, MaterialName, Smooth: string;
    SmoothID: Integer; // one per object + smoothing group, off included
  end;
  // A face, line or point.  Corners and triangles live in the reader's shared
  // lists rather than an object and two arrays per face: a scanned mesh has
  // millions of faces, and that overhead alone fills a 32-bit address space.
  TPrimitive = record
    FirstCorner, CornerCount: Integer;
    // Into Triangles, numbering the primitive's own corners; -1 for a plain
    // triangle, which is 0 1 2.
    FirstTriangle, TriangleCount: Integer;
    State: Integer;
    Kind: TvgPrimitiveTopology;
    LineNo: Integer;
    Normal: TpvVector3D; // unnormalised Newell normal, for area weighting
  end;
  TSmoothKey = record
    SmoothID, Vertex: Integer;
  end;
  TMaterial = class
    Data: TvgOBJMaterial;
  end;
  TOBJReader = class
    FileName: string;
    LineNo, PhysicalLine: Integer;
    FS: TFormatSettings;
    Positions, Colors, Normals, UVs: TList<TpvVector3>;
    HasColors: TList<Boolean>;
    Corners: TList<TCorner>;
    Triangles: TList<Integer>;
    States: TList<TPrimitiveState>;
    SmoothIDs: TDictionary<string, Integer>;
    Primitives: TList<TPrimitive>;
    Materials: TObjectDictionary<string, TMaterial>;
    Libraries: TList<string>;
    SmoothNormals: TDictionary<TSmoothKey, TpvVector3D>;
    // What the load got past: libraries and materials it could not find.
    Warnings: TArray<string>;
    SmoothWhenNoNormals: Boolean;   // the loader's
    procedure Warn(const S: string; const Once: string = '');
    constructor Create;
    destructor Destroy; override;
    procedure Error(const S: string);
    function Number(const S: string): Double;
    function IntegerValue(const S: string): Integer;
    function Tokens(const S: string): TArray<string>;
    function OpenLines(const Path: string): TStreamReader;
    function NextLine(R: TStreamReader; out S: string): Boolean;
    function Index(const S: string; Count: Integer): Integer;
    function Corner(const S: string): TCorner;
    function CornerOf(const P: TPrimitive; I: Integer): TCorner;
    procedure ReadOBJ(const Path: string);
    procedure ReadMTL(const Path: string);
    function ReadMap(const W: TArray<string>): TvgOBJTextureMap;
    procedure Triangulate(var P: TPrimitive);
    procedure BuildNormals;
    function BuildStores: TObjectList<TvgOBJObjectStore>;
  end;

constructor TvgOBJShadedStore.Create(AOwner: TComponent);
begin
  inherited;
  fShading := osSmooth;
  fAmbient := 0.35;
end;

procedure TvgOBJShadedStore.SetShading(const Value: TvgOBJShading);
begin
  if fShading = Value then Exit;
  fShading := Value;
  RebuildPipelines;
end;

procedure TvgOBJShadedStore.SetAmbient(const Value: Single);
begin
  if fAmbient = EnsureRange(Value, 0, 1) then Exit;
  fAmbient := EnsureRange(Value, 0, 1);
  RebuildPipelines;
end;

// Shading and Ambient are specialization constants, baked into the pipeline:
// a store already drawing gets its own pipelines built again, every other
// store's left alone (as TvgDelaunayDisplay does for a live PointSize).  One
// not yet drawing picks the values up when its pipelines are first built.
procedure TvgOBJShadedStore.RebuildPipelines;
var I: Integer;
begin
  if not Assigned(fGraphicPipes) or (fGraphicPipes.Count = 0) then Exit;
  if not Assigned(fScene) or not Assigned(fScene.RendererList) then Exit;
  for I := 0 to fScene.RendererList.Count - 1 do
    if Assigned(fScene.RendererList.Items[I]) then
      DisConnectDataFromSceneandRenderer(fScene.RendererList.Items[I]);
  // The Vulkan buffers freed above are recreated by the next upload.
  fScene.ConnectStoreLive(Self);
  fScene.NotifyDataChanged(Self);
end;

class procedure TvgOBJShadedStore.SetFragmentConstant(GP: TvgGraphicPipeline;
  ID: Integer; const Name: string; SpecType: TvgSpecialisationType; const Value: string);
var I: Integer; Item: TvgShaderSpecialisationItem;
begin
  Item := nil;
  for I := 0 to GP.FragmentS.SpecialConst.Count - 1 do
    if GP.FragmentS.SpecialConst[I].ConstantID = ID then Item := GP.FragmentS.SpecialConst[I];
  if Item = nil then Item := GP.FragmentS.SpecialConst.Add;
  Item.Name := Name; Item.ConstantID := ID; Item.SpecType := SpecType;
  Item.SpecTValue := Value;
end;

procedure TvgOBJShadedStore.ConfigureGraphicPipeline(GP: TvgGraphicPipeline);
begin
  // Shader names (OBJ / OBJTexture and their Double, Pick and PickImage
  // variants) come from inherited: BaseVertName, BaseFragName and
  // PrebuiltShaderVariants are set when the store is built.
  inherited;
  // Lines and points have no surface: their normals are placeholders.
  if Topology = TRIANGLE_LIST then
    SetFragmentConstant(GP, 9, 'SHADING', TS_INTEGER, IntToStr(Ord(fShading)))
  else SetFragmentConstant(GP, 9, 'SHADING', TS_INTEGER, IntToStr(Ord(osUnlit)));
  // The shared specialization setter parses using the current locale.
  SetFragmentConstant(GP, 10, 'AMBIENT', TS_SINGLE, FloatToStr(fAmbient));
end;

procedure TvgOBJObjectStore.ConfigureGraphicPipeline(GP: TvgGraphicPipeline);
var Map: TvgOBJTextureMap;
  procedure SetFloat(ID: Integer; const Name: string; Value: Single);
  begin
    // The shared specialization setter parses using the current locale.
    SetFragmentConstant(GP, ID, Name, TS_SINGLE, FloatToStr(Value));
  end;
begin
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

function SmoothKey(SmoothID, Vertex: Integer): TSmoothKey;
begin
  Result.SmoothID := SmoothID; Result.Vertex := Vertex;
end;

procedure TOBJReader.Warn(const S: string; const Once: string = '');
var W: string;
begin
  // each once - or, with Once, the first of those starting with it
  for W in Warnings do
    if (W = S) or ((Once <> '') and W.StartsWith(Once)) then Exit;
  Warnings := Warnings + [S];
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
  Corners := TList<TCorner>.Create;
  Triangles := TList<Integer>.Create;
  States := TList<TPrimitiveState>.Create;
  SmoothIDs := TDictionary<string, Integer>.Create;
  Primitives := TList<TPrimitive>.Create;
  Materials := TObjectDictionary<string, TMaterial>.Create([doOwnsValues]);
  Libraries := TList<string>.Create;
  SmoothNormals := TDictionary<TSmoothKey, TpvVector3D>.Create;
end;

destructor TOBJReader.Destroy;
begin
  SmoothNormals.Free;
  Libraries.Free;
  Materials.Free;
  Primitives.Free;
  SmoothIDs.Free;
  States.Free;
  Triangles.Free;
  Corners.Free;
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
var I, N, Start: Integer; Token: string; Quoted, Started: Boolean; List: TList<string>;
begin
  if Pos('"', S) = 0 then
  begin
    // The usual line, with no quoted names: cut whole tokens out rather than
    // build them a character at a time - this runs for every line of the file.
    SetLength(Result, 8); N := 0; I := 1;
    while I <= Length(S) do
    begin
      if CharInSet(S[I], [' ', #9]) then begin Inc(I); Continue; end;
      if S[I] = '#' then Break;
      Start := I;
      while (I <= Length(S)) and not CharInSet(S[I], [' ', #9, '#']) do Inc(I);
      if N = Length(Result) then SetLength(Result, N * 2);
      Result[N] := Copy(S, Start, I - Start); Inc(N);
    end;
    SetLength(Result, N);
    Exit;
  end;
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

// Files are read a line at a time: holding a whole file as a string list
// costs several times its size, more than a 32-bit process can find for a
// large scan.
function TOBJReader.OpenLines(const Path: string): TStreamReader;
begin
  FileName := Path; PhysicalLine := 0; LineNo := 0;
  Result := TStreamReader.Create(Path, TEncoding.UTF8, True, 1 shl 20);
end;

// The next statement, backslash continuations joined; LineNo is its first
// physical line.
function TOBJReader.NextLine(R: TStreamReader; out S: string): Boolean;
var L: string; Last: Integer;
begin
  S := ''; Result := False;
  while not R.EndOfStream do
  begin
    L := R.ReadLine; Inc(PhysicalLine);
    if not Result then LineNo := PhysicalLine;
    Result := True;
    Last := Length(L);
    while (Last > 0) and (L[Last] <= ' ') do Dec(Last);
    if (Last > 0) and (L[Last] = '\') then
    begin
      S := S + Copy(L, 1, Last - 1) + ' ';
      if R.EndOfStream then begin LineNo := PhysicalLine; Error('Unfinished continuation'); end;
    end
    else
    begin
      S := S + L;
      Exit;
    end;
  end;
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

function TOBJReader.CornerOf(const P: TPrimitive; I: Integer): TCorner;
begin
  Result := Corners.List[P.FirstCorner + I];
end;

procedure TOBJReader.ReadOBJ(const Path: string);
var
  Reader: TStreamReader;
  Line: string;
  W: TArray<string>;
  J, K, StateIndex: Integer;
  V, C: TpvVector3;
  X, Y, Z, Weight: Double;
  ObjectName, Groups, MaterialName, Smooth, Lib, Key: string;
  P: TPrimitive;
  State: TPrimitiveState;
begin
  StateIndex := -1;
  Reader := OpenLines(Path);
  try
  while NextLine(Reader, Line) do
  begin
    W := Tokens(Line);
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
      if StateIndex < 0 then
      begin
        State.ObjectName := ObjectName; State.Groups := Groups;
        State.MaterialName := MaterialName; State.Smooth := Smooth;
        // Smoothing off is a group of its own, Smooth '': flat shading is the
        // shader's (TvgOBJShading), so its faces share vertices and smooth
        // normals like any other, for when a store is switched to smooth.
        // Length-prefix names to avoid collisions when names contain separators.
        Key := IntToStr(Length(ObjectName)) + ':' + ObjectName + ':' + Smooth;
        if not SmoothIDs.TryGetValue(Key, State.SmoothID) then
        begin
          State.SmoothID := SmoothIDs.Count; SmoothIDs.Add(Key, State.SmoothID);
        end;
        StateIndex := States.Add(State);
      end;
      P := Default(TPrimitive);
      P.State := StateIndex; P.LineNo := LineNo;
      P.Kind := TRIANGLE_LIST;
      if W[0] = 'l' then P.Kind := LINE_LIST;
      if W[0] = 'p' then P.Kind := POINT_LIST;
      P.FirstCorner := Corners.Count; P.CornerCount := Length(W) - 1;
      P.FirstTriangle := -1;
      for J := 1 to High(W) do Corners.Add(Corner(W[J]));
      if P.Kind = TRIANGLE_LIST then Triangulate(P);
      Primitives.Add(P);
    end
    else if W[0] = 'o' then begin ObjectName := Join(W, 1); StateIndex := -1; end
    else if W[0] = 'g' then begin Groups := Join(W, 1); StateIndex := -1; end
    else if W[0] = 'usemtl' then begin MaterialName := Join(W, 1); StateIndex := -1; end
    else if W[0] = 's' then
    begin
      if Length(W) <> 2 then Error('Expected smoothing group or off');
      Smooth := W[1];
      if (Smooth = 'off') or (Smooth = '0') then Smooth := '';
      if Smooth = 'on' then Smooth := '1';
      StateIndex := -1;
    end
    else if W[0] = 'mtllib' then
    begin
      if Length(W) < 2 then Error('Missing material library name');
      // Accept an unquoted filename with spaces when the whole path exists.
      Lib := ExpandFileName(ExtractFilePath(Path) + Join(W, 1));
      if FileExists(Lib) then Libraries.Add(Lib)
      else
      begin
        // Several libraries on one line - or one unquoted name with spaces
        // that is not there, reported as written.
        K := 0;
        for J := 1 to High(W) do
          if FileExists(TPath.Combine(ExtractFilePath(Path), W[J])) then Inc(K);
        if K = 0 then
          Warn(Format('Material library "%s" (line %d) not found in %s - its materials are drawn grey',
            [Join(W, 1), LineNo, ExtractFilePath(Path)]))
        else
          for J := 1 to High(W) do
          begin
            Lib := TPath.GetFullPath(TPath.Combine(ExtractFilePath(Path), W[J]));
            if FileExists(Lib) then Libraries.Add(Lib)
            else Warn(Format('Material library "%s" (line %d) not found in %s - its materials are drawn grey',
              [W[J], LineNo, ExtractFilePath(Path)]));
          end;
      end;
    end
    else if (W[0] = 'vp') or (W[0] = 'curv') or (W[0] = 'curv2') or
      (W[0] = 'surf') or (W[0] = 'cstype') or (W[0] = 'call') then
      Error('Unsupported free-form/external geometry statement: ' + W[0]);
  end;
  finally Reader.Free; end;
  if Primitives.Count = 0 then Error('OBJ file contains no faces, lines or points');
  // Returns the lists' spare growth room before the stores are built.
  Primitives.TrimExcess; Corners.TrimExcess; Triangles.TrimExcess;
  // OBJ files are often distributed without their companion libraries.
  // Available libraries still load; absent ones leave default materials.
  for Lib in Libraries do
    if FileExists(Lib) then ReadMTL(Lib);
  FileName := Path;
  BuildNormals;
end;

procedure TOBJReader.Triangulate(var P: TPrimitive);
var
  Pts: TArray<TpvVector3D>;
  Tris: TArray<Integer>;
  V: TpvVector3;
  I: Integer;
begin
  SetLength(Pts, P.CornerCount);
  for I := 0 to High(Pts) do
  begin
    V := Positions.List[CornerOf(P, I).P];
    Pts[I] := TpvVector3D.Create(V.x, V.y, V.z);
  end;
  // Triangles pass through even with no area (exported sphere poles).
  case vgTriangulatePolygon(Pts, Tris, P.Normal) of
    trDegenerate: Error('Degenerate polygon');
    trFailed: Error('Cannot triangulate polygon (duplicate or intersecting edges)');
  end;
  P.TriangleCount := Length(Tris) div 3;
  // A plain triangle is 0 1 2: nothing to store for it.
  if P.CornerCount = 3 then P.FirstTriangle := -1
  else
  begin
    P.FirstTriangle := Triangles.Count;
    Triangles.AddRange(Tris);
  end;
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
  Reader: TStreamReader;
  Line: string;
  W: TArray<string>;
  J, N, Start: Integer;
  M: TMaterial;
  V: TpvVector3;
  X, Y, Z: Double;
  Map: TvgOBJTextureMap;
  Key: string;
  procedure Arity(Count: Integer);
  begin if Length(W) <> Count then Error('Invalid ' + W[0] + ' value count'); end;
begin
  Reader := OpenLines(Path); M := nil;
  try
  while NextLine(Reader, Line) do
  begin
    W := Tokens(Line);
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
      M.Data.ExtraStatements[N] := Line;
    end;
  end;
  finally Reader.Free; end;
end;

procedure TOBJReader.BuildNormals;
var P: TPrimitive; I, SmoothID: Integer; Key: TSmoothKey; V: TpvVector3D; Needed: Boolean;
begin
  // Only corners with no normal of their own use these.
  Needed := False;
  for I := 0 to Corners.Count - 1 do
    if Corners.List[I].N < 0 then begin Needed := True; Break; end;
  if not Needed then Exit;
  for P in Primitives do
  begin
    SmoothID := States.List[P.State].SmoothID;
    if P.Kind = TRIANGLE_LIST then
      for I := 0 to P.CornerCount - 1 do
      begin
        Key := SmoothKey(SmoothID, CornerOf(P, I).P);
        if not SmoothNormals.TryGetValue(Key, V) then V := TpvVector3D.Create(0, 0, 0);
        SmoothNormals.AddOrSetValue(Key, V + P.Normal);
      end;
  end;
end;

function TOBJReader.BuildStores: TObjectList<TvgOBJObjectStore>;
type
  TVertexKey = record
    P, T, N, SmoothID: Integer;
  end;
  // A vertex of the store being built: the corner it came from, and the
  // primitive whose face normal or smoothing group it takes.
  TStoreVertex = record
    C: TCorner;
    Prim: Integer;
  end;
var
  Store: TvgOBJObjectStore;
  M: TMaterial;
  Mesh: TvgMeshData;
  Vertices: TDictionary<TVertexKey, Integer>;
  StoreVertices: TList<TStoreVertex>;
  Indices: TList<Cardinal>;
  First, Last, FaceID, I, J, K: Integer;
  P: TPrimitive;
  Position, Color, Normal, UV: TpvVector3;
  HasDiffuseMap, HasFlatFaces: Boolean;
  Map: TvgOBJTextureMap;
  FirstState: TPrimitiveState;

  function SameStore(const A, B: TPrimitive): Boolean;
  var SA, SB: TPrimitiveState;
  begin
    SA := States.List[A.State]; SB := States.List[B.State];
    Result := (A.Kind = B.Kind) and (SA.ObjectName = SB.ObjectName) and
      (SA.Groups = SB.Groups) and (SA.MaterialName = SB.MaterialName);
  end;

  function VertexUV(K: Integer): TpvVector3;
  var T: Integer;
  begin
    T := StoreVertices.List[K].C.T;
    if T >= 0 then Result := UVs.List[T] else Result := TpvVector3.Create(0, 0, 0);
  end;

  function VertexNormal(K: Integer): TpvVector3;
  var V: TStoreVertex; Q: TPrimitive;
  begin
    V := StoreVertices.List[K];
    Q := Primitives.List[V.Prim];
    Result := TpvVector3.Create(0, 0, 1);
    if V.C.N >= 0 then Result := Normals.List[V.C.N]
    else if Q.Kind = TRIANGLE_LIST then
      Result := UnitNormal(SmoothNormals[SmoothKey(States.List[Q.State].SmoothID, V.C.P)]);
  end;

  procedure AddCorner(CornerIndex: Integer);
  var C: TCorner; Key: TVertexKey; V: TStoreVertex; VertexIndex: Integer;
  begin
    C := CornerOf(P, CornerIndex);
    // Flat shading is the shader's, from each triangle's own plane, so even a
    // flat face's corners are shared - by smoothing group, whose normal they
    // take when the store is switched to smooth.
    Key.P := C.P; Key.T := C.T; Key.N := C.N; Key.SmoothID := -1;
    if (C.N < 0) and (P.Kind = TRIANGLE_LIST) then
    begin
      Key.SmoothID := States.List[P.State].SmoothID;
      if States.List[P.State].Smooth = '' then HasFlatFaces := True;
    end;
    if not Vertices.TryGetValue(Key, VertexIndex) then
    begin
      V.C := C; V.Prim := FaceID;
      VertexIndex := StoreVertices.Add(V);
      Vertices.Add(Key, VertexIndex);
    end;
    Indices.Add(VertexIndex);
  end;

begin
  Result := TObjectList<TvgOBJObjectStore>.Create;
  Vertices := TDictionary<TVertexKey, Integer>.Create;
  StoreVertices := TList<TStoreVertex>.Create;
  Indices := TList<Cardinal>.Create;
  try
    try
      First := 0;
      while First < Primitives.Count do
      begin
        Last := First;
        while (Last + 1 < Primitives.Count) and
          SameStore(Primitives.List[First], Primitives.List[Last + 1]) do Inc(Last);
        P := Primitives.List[First]; LineNo := P.LineNo;
        FirstState := States.List[P.State];

        // Every vertex and index first, so the store is allocated once at its
        // final size rather than grown a vertex at a time.
        Vertices.Clear; StoreVertices.Clear; Indices.Clear;
        HasFlatFaces := False;
        for FaceID := First to Last do
        begin
          P := Primitives.List[FaceID]; LineNo := P.LineNo;
          if P.Kind = TRIANGLE_LIST then
          begin
            if P.FirstTriangle < 0 then begin AddCorner(0); AddCorner(1); AddCorner(2); end
            else for J := P.FirstTriangle to P.FirstTriangle + 3 * P.TriangleCount - 1 do
              AddCorner(Triangles.List[J]);
          end
          else if P.Kind = LINE_LIST then
            for I := 0 to P.CornerCount - 2 do begin AddCorner(I); AddCorner(I + 1); end
          else for I := 0 to P.CornerCount - 1 do AddCorner(I);
        end;
        Vertices.Clear;

        P := Primitives.List[First]; LineNo := P.LineNo;
        Store := TvgOBJObjectStore.Create(nil); Result.Add(Store);
        Store.fObjectName := FirstState.ObjectName; Store.fGroupNames := FirstState.Groups;
        Store.fMaterial := DefaultMaterial;
        Store.fMaterial.Name := FirstState.MaterialName;
        if (FirstState.MaterialName <> '') and Materials.TryGetValue(FirstState.MaterialName, M) then
        begin
          Store.fMaterial := M.Data;
          Store.fMaterial.Maps := Copy(M.Data.Maps); // bindings are per store
        end
        else if FirstState.MaterialName <> '' then
          Warn(Format('Material "%s" (usemtl, line %d) is in no material library loaded - drawn grey',
            [FirstState.MaterialName, P.LineNo]), Format('Material "%s" ', [FirstState.MaterialName]));
        HasDiffuseMap := False;
        for Map in Store.fMaterial.Maps do if Map.Kind = 'map_Kd' then HasDiffuseMap := True;
        vgSetupShadedStore(Store, P.Kind, HasDiffuseMap);
        // The OBJ format's own shading: flat where faces have no normals and
        // smoothing is off.  The shader ignores it on lines and points.
        if HasFlatFaces and not SmoothWhenNoNormals then Store.fShading := osFlat
        else Store.fShading := osSmooth;

        Mesh.Clear;
        Mesh.Topology := P.Kind;
        SetLength(Mesh.Positions, StoreVertices.Count);
        SetLength(Mesh.Normals, StoreVertices.Count);
        SetLength(Mesh.Colors, StoreVertices.Count);
        SetLength(Mesh.TexCoords, StoreVertices.Count);
        for K := 0 to StoreVertices.Count - 1 do
        begin
          J := StoreVertices.List[K].C.P;
          Position := Positions.List[J]; Color := Store.fMaterial.Diffuse;
          if HasColors.List[J] then
          begin
            // Explicit vertex colours keep their original brightness when there
            // is no material, otherwise they modulate the material diffuse colour.
            if Store.fMaterial.LibraryFile = '' then Color := Colors.List[J]
            else Color := TpvVector3.Create(Color.x * Colors.List[J].x,
              Color.y * Colors.List[J].y, Color.z * Colors.List[J].z);
          end;
          Normal := VertexNormal(K);
          UV := VertexUV(K);
          Mesh.Positions[K] := Position;
          Mesh.Colors[K] := TpvVector4.Create(Color.x, Color.y, Color.z, Store.fMaterial.Opacity);
          Mesh.Normals[K] := Normal;
          // Retain source UVs; each map may have its own transform. The diffuse
          // shader applies its transform and the image-origin V flip at sampling.
          Mesh.TexCoords[K] := TpvVector2.Create(UV.x, UV.y);
        end;
        Mesh.Indices := Indices.ToArray;
        // Bulk write, and tangent frames (vgBuildTangents: lines and points
        // get any frame about the normal).
        vgWriteMesh(Store, 0, Mesh, TpvVector4.Create(1, 1, 1, 1));
        Mesh.Clear;
        First := Last + 1;
      end;
    except Result.Free; raise; end;
  finally
    Vertices.Free; StoreVertices.Free; Indices.Free;
  end;
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
  PreviousStore: TvgObjectStore; W: string; Warnings: TArray<string>;
begin
  ClearWarnings;
  if not Assigned(fScene) then raise EvgOBJError.Create('OBJ loader requires a Scene');
  if Trim(fFileName) = '' then raise EvgOBJError.Create('OBJ loader requires a FileName');
  // The reader and its parsed file are freed before the stores reach the
  // GPU: on a large scan they are hundreds of MB the upload may need.
  Reader := TOBJReader.Create;
  try
    Reader.SmoothWhenNoNormals := fSmoothWhenNoNormals;
    Reader.ReadOBJ(ExpandFileName(fFileName));
    Stores := Reader.BuildStores;
    Warnings := Reader.Warnings;
  finally Reader.Free; end;
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
    for W in Warnings do AddWarning(W);
  finally Stores.Free; end;
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
