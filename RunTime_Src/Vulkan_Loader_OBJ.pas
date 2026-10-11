unit Vulkan_Loader_OBJ;

{ Simple, load-only Wavefront OBJ geometry loader (public package, zlib licence).
  All faces become one indexed triangle object. Convex polygons are fan
  triangulated; export concave polygons as triangles. Coordinates and winding
  are retained. Normals, UVs, materials, groups and smoothing are ignored. }

interface

uses
  System.SysUtils, System.Classes, Vulkan_Components_Scene_Renderer;

type
  EvgOBJError = class(Exception);

  TvgSceneLoader_OBJ = class(TvgSceneLoaderStorer)
  private
    fFileName: string;
  public
    procedure LoadScene; override;
    procedure StoreScene; override;
  published
    property FileName: string read fFileName write fFileName;
  end;

implementation

uses
  System.Math, System.Generics.Collections, PasVulkan.Math,
  Vulkan_Components, Vulkan_Components_DataStore,
  Vulkan_Components_Lookups, Vulkan_SceneLoaders;

procedure TvgSceneLoader_OBJ.LoadScene;
var
  Lines: TStringList;
  Positions, Colors: TList<TpvVector3>;
  Indices: TList<Cardinal>;
  Words, Corner: TArray<string>;
  Face: TArray<Integer>;
  Line: string;
  LineNo, I, J, K, N, CommentAt: Integer;
  X, Y, Z, W, R, G, B: Double;
  FS: TFormatSettings;
  Store: TvgObjectStore;
  Obj: TvgObject;

  procedure Error(const MessageText: string);
  begin
    raise EvgOBJError.CreateFmt('%s, line %d: %s',
      [fFileName, LineNo + 1, MessageText]);
  end;

  function Number(const S: string): Double;
  begin
    if not TryStrToFloat(S, Result, FS) then
      Error('Invalid number: ' + S);
    if IsNan(Result) or IsInfinite(Result) then
      Error('Non-finite number: ' + S);
  end;

