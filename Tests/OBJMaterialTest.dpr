program OBJMaterialTest;
{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Math,
  Vcl.Graphics, Vcl.Imaging.pngimage, Vcl.Imaging.jpeg, Vulkan, PasVulkan.Math.Double,
  Vulkan_Components, Vulkan_Components_Lookups, Vulkan_Components_DataStore,
  Vulkan_Components_Descriptors, Vulkan_Components_Scene_Renderer,
  Vulkan_Components_Light, Vulkan_Components_TextureInspector, Vulkan_Components_Camera,
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

// A loaded store turned into an instanced one: one copy of the vertices, one
// matrix per copy, and the OBJInst vertex shader that reads the matrices.
procedure TestInstancing;
var S: TvgOBJObjectStore; Pipeline: TvgGraphicPipeline; Engine: TvgRenderEngine;
  A: TVkVertexInputAttributeDescription; Locations: set of Byte;
  ID1, ID2, Before1, Before2: Cardinal; D: TvgObjectData; M: TvgMatrix4x4S;
  Offset: Integer; Box: TvgAABB;
begin
  Load(Mesh + 'f 1 2 3 4');
  S := TvgOBJObjectStore(Scene.SceneData[0]);
  S.GetObjectInstanceObjID(0, 0, Before1, Before2);
  S.ChangeInstanceAttributes([idtObjID, idtMatrix]);
  S.GetObjectInstanceObjID(0, 0, ID1, ID2);
  Check('instancing: object ID kept through the new layout', (ID1 = Before1) and (ID2 = Before2));
  Check('instancing: one instance, vertices untouched',
    (S.GetObjectInstanceCount(0) = 1) and (S.GetObjectVertexCount(0) = 4));

  Locations := [];
  for A in S.GetAttributeDescriptions do
    if A.binding = 1 then Include(Locations, Byte(A.location));
  Check('instancing: object ID at 6, matrix columns at 7..10', Locations = [6, 7, 8, 9, 10]);

  // Every new instance starts as identity - zero would collapse it to the origin.
  D := S.GetObjectData(0);
  Offset := 0;
  for A in S.GetAttributeDescriptions do
    if (A.binding = 1) and (A.location = 7) then Offset := Integer(A.offset);
  Move(D.Instances[Offset], M, SizeOf(M));
  Check('instancing: existing instance gets an identity matrix', CompareMem(@M, @TvgMatrix4x4S.Identity, SizeOf(M)));
  S.AddObjectInstance(0);
  D := S.GetObjectData(0);
  Move(D.Instances[Integer(S.GetStride(1)) + Offset], M, SizeOf(M));
  Check('instancing: added instance gets an identity matrix', CompareMem(@M, @TvgMatrix4x4S.Identity, SizeOf(M)));

  // Two copies of the unit quad, at x+10 and y+20: the bound covers both.
  M := TvgMatrix4x4S.Identity; M.RawComponents[3, 0] := 10;
  S.SetObjectInstanceMatrix(0, 0, M);
  M := TvgMatrix4x4S.Identity; M.RawComponents[3, 1] := 20;
  S.SetObjectInstanceMatrix(0, 1, M);
  Box := S.GetObjectWorldBounds(0);
  Check('instancing: world bound is the union of the copies', Box.Valid and
    Near(Box.Min.x, 0) and Near(Box.Max.x, 11) and Near(Box.Min.y, 0) and Near(Box.Max.y, 21));

  Pipeline := TvgGraphicPipeline.Create(nil); Engine := TvgRenderEngine.Create(nil);
  try
    Pipeline.Renderer := Engine;
    Engine.ShaderUseDouble := False; Engine.SelectMode := smNone;
    TStoreAccess(S).ConfigureGraphicPipeline(Pipeline);
    Check('instancing: float shader variant', (Pipeline.VertexS.FileName = 'OBJInst_vert.spv') and (Pipeline.FragmentS.FileName = 'OBJ_frag.spv'));
    Engine.ShaderUseDouble := True; Engine.SelectMode := smImageBuffer;
    TStoreAccess(S).ConfigureGraphicPipeline(Pipeline);
    Check('instancing: double/picking shader variant', (Pipeline.VertexS.FileName = 'OBJInstDouble_vert.spv') and (Pipeline.FragmentS.FileName = 'OBJPickImage_frag.spv'));
  finally Pipeline.Free; Engine.Free; end;
  Check('instancing: OBJInst shaders shipped', FileExists(ShaderFolderPath + 'OBJInst_vert.spv') and
    FileExists(ShaderFolderPath + 'OBJInstDouble_vert.spv'));
end;

// The SHADING specialization constant a store's pipeline gets.
function ShadingConstant(Store: TvgOBJObjectStore): string;
var Pipeline: TvgGraphicPipeline; Engine: TvgRenderEngine; I: Integer;
begin
  Result := '';
  Pipeline := TvgGraphicPipeline.Create(nil); Engine := TvgRenderEngine.Create(nil);
  try
    Pipeline.Renderer := Engine;
    TStoreAccess(Store).ConfigureGraphicPipeline(Pipeline);
    for I := 0 to Pipeline.FragmentS.SpecialConst.Count - 1 do
      if Pipeline.FragmentS.SpecialConst[I].ConstantID = 9 then
        Result := Pipeline.FragmentS.SpecialConst[I].SpecTValue;
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
  // Flat shading is the shader's (from each triangle's own plane), so flat
  // faces share corners too, and carry smooth normals for a switch to smooth.
  Load(Mesh + 'v 0 0 1'#10's off'#10'f 1 2 3'#10'f 1 5 2');
  S := Scene.SceneData[0];
  Check('flat faces share common corners', S.GetObjectVertexCount(0) = 4);
  Check('flat faces still get smooth normals', Near(Attribute(S, 0, 2, 1), Sqrt(0.5)) and Near(Attribute(S, 0, 2, 2), Sqrt(0.5)));
  Check('no normals and smoothing off: starts flat', TvgOBJObjectStore(S).Shading = osFlat);
  Check('flat: SHADING constant 1', ShadingConstant(TvgOBJObjectStore(S)) = '1');
  Loader.SmoothWhenNoNormals := True;
  try
    Load(Mesh + 'v 0 0 1'#10's off'#10'f 1 2 3'#10'f 1 5 2');
    S := Scene.SceneData[0];
    Check('SmoothWhenNoNormals: starts smooth', TvgOBJObjectStore(S).Shading = osSmooth);
    Check('SmoothWhenNoNormals: same vertices', S.GetObjectVertexCount(0) = 4);
  finally Loader.SmoothWhenNoNormals := False; end;
  Load(Mesh + 'v 0 0 1'#10's 1'#10'f 1 2 3'#10'f 1 5 2');
  Check('smoothing group: starts smooth', TvgOBJObjectStore(Scene.SceneData[0]).Shading = osSmooth);
  Check('smooth: SHADING constant 2', ShadingConstant(TvgOBJObjectStore(Scene.SceneData[0])) = '2');

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

// Libraries and materials that are not found are not errors - the geometry
// loads grey - but the loader says so in Warnings, and vgLoadSceneFile hands
// them back.
procedure TestWarnings;
var W: TArray<string>;
  function Has(const Part: string): Boolean;
  var S: string;
  begin
    for S in Loader.Warnings do if Pos(Part, S) > 0 then Exit(True);
    Result := False;
  end;
begin
  TFile.WriteAllText(MTLPath, 'newmtl Painted'#10'Kd 0.4 0.5 0.6'#10, TEncoding.UTF8);
  Load('mtllib "materials/model library.mtl"'#10 + Mesh + 'usemtl Painted'#10'f 1 2 3');
  Check('clean load: no warnings', Length(Loader.Warnings) = 0);

  Load('mtllib Plants 190.mtl'#10 + Mesh + 'usemtl Leaf'#10'f 1 2 3');
  Check('missing library: one warning, named as written',
    Has('Material library "Plants 190.mtl" (line 1) not found') and
    (Length(Loader.Warnings) = 2));
  Check('...and its material too', Has('Material "Leaf" (usemtl, line'));

  Load('mtllib missing.mtl "materials/model library.mtl"'#10 + Mesh +
    'usemtl Painted'#10'f 1 2 3'#10'usemtl Absent'#10'f 1 3 4'#10'usemtl Painted'#10'f 2 3 4'#10'usemtl Absent'#10'f 1 2 4');
  Check('one of two libraries missing: just that one', Has('"missing.mtl"') and not Has('model library'));
  Check('a missing material reported once however often it is used',
    Has('Material "Absent"') and (Length(Loader.Warnings) = 2));
  Check('the found material is not reported', not Has('"Painted"'));

  Load(Mesh + 'usemtl Absent'#10'f 1 2 3');
  Check('usemtl with no library at all is reported', Has('Material "Absent"'));

  Load(Mesh + 'f 1 2 3');
  Check('warnings cleared by the next load', Length(Loader.Warnings) = 0);

  TFile.WriteAllText(OBJPath, 'mtllib none.mtl'#10 + Mesh + 'f 1 2 3', TEncoding.UTF8);
  vgLoadSceneFile(Scene, OBJPath, W);
  Check('vgLoadSceneFile hands back a temporary loader''s warnings',
    (Length(W) = 1) and (Pos('"none.mtl"', W[0]) > 0));
end;

// Tangent (location 4) and bitangent (5) of a vertex, its normal (2).
function Vec(Store: TvgObjectStore; Vertex, Location: Integer): TpvVector3D;
begin
  Result := TpvVector3D.Create(Attribute(Store, Vertex, Location, 0),
    Attribute(Store, Vertex, Location, 1), Attribute(Store, Vertex, Location, 2));
end;

function NearV(const V: TpvVector3D; X, Y, Z: Double): Boolean;
begin Result := (Abs(V.x - X) < 1e-4) and (Abs(V.y - Y) < 1e-4) and (Abs(V.z - Z) < 1e-4); end;

function DotV(const A, B: TpvVector3D): Double;
begin Result := A.x * B.x + A.y * B.y + A.z * B.z; end;

// Every vertex: unit tangent and bitangent, both perpendicular to the unit
// normal and to each other.
function FramesOrthonormal(Store: TvgObjectStore): Boolean;
var I, Stride: Integer; N, T, B: TpvVector3D; D: TvgObjectData;
  Offsets: array[0..5] of Integer; A: TVkVertexInputAttributeDescription;
  function Read(Vertex, Location: Integer): TpvVector3D;
  var V: array[0..2] of Single;
  begin
    Move(D.Vertices[Vertex * Stride + Offsets[Location]], V, SizeOf(V));
    Result := TpvVector3D.Create(V[0], V[1], V[2]);
  end;
begin
  // the vertex data once - GetObjectData copies it (Vec would per call)
  D := Store.GetObjectData(0);
  Stride := Integer(Store.GetStride(0));
  for A in Store.GetAttributeDescriptions do
    if (A.binding = 0) and (A.location <= 5) then Offsets[A.location] := Integer(A.offset);
  for I := 0 to Store.GetObjectVertexCount(0) - 1 do
  begin
    N := Read(I, 2); T := Read(I, 4); B := Read(I, 5);
    if (Abs(DotV(T, T) - 1) > 1e-3) or (Abs(DotV(B, B) - 1) > 1e-3) or
       (Abs(DotV(T, N)) > 1e-3) or (Abs(DotV(B, N)) > 1e-3) or (Abs(DotV(T, B)) > 1e-3) then
    begin
      Writeln(Format('       vertex %d: N %.4f %.4f %.4f  T %.4f %.4f %.4f  B %.4f %.4f %.4f',
        [I, N.x, N.y, N.z, T.x, T.y, T.z, B.x, B.y, B.z]));
      Exit(False);
    end;
  end;
  Result := True;
end;

// Tangent frames: +U and +V of the file's UVs, orthonormal with the normal.
procedure TestTangents;
const
  QuadUV = 'vt 0 0'#10'vt 1 0'#10'vt 1 1'#10'vt 0 1'#10;
var S: TvgObjectStore; I: Integer; OK: Boolean; A: TVkVertexInputAttributeDescription;
  T, B: TpvVector3D;
begin
  Load(Mesh + QuadUV + 'vn 0 0 1'#10'f 1/1/1 2/2/1 3/3/1 4/4/1');
  S := Scene.SceneData[0];
  OK := True;
  for I := 0 to S.GetObjectVertexCount(0) - 1 do
    OK := OK and NearV(Vec(S, I, 4), 1, 0, 0) and NearV(Vec(S, I, 5), 0, 1, 0);
  Check('tangent along +U, bitangent along +V', OK);

  Load(Mesh + 'vt 1 0'#10'vt 0 0'#10'vt 0 1'#10'vt 1 1'#10'vn 0 0 1'#10'f 1/1/1 2/2/1 3/3/1 4/4/1');
  S := Scene.SceneData[0];
  OK := True;
  for I := 0 to S.GetObjectVertexCount(0) - 1 do
    OK := OK and NearV(Vec(S, I, 4), -1, 0, 0) and NearV(Vec(S, I, 5), 0, 1, 0);
  Check('mirrored U: tangent flips, bitangent still along +V', OK);

  // U running up the quad and V back along it: a quarter turn
  Load(Mesh + 'vt 0 0'#10'vt 0 -1'#10'vt 1 -1'#10'vt 1 0'#10'vn 0 0 1'#10'f 1/1/1 2/2/1 3/3/1 4/4/1');
  S := Scene.SceneData[0];
  Check('rotated UVs rotate the frame',
    NearV(Vec(S, 0, 4), 0, 1, 0) and NearV(Vec(S, 0, 5), -1, 0, 0));

  Load(Mesh + QuadUV + 'vn 0 0 5'#10'f 1/1/1 2/2/1 3/3/1 4/4/1');
  S := Scene.SceneData[0];
  Check('a non-unit vn still gives a unit frame',
    NearV(Vec(S, 0, 4), 1, 0, 0) and NearV(Vec(S, 0, 5), 0, 1, 0) and FramesOrthonormal(S));

  Load(Mesh + 'vn 0.6 0 0.8'#10'f 1//1 2//1 3//1');
  S := Scene.SceneData[0];
  Check('no UVs: any unit tangent perpendicular to the normal', FramesOrthonormal(S));

  Load(Mesh + 'l 1 2 3 4'#10'p 1');
  Check('lines and points get frames too',
    FramesOrthonormal(Scene.SceneData[0]) and FramesOrthonormal(Scene.SceneData[1]));

  // Smooth normals on a bent strip: the tangent bends with the normal.
  Load('v 0 0 0'#10'v 1 0 0'#10'v 1 1 0'#10'v 0 1 0'#10'v 2 0 1'#10'v 2 1 1'#10 +
    'vt 0 0'#10'vt 1 0'#10'vt 1 1'#10'vt 0 1'#10'vt 2 0'#10'vt 2 1'#10 +
    's 1'#10'f 1/1 2/2 3/3 4/4'#10'f 2/2 5/5 6/6 3/3');
  S := Scene.SceneData[0];
  Check('smooth-shaded strip: frames orthonormal', FramesOrthonormal(S));
  T := Vec(S, 1, 4); B := Vec(S, 1, 5);
  Check('...the shared edge''s tangent leans between the two faces',
    (T.x > 0.5) and (T.z > 0.1) and NearV(B, 0, 1, 0));

  // The object ID comes after the frame, where OBJ_vert reads it.
  OK := False;
  for A in S.GetAttributeDescriptions do
    if A.binding = 1 then OK := A.location = 6;
  Check('object ID at location 6 (OBJ.vert)', OK);
end;

// The shipped Monstera sample (3ds Max export, tab-indented MTL with both
// d and Tr) loads with its materials.  Skipped where the OBJ is not present.
procedure TestRealSample;
var Path: string; W: TArray<string>; A, B: TvgOBJObjectStore;
begin
  Path := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)),
    '..\..\Samples\OBJ Files\Plant Monstera 01.obj'));
  if not FileExists(Path) then
  begin
    Writeln('  skip Plant Monstera 01.obj not found: ', Path);
    Exit;
  end;
  vgLoadSceneFile(Scene, Path, W);
  Check('Monstera: no warnings (its MTL is found)', Length(W) = 0);
  Check('Monstera: one store per material', Scene.SceneData.Count = 2);
  if Scene.SceneData.Count <> 2 then Exit;
  A := TvgOBJObjectStore(Scene.SceneData[0]);
  B := TvgOBJObjectStore(Scene.SceneData[1]);
  Check('Monstera: materials from "Plants 190.mtl"',
    SameText(ExtractFileName(A.Material.LibraryFile), 'Plants 190.mtl') and
    SameText(ExtractFileName(B.Material.LibraryFile), 'Plants 190.mtl'));
  Check('Monstera: leaf material purple',
    (A.Material.Name = 'wire_108008136') and Near(A.Material.Diffuse.x, 0.4235) and
    Near(A.Material.Diffuse.y, 0.0314) and Near(A.Material.Diffuse.z, 0.5333));
  Check('Monstera: second material black',
    (B.Material.Name = 'wire_000000000') and Near(B.Material.Diffuse.x, 0) and Near(B.Material.Diffuse.z, 0));
  Check('Monstera: Ns, Ks and opacity (d 1, Tr 0)',
    Near(A.Material.Shininess, 32) and Near(A.Material.Specular.x, 0.35) and Near(A.Material.Opacity, 1));
  Check('Monstera: the diffuse colour reaches the vertices',
    Near(Attribute(A, 0, 1, 0), 0.4235) and Near(Attribute(A, 0, 1, 2), 0.5333));
  Check('Monstera: triangle counts', (A.GetObjectIndexCount(0) = 3 * 65508) and (B.GetObjectIndexCount(0) = 3 * 6272));
  Check('Monstera: every tangent frame orthonormal (leaf)', FramesOrthonormal(A));
  Check('Monstera: every tangent frame orthonormal (second)', FramesOrthonormal(B));
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
    try TestMaterials; TestGeometry; TestTextureFormatsAndShaders; TestWarnings; TestTangents; TestInstancing; TestRealSample;
    except on E: Exception do begin Inc(Failures); Writeln(E.ClassName, ': ', E.Message); end; end;
  finally
    PNG.Free; JPEG.Free; BMP.Free; Loader.Free; Scene.Free;
    TDirectory.Delete(Folder, True);
  end;
  Writeln('Failures: ', Failures);
  if Failures <> 0 then Halt(1);
end.
