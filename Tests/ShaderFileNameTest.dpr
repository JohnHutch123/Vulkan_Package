program ShaderFileNameTest;
{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.IOUtils,
  Vulkan_Components, Vulkan_Components_Scene_Renderer;

type
  TStoreAccess = class(TvgObjectStore);
  TShaderAccess = class(TvgShaderModule);

var
  Failures: Integer = 0;

procedure Check(const Name: string; OK: Boolean);
begin
  if OK then Writeln('  ok   ', Name)
  else begin Inc(Failures); Writeln('  FAIL ', Name); end;
end;

procedure Run;
var
  Scene: TvgScene;
  Store: TvgObjectStore;
  Pipeline: TvgGraphicPipeline;
  Shader: TvgShaderModule;
  ID: TGUID;
  MissingBase, MissingName, ExistingFile: string;
begin
  CreateGUID(ID);
  MissingBase := 'NotDeployed-' + GUIDToString(ID);
  MissingName := MissingBase + '_vert.spv';
  ExistingFile := TPath.GetTempFileName;
  Shader := TvgShaderModule.Create(nil);
  Pipeline := TvgGraphicPipeline.Create(nil);
  Scene := TvgScene.Create(nil);
  try
    // A file's existence must not determine whether its name is remembered.
    Shader.FileName := MissingName;
    Check('missing shader filename is retained', Shader.FileName = MissingName);
    Shader.FileName := ExistingFile;
    Check('existing path retained', Shader.FileName = ExistingFile);
    Shader.FileName := MissingName;
    Check('missing replacement does not retain old path', Shader.FileName = MissingName);
    Shader.FileName := '';
    Check('filename can be cleared', Shader.FileName = '');

    Check('undeployed pipeline shader names can be built',
      Pipeline.BuildShaderNames(MissingBase, MissingBase, MissingBase));
    Check('vertex name assigned', Pipeline.VertexS.FileName = MissingBase + '_vert.spv');
    Check('geometry name assigned', Pipeline.GeometryS.FileName = MissingBase + '_geom.spv');
    Check('fragment name assigned', Pipeline.FragmentS.FileName = MissingBase + '_frag.spv');

    if not Scene.Load_Begin then raise Exception.Create('Load_Begin refused');
    try
      Store := TvgObjectStore.Create(nil);
      Scene.AddDataStore(Store);
      Store.BaseVertName := MissingBase;
      Store.BaseFragName := MissingBase;
    finally Scene.Load_End; end;
    Pipeline.VertexS.FileName := '';
    Pipeline.FragmentS.FileName := '';
    TStoreAccess(Store).ConfigureGraphicPipeline(Pipeline);
    Check('loaded store configures undeployed vertex shader', Pipeline.VertexS.FileName = MissingBase + '_vert.spv');
    Check('loaded store configures undeployed fragment shader', Pipeline.FragmentS.FileName = MissingBase + '_frag.spv');

    // This fails before device access: assigning a name is not activation.
    Shader.FileName := MissingName;
    Check('missing file cannot enable shader', not TShaderAccess(Shader).SetEnabled);
    Check('failed enable preserves requested filename', Shader.FileName = MissingName);
    Shader.FileName := '';
    Check('empty filename cannot enable shader', not TShaderAccess(Shader).SetEnabled);
  finally
    Scene.Free; Pipeline.Free; Shader.Free;
    DeleteFile(ExistingFile);
  end;
end;

procedure RunLookup;
var
  Root, A, B, Sub, TempSub, Name, Found, OldFolder: string;
  ID: TGUID;
  Folders: TArray<string>;
  I, CountRepo: Integer;
begin
  OldFolder := ShaderFolderPath;
  CreateGUID(ID);
  Name := 'LookupTest-' + Copy(GUIDToString(ID), 2, 36) + '_vert.spv';
  Root := TPath.Combine(TPath.GetTempPath, 'vgShaderLookup-' + Copy(GUIDToString(ID), 2, 8));
  A := TPath.Combine(Root, 'A');
  B := TPath.Combine(Root, 'B');
  Sub := TPath.Combine(B, 'nested');
  TempSub := TPath.Combine(TPath.GetTempPath, 'vgShaderLookupSub-' + Copy(GUIDToString(ID), 2, 8));
  ForceDirectories(A); ForceDirectories(Sub); ForceDirectories(TempSub);
  try
    // The repository's shaders are found from a build under the checkout,
    // whatever ShaderFolderPath says.
    ShaderFolderPath := A + '\';
    Found := vgFindShaderFile('OBJ_vert.spv');
    Check('repo VulkanShaders found above the exe', SameText(ExtractFileName(ExtractFileDir(Found)), 'VulkanShaders'));
    Check('OBJ_frag.spv found too', vgFindShaderFile('OBJ_frag.spv') <> '');
    Folders := vgShaderSearchFolders;
    Check('ShaderFolderPath searched first', SameText(Folders[0], A));
    CountRepo := 0;
    for I := 0 to High(Folders) do
      if SameText(ExtractFileName(Folders[I]), 'VulkanShaders') and
         TFile.Exists(TPath.Combine(Folders[I], 'OBJ_vert.spv')) then Inc(CountRepo);
    Check('each folder listed once', CountRepo = 1);

    // ShaderFolderPath wins over a copy elsewhere; subfolders of it are searched.
    TFile.WriteAllText(TPath.Combine(Sub, Name), 'b');
    ShaderFolderPath := B + '\';
    Found := vgFindShaderFile(Name);
    Check('found in a subfolder of ShaderFolderPath', SameText(Found, TPath.Combine(Sub, Name)));
    TFile.WriteAllText(TPath.Combine(B, Name), 'b');
    vgClearShaderFileCache;
    Check('a direct hit beats a subfolder', SameText(vgFindShaderFile(Name), TPath.Combine(B, Name)));

    // The cache follows the file: deleted -> searched again.
    DeleteFile(TPath.Combine(B, Name));
    Check('no subfolder search when not asked', vgFindShaderFile(Name, '', False) = '');
    Check('cached hit re-checked after delete', SameText(vgFindShaderFile(Name), TPath.Combine(Sub, Name)));
    DeleteFile(TPath.Combine(Sub, Name));
    Check('gone everywhere: not found', vgFindShaderFile(Name) = '');
    TFile.WriteAllText(TPath.Combine(Sub, Name), 'b');
    Check('a miss is not cached: deployed later is found', vgFindShaderFile(Name) <> '');

    // Changing ShaderFolderPath changes the answer, cache or not.
    TFile.WriteAllText(TPath.Combine(A, Name), 'a');
    ShaderFolderPath := A + '\';
    Check('new ShaderFolderPath used', SameText(vgFindShaderFile(Name), TPath.Combine(A, Name)));

    // TEMP is searched, but never its subfolders (that used to scan all of TEMP).
    DeleteFile(TPath.Combine(A, Name)); DeleteFile(TPath.Combine(Sub, Name));
    TFile.WriteAllText(TPath.Combine(TempSub, Name), 't');
    Check('TEMP subfolders not scanned', vgFindShaderFile(Name) = '');
    TFile.WriteAllText(TPath.Combine(TPath.GetTempPath, Name), 't');
    Check('TEMP itself searched', vgFindShaderFile(Name) <> '');
    DeleteFile(TPath.Combine(TPath.GetTempPath, Name));

    // A shader module enables only when the file resolves; the legacy helper agrees.
    Check('legacy helper uses the same lookup',
      SameText(FileExistsInVariousLocations('OBJ_vert.spv', ShaderFolderPath, True), vgFindShaderFile('OBJ_vert.spv')));
  finally
    ShaderFolderPath := OldFolder;
    vgClearShaderFileCache;
    TDirectory.Delete(Root, True);
    TDirectory.Delete(TempSub, True);
  end;
end;

begin
  try Run; RunLookup;
  except on E: Exception do begin Inc(Failures); Writeln(E.ClassName, ': ', E.Message); end; end;
  Writeln('Failures: ', Failures);
  if Failures <> 0 then Halt(1);
end.