begin
  if not Assigned(fScene) then
    raise EvgOBJError.Create('OBJ loader requires a Scene');
  if Trim(fFileName) = '' then
    raise EvgOBJError.Create('OBJ loader requires a FileName');

  Lines := TStringList.Create;
  Positions := TList<TpvVector3>.Create;
  Colors := TList<TpvVector3>.Create;
  Indices := TList<Cardinal>.Create;
  try
    // Parse everything before Load_Begin, which clears the existing scene.
    Lines.LoadFromFile(fFileName, TEncoding.UTF8);
    FS := TFormatSettings.Create;
    FS.DecimalSeparator := '.';
    FS.ThousandSeparator := #0;
    for LineNo := 0 to Lines.Count - 1 do
    begin
      Line := Lines[LineNo];
      CommentAt := Pos('#', Line);
      if CommentAt > 0 then
        Delete(Line, CommentAt, MaxInt);
      Words := Line.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
      if Length(Words) = 0 then
        Continue;
      if Words[0] = 'v' then
      begin
        // v x y z [w], or the common x y z r g b vertex colour extension
        if not (Length(Words) in [4, 5, 7]) then
          Error('Expected v x y z [w] or v x y z r g b');
        X := Number(Words[1]);
        Y := Number(Words[2]);
        Z := Number(Words[3]);
        W := 1;
        R := 0.8;
        G := 0.8;
        B := 0.8;
        if Length(Words) = 5 then
          W := Number(Words[4])
        else if Length(Words) = 7 then
        begin
          R := EnsureRange(Number(Words[4]), 0, 1);
          G := EnsureRange(Number(Words[5]), 0, 1);
          B := EnsureRange(Number(Words[6]), 0, 1);
        end;
        if W = 0 then
          Error('Vertex weight must not be zero');
        X := X / W;
        Y := Y / W;
        Z := Z / W;
        if (Abs(X) > MaxSingle) or (Abs(Y) > MaxSingle) or
           (Abs(Z) > MaxSingle) then
          Error('Vertex exceeds the scene single-precision range');
        Positions.Add(TpvVector3.Create(X, Y, Z));
        Colors.Add(TpvVector3.Create(R, G, B));
      end
      else if Words[0] = 'f' then
      begin
        if Length(Words) < 4 then
          Error('A face needs at least three vertices');
        SetLength(Face, Length(Words) - 1);
        for I := 1 to High(Words) do
        begin
          Corner := Words[I].Split(['/']);
          if (Length(Corner) < 1) or (Length(Corner) > 3) then
            Error('Invalid face corner: ' + Words[I]);
          if not TryStrToInt(Corner[0], N) or (N = 0) then
            Error('Invalid vertex index: ' + Corner[0]);
          if N < 0 then
            N := Positions.Count + N
          else
            Dec(N);
          if (N < 0) or (N >= Positions.Count) then
            Error('Vertex index out of range: ' + Corner[0]);
          Face[I - 1] := N;
          // Accept v, v/vt, v//vn and v/vt/vn. Attribute indices are
          // syntactically checked, but their data is outside this loader.
          for J := 1 to High(Corner) do
          begin
            if (J = 1) and (Length(Corner) = 3) and (Corner[J] = '') then
              Continue;
            if not TryStrToInt(Corner[J], K) or (K = 0) then
              Error('Invalid attribute index: ' + Words[I]);
          end;
        end;
        for I := 1 to High(Face) - 1 do
        begin
          Indices.Add(Face[0]);
          Indices.Add(Face[I]);
          Indices.Add(Face[I + 1]);
        end;
      end;
    end;
    if Indices.Count = 0 then
      raise EvgOBJError.Create('OBJ file contains no polygon faces: ' + fFileName);

    // Build the CPU store first too, so allocation failures leave the scene.
    Store := TvgObjectStore.Create(nil);
    try
      Store.SetupVertexAttributes([vdtPosition, vdtColor]);
      Store.SetupInstanceAttributes([idtObjID]);
      Store.SetIndexType(itUInt32);
      Store.Topology := TRIANGLE_LIST;
      // The public EditLines shaders consume position/colour/object ID;
      // primitive topology is supplied by the store, so triangles work too.
      Store.BaseVertName := 'EditLines';
      Store.BaseFragName := 'EditLines';
      Obj := Store.AddObject(True);
      // Grey unless the file gave the vertex a colour.
      for I := 0 to Positions.Count - 1 do
      begin
        Obj.AddVertex;
        Obj.SetVertexPosition(Positions[I].x, Positions[I].y, Positions[I].z);
        Obj.SetVertexColor(Colors[I].x, Colors[I].y, Colors[I].z);
      end;
      Obj.AddIndices(Indices.ToArray);
      Obj.AddObjectID;
      if not fScene.Load_Begin then
        raise EvgOBJError.Create('Scene is not ready to load an OBJ file');
      fCurrentObjectStore := nil;
      try
        fScene.AddDataStore(Store);
        fCurrentObjectStore := Store;
        Store := nil; // scene owns it
      finally
        fScene.Load_End;
      end;
    finally
      Store.Free;
    end;
  finally
    Indices.Free;
    Colors.Free;
    Positions.Free;
    Lines.Free;
  end;
end;

procedure TvgSceneLoader_OBJ.StoreScene;
begin
  raise EvgOBJError.Create('OBJ loader is load-only; saving is not supported');
end;

initialization
  RegisterSceneLoader(TvgSceneLoader_OBJ, 'OBJ', 'Wavefront OBJ geometry',   '.obj', 'FileName');
  RegisterClass(TvgSceneLoader_OBJ);

finalization
  UnregisterClass(TvgSceneLoader_OBJ);
  UnregisterSceneLoader(TvgSceneLoader_OBJ);

end.
