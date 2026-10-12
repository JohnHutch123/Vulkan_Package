program OBJMaterialTest;
{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Math,
  Vcl.Graphics, Vcl.Imaging.pngimage, Vcl.Imaging.jpeg, Vulkan, PasVulkan.Math.Double,
  Vulkan_Components, Vulkan_Components_Lookups, Vulkan_Components_DataStore,
  Vulkan_Components_Descriptors, Vulkan_Components_Scene_Renderer,
  Vulkan_Components_Light, Vulkan_Components_TextureInspector,
  Vulkan_Loader_OBJ, Vulkan_SceneLoaders;

const
  Mesh = 'v 0 0 0'#10'v 1 0 0'#10'v 1 1 0'#10'v 0 1 0'#10;
  UVs = 'vt 0.2 0.3'#10'vt 1 0'#10'vt 1 1'#10'vt 0 1'#10;
type
  TStoreAccess = class(TvgOBJObjectStore);
var
  Failures: Integer = 0;
  Folder, OBJPath, MTLPath: string;
  Scene: TvgScene;
  Loader: TvgSceneLoader_OBJ;

procedure Check(const Name: string; OK: Boolean);
begin
  if OK then Writeln('  ok   ', Name)
  else begin Inc(Failures); Writeln('  FAIL ', Name); end;
end;

function Near(A, B: Double): Boolean;
begin Result := Abs(A - B) < 1e-5; end;

procedure Load(const Text: string);
begin
  TFile.WriteAllText(OBJPath, Text, TEncoding.UTF8);
  Loader.LoadScene;
end;

function Attribute(Store: TvgObjectStore; Vertex, Location, Component: Integer): Single;
var A: TVkVertexInputAttributeDescription; D: TvgObjectData; Offset: Integer;
begin
  D := Store.GetObjectData(0);
  for A in Store.GetAttributeDescriptions do
    if (A.binding = 0) and (Integer(A.location) = Location) then
    begin
      Offset := Vertex * Integer(Store.GetStride(0)) + Integer(A.offset) + Component * SizeOf(Single);
      Move(D.Vertices[Offset], Result, SizeOf(Result));
      Exit;
    end;
  raise Exception.Create('Vertex attribute not found');
end;

procedure Reject(const Name, Text: string);
var Original: TvgObjectStore; Raised: Boolean;
begin
  Original := Scene.SceneData[0];
  Raised := False;
  try Load(Text); except on E: Exception do begin
    Check(Name + ' reports a loader/file error',
      (E is EvgOBJError) or (E is EFOpenError) or (E is EReadError));
    Raised := True; Writeln('       ', E.Message);
  end; end;
  Check(Name, Raised);
  Check(Name + ' preserves scene', (Scene.SceneData.Count > 0) and (Scene.SceneData[0] = Original));
end;

procedure TestMaterials;
var S: TvgOBJObjectStore; M: TvgOBJMaterial; T: TvgDescriptorArray_Texture;
  I: Integer; Light: TvgLight;
begin
  TFile.WriteAllText(MTLPath,
    'newmtl Painted'#10'Ka 0.1 0.2 0.3'#10'Kd 0.4 0.5 0.6'#10'Ks 0.7 0.8 0.9'#10+
    'Ke 0.01 0.02 0.03'#10'Tf 0.9 0.8 0.7'#10'Ns 123'#10'Ni 1.5'#10'illum 4'#10+
    'd -halo 0.75'#10'Pr 0.35'#10'Pm 0.8'#10'Ps 0.2'#10'Pc 0.7'#10'Pcr 0.1'#10+
    'aniso 0.4'#10'anisor 0.25'#10'sharpness 50'#10'custom_value retained'#10+
    'map_Ks -bm 0.25 "checker map.bmp"'#10+
    'map_Kd -o 0.1 0.2 -s 2 3 -clamp on "checker map.bmp"'#10+
    'map_Bump -bm 0.5 checker map.bmp'#10+
    'newmtl Glass'#10'Kd 1 1 1'#10'Tr 0.2'#10, TEncoding.UTF8);
  Light := Default(TvgLight); Light.LightType := ltPoint; Scene.Lights.Add(Light);
  Load('mtllib "materials/model library.mtl"'#10 + Mesh + UVs + 'vn 0 0 1'#10+
    'o Body'#10'g panels trim'#10'usemtl Painted'#10'f 1/1/1 2/2/1 3/3/1'#10+
    'usemtl Glass'#10'f -4/-4/-1 -2/-2/-1 -1/-1/-1'#10);
  Check('material boundary makes two stores', Scene.SceneData.Count = 2);
  S := TvgOBJObjectStore(Scene.SceneData[0]); M := S.Material;
  Check('object and group names retained', (S.ObjectName = 'Body') and (S.GroupNames = 'panels trim'));
  Check('named material and library retained', (M.Name = 'Painted') and SameFileName(M.LibraryFile, MTLPath));
  Check('ambient loaded', Near(M.Ambient.y, 0.2));
  Check('diffuse loaded', Near(M.Diffuse.z, 0.6));
  Check('specular loaded', Near(M.Specular.x, 0.7));
  Check('emissive loaded', Near(M.Emissive.z, 0.03));
  Check('transmission loaded', Near(M.Transmission.y, 0.8));
  Check('shininess, IOR, illum loaded', Near(M.Shininess, 123) and Near(M.OpticalDensity, 1.5) and (M.IlluminationModel = 4));
  Check('opacity and halo loaded', Near(M.Opacity, 0.75) and M.Halo);
  Check('PBR extension fields loaded', Near(M.Roughness, 0.35) and Near(M.Metallic, 0.8) and Near(M.Sheen, 0.2) and
    Near(M.Clearcoat, 0.7) and Near(M.ClearcoatRoughness, 0.1) and Near(M.Anisotropy, 0.4) and Near(M.AnisotropyRotation, 0.25));
  Check('extra material statement retained', (Length(M.ExtraStatements) = 1) and (M.ExtraStatements[0] = 'custom_value retained'));
  Check('all three texture maps loaded', Length(M.Maps) = 3);
  Check('texture paths relative to MTL directory', SameFileName(M.Maps[0].FileName, TPath.Combine(ExtractFilePath(MTLPath), 'checker map.bmp')));
  Check('diffuse map bound first', (M.Maps[1].Binding = 0) and (M.Maps[0].Binding = 1));
  Check('map options retained', Near(M.Maps[1].Scale.y, 3) and Near(M.Maps[1].Offset.y, 0.2) and M.Maps[1].Clamp and Near(M.Maps[2].BumpMultiplier, 0.5));
  for I := 0 to 2 do
  begin
    T := TvgDescriptorArray_Texture(S.ObjectStoreRes.Descriptors[I].Descriptor);
    Check('texture has CPU source ' + IntToStr(I), T.TextureData[0].TextureFrame[0].HasTextureSource);
  end;
  Check('explicit normal stored', Near(Attribute(S, 0, 2, 2), 1));
  Check('source UV preserved for per-map transforms', Near(Attribute(S, 0, 3, 0), 0.2) and Near(Attribute(S, 0, 3, 1), 0.3));
  Check('diffuse and opacity reach vertex data', Near(Attribute(S, 0, 1, 0), 0.4) and Near(Attribute(S, 0, 1, 3), 0.75));
  Check('Tr converts to opacity', Near(TvgOBJObjectStore(Scene.SceneData[1]).Material.Opacity, 0.8));
  Check('no scene lights inferred from materials', Scene.Lights.Count = 0);

  // Registry owns and frees its temporary loader; material and image data must remain.
  vgLoadSceneFile(Scene, OBJPath);
  S := TvgOBJObjectStore(Scene.SceneData[0]);
  Check('material outlives temporary loader', Near(S.Material.Specular.x, 0.7));
  T := TvgDescriptorArray_Texture(S.ObjectStoreRes.Descriptors[0].Descriptor);
  Check('texture outlives temporary loader', T.TextureData[0].TextureFrame[0].HasTextureSource);

  Reject('bad UV index', Mesh + UVs + 'f 1/5 2/2 3/3');
  Reject('bad normal index', Mesh + 'vn 0 0 1'#10'f 1//2 2//1 3//1');
  Load('mtllib missing.mtl'#10 + Mesh + 'f 1 2 3');
  Check('missing MTL still loads geometry', Scene.SceneData[0].GetObjectIndexCount(0) = 3);
  Load('mtllib "missing library.mtl"'#10 + Mesh + UVs +
    'usemtl absent'#10'f 1/1 2/2 3/3');
  S := TvgOBJObjectStore(Scene.SceneData[0]);
  Check('missing MTL and named material fall back to grey',
    (S.GetObjectIndexCount(0) = 3) and Near(Attribute(S, 0, 1, 0), 0.8) and
    Near(Attribute(S, 0, 1, 3), 1));
  Check('fallback retains material name without textures',
    (S.Material.Name = 'absent') and (S.Material.LibraryFile = '') and (Length(S.Material.Maps) = 0));
  Load(Mesh + 'usemtl absent'#10'f 1 2 3');
  Check('usemtl without any library loads', Scene.SceneData[0].GetObjectIndexCount(0) = 3);
  Load('mtllib missing.mtl'#10'v 0 0 0 1 0.5 0.25'#10'v 1 0 0'#10'v 0 1 0'#10+
    'usemtl absent'#10'f 1 2 3');
  S := TvgOBJObjectStore(Scene.SceneData[0]);
  Check('missing material preserves explicit vertex colour', Near(Attribute(S, 0, 1, 0), 1) and
    Near(Attribute(S, 0, 1, 1), 0.5) and Near(Attribute(S, 0, 1, 2), 0.25));
  Load('mtllib missing.mtl "materials/model library.mtl"'#10 + Mesh +
    'usemtl Glass'#10'f 1 2 3'#10'usemtl absent'#10'f 1 3 4');
  Check('available library loads alongside missing library',
    (Scene.SceneData.Count = 2) and Near(TvgOBJObjectStore(Scene.SceneData[0]).Material.Opacity, 0.8) and
    Near(TvgOBJObjectStore(Scene.SceneData[1]).Material.Opacity, 1));
  Check('missing MTL reload replaces old geometry', Scene.SceneData[0].GetObjectIndexCount(0) = 3);
  TFile.WriteAllText(MTLPath, 'newmtl Bad'#10'Kd nope 1 1', TEncoding.UTF8);
  Reject('malformed MTL', 'mtllib "materials/model library.mtl"'#10 + Mesh + 'usemtl Bad'#10'f 1 2 3');
  TFile.WriteAllText(MTLPath, 'newmtl Bad'#10'map_Kd missing.bmp', TEncoding.UTF8);
  Reject('missing texture', 'mtllib "materials/model library.mtl"'#10 + Mesh + UVs + 'usemtl Bad'#10'f 1/1 2/2 3/3');
  TFile.WriteAllText(TPath.Combine(ExtractFilePath(MTLPath), 'bad.bmp'), 'not an image');
  TFile.WriteAllText(MTLPath, 'newmtl Bad'#10'map_Kd bad.bmp', TEncoding.UTF8);
  Reject('invalid texture', 'mtllib "materials/model library.mtl"'#10 + Mesh + UVs + 'usemtl Bad'#10'f 1/1 2/2 3/3');
end;

procedure TestTextureFormatsAndShaders;
var Ext: string; S: TvgOBJObjectStore; Pipeline: TvgGraphicPipeline;
  Engine: TvgRenderEngine; Tex: TvgDescriptorArray_Texture; I: Integer;
  Stream: TMemoryStream; Info: TTextureInfo; Bytes: TBytes;
  function Spec(ID: Integer): Double;
  var J: Integer;
  begin
    for J := 0 to Pipeline.FragmentS.SpecialConst.Count - 1 do
      if Pipeline.FragmentS.SpecialConst[J].ConstantID = ID then
        Exit(StrToFloat(Pipeline.FragmentS.SpecialConst[J].SpecTValue));
    raise Exception.Create('Missing specialization constant');
  end;
begin
  for Ext in ['png', 'jpg', 'bmp'] do
  begin
    TFile.WriteAllText(MTLPath, 'newmtl Test'#10'map_Kd -s 2 3 -o 0.1 0.2 "checker map.' + Ext + '"');
    Load('mtllib "materials/model library.mtl"'#10 + Mesh + UVs + 'usemtl Test'#10'f 1/1 2/2 3/3');
    S := TvgOBJObjectStore(Scene.SceneData[0]);
    Tex := TvgDescriptorArray_Texture(S.ObjectStoreRes.Descriptors[0].Descriptor);
    Check(Ext + ' texture source loaded', Tex.TextureData[0].TextureFrame[0].HasTextureSource);
  end;
  Stream := TMemoryStream.Create;
  try
    Stream.LoadFromFile(TPath.Combine(ExtractFilePath(MTLPath), 'checker map.png'));
    Check('PNG inspector reads big-endian dimensions', InspectTexture(Stream, Info) and
      (Info.FormatKind = tfPNG) and (Info.Width = 2) and (Info.Height = 2));
  finally Stream.Free; end;
  Bytes := TFile.ReadAllBytes(TPath.Combine(ExtractFilePath(MTLPath), 'checker map.png'));
  SetLength(Bytes, 20);
  TFile.WriteAllBytes(TPath.Combine(ExtractFilePath(MTLPath), 'truncated.png'), Bytes);
  TFile.WriteAllText(MTLPath, 'newmtl Bad'#10'map_Kd truncated.png');
  Reject('truncated PNG', 'mtllib "materials/model library.mtl"'#10 + Mesh + UVs + 'usemtl Bad'#10'f 1/1 2/2 3/3');
  Pipeline := TvgGraphicPipeline.Create(nil); Engine := TvgRenderEngine.Create(nil);
  try
    Pipeline.Renderer := Engine;
    Engine.ShaderUseDouble := False; Engine.SelectMode := smNone;
    TStoreAccess(S).ConfigureGraphicPipeline(Pipeline);
    Check('float/unselected shader variant', (Pipeline.VertexS.FileName = 'OBJ_vert.spv') and (Pipeline.FragmentS.FileName = 'OBJTexture_frag.spv'));
    Check('per-map UV transform passed to shader', Near(Spec(3), 2) and Near(Spec(4), 3) and Near(Spec(5), 0.1) and Near(Spec(6), 0.2));
    I := Pipeline.FragmentS.SpecialConst.Count;
    Engine.ShaderUseDouble := True; Engine.SelectMode := smStorageBuffer;
    TStoreAccess(S).ConfigureGraphicPipeline(Pipeline);
    Check('double/buffer-picking shader variant', (Pipeline.VertexS.FileName = 'OBJDouble_vert.spv') and (Pipeline.FragmentS.FileName = 'OBJTexturePick_frag.spv'));
    Check('reconfiguration does not duplicate map constants', Pipeline.FragmentS.SpecialConst.Count = I);
    Engine.SelectMode := smImageBuffer;
    TStoreAccess(S).ConfigureGraphicPipeline(Pipeline);
    Check('image-picking shader variant', Pipeline.FragmentS.FileName = 'OBJTexturePickImage_frag.spv');
  finally Pipeline.Free; Engine.Free; end;
end;

procedure TestGeometry;
var S: TvgObjectStore; I, A, B, C: Integer; Area: Double; P, Q, R: TpvVector3D;
  function Pos(Index: Integer): TpvVector3D;
  begin
    Result.x := S.GetObjectVertexPosition(0, Index).x;
    Result.y := S.GetObjectVertexPosition(0, Index).y;
    Result.z := S.GetObjectVertexPosition(0, Index).z;
  end;
begin
  Load(Mesh + UVs + 'vt 0.7 0.8'#10'vn 0 0 1'#10's 1'#10+
    'f 1/1/1 2/2/1 3/3/1'#10'f 1/5/1 3/3/1 4/4/1');
  S := Scene.SceneData[0];
  Check('UV seam duplicates only split corner', S.GetObjectVertexCount(0) = 5);
  Check('both UVs survive same position', Near(Attribute(S, 0, 3, 0), 0.2) and Near(Attribute(S, 3, 3, 0), 0.7));

  Load(Mesh + 'v 0 0 1'#10's 1'#10'f 1 2 3'#10'f 1 5 2');
  S := Scene.SceneData[0];
  Check('smoothing shares common corners', S.GetObjectVertexCount(0) = 4);
  Check('area-weighted smooth normal', Near(Attribute(S, 0, 2, 1), Sqrt(0.5)) and Near(Attribute(S, 0, 2, 2), Sqrt(0.5)));
  Load(Mesh + 'v 0 0 1'#10's off'#10'f 1 2 3'#10'f 1 5 2');
  S := Scene.SceneData[0];
  Check('flat shading splits hard edge', S.GetObjectVertexCount(0) = 6);
  Check('flat normals differ across edge', Near(Attribute(S, 0, 2, 2), 1) and Near(Attribute(S, 3, 2, 1), 1));

  Load('v 0 0 0'#10'v 2 0 0'#10'v 2 2 0'#10'v 1 1 0'#10'v 0 2 0'#10'f 1 2 3 4 5');
  S := Scene.SceneData[0]; Area := 0;
  Check('concave pentagon makes three triangles', S.GetObjectIndexCount(0) = 9);
  for I := 0 to 2 do
  begin
    A := S.GetObjectIndex(0, I * 3); B := S.GetObjectIndex(0, I * 3 + 1); C := S.GetObjectIndex(0, I * 3 + 2);
    P := Pos(A); Q := Pos(B); R := Pos(C);
    Check('triangle preserves positive winding ' + IntToStr(I), (Q.x-P.x)*(R.y-P.y)-(Q.y-P.y)*(R.x-P.x) > 0);
    Area := Area + ((Q.x-P.x)*(R.y-P.y)-(Q.y-P.y)*(R.x-P.x))/2;
  end;
  Check('concave polygon area retained', Near(Area, 3));

  Load(Mesh + 'o Line'#10'g one two'#10'l 1 2 3 4'#10'o Points'#10'p 1 4');
  Check('line and point primitives loaded', (Scene.SceneData.Count = 2) and
    (Scene.SceneData[0].Topology = LINE_LIST) and (Scene.SceneData[0].GetObjectIndexCount(0) = 6) and
    (Scene.SceneData[1].Topology = POINT_LIST) and (Scene.SceneData[1].GetObjectIndexCount(0) = 2));
  Load(Mesh + 'f 1 2 \'#10'3');
  Check('continued face loaded', Scene.SceneData[0].GetObjectIndexCount(0) = 3);
  Reject('freeform geometry explicitly rejected', Mesh + 'curv 0 1 1 2 3');
end;

var BMP: TBitmap; PNG: TPngImage; JPEG: TJPEGImage; ID: TGUID;
begin
  ShaderFolderPath := IncludeTrailingPathDelimiter(TPath.GetFullPath(
    TPath.Combine(ExtractFilePath(ParamStr(0)), '..\..\VulkanShaders')));
  if ParamCount > 0 then ShaderFolderPath := IncludeTrailingPathDelimiter(ParamStr(1));
  CreateGUID(ID);
  Folder := TPath.Combine(TPath.GetTempPath, 'OBJMaterialTest-' + GUIDToString(ID));
  ForceDirectories(TPath.Combine(Folder, 'materials'));
  OBJPath := TPath.Combine(Folder, 'model.obj');
  MTLPath := TPath.Combine(Folder, 'materials\model library.mtl');
  Scene := TvgScene.Create(nil); Loader := TvgSceneLoader_OBJ.Create(nil);
  BMP := TBitmap.Create;
  PNG := TPngImage.Create; JPEG := TJPEGImage.Create;
  try
    Loader.Scene := Scene; Loader.FileName := OBJPath;
    BMP.SetSize(2, 2); BMP.PixelFormat := pf24bit;
    BMP.Canvas.Pixels[0, 0] := clRed; BMP.Canvas.Pixels[1, 0] := clBlue;
    BMP.SaveToFile(TPath.Combine(ExtractFilePath(MTLPath), 'checker map.bmp'));
    PNG.Assign(BMP); PNG.SaveToFile(TPath.Combine(ExtractFilePath(MTLPath), 'checker map.png'));
    JPEG.Assign(BMP); JPEG.SaveToFile(TPath.Combine(ExtractFilePath(MTLPath), 'checker map.jpg'));
    try TestMaterials; TestGeometry; TestTextureFormatsAndShaders;
    except on E: Exception do begin Inc(Failures); Writeln(E.ClassName, ': ', E.Message); end; end;
  finally
    PNG.Free; JPEG.Free; BMP.Free; Loader.Free; Scene.Free;
    TDirectory.Delete(Folder, True);
  end;
  Writeln('Failures: ', Failures);
  if Failures <> 0 then Halt(1);
end.
