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
  Repo, Root, A, B, Sub, Sibling, Deep, ExeDir, Name, OldFolder: string;
  ID: TGUID;
  Folders: TArray<string>;
begin
  OldFolder := ShaderFolderPath;
  ExeDir := ExtractFileDir(ParamStr(0));
  Repo := IncludeTrailingPathDelimiter(TPath.GetFullPath(TPath.Combine(ExeDir, '..\..\VulkanShaders')));
  CreateGUID(ID);
  Name := 'LookupTest-' + Copy(GUIDToString(ID), 2, 36) + '_vert.spv';
  Root := TPath.Combine(TPath.GetTempPath, 'vgShaderLookup-' + Copy(GUIDToString(ID), 2, 8));
  A := TPath.Combine(Root, 'A');
  B := TPath.Combine(Root, 'B');
  Sub := TPath.Combine(B, 'nested');
  Sibling := TPath.Combine(TPath.Combine(Root, 'Vulkan_Package'), 'VulkanShaders');
  Deep := TPath.Combine(Root, 'Vulkan_Package_PRO\Tests\TestVulkan\Win64\Debug');
  ForceDirectories(A); ForceDirectories(Sub); ForceDirectories(Sibling); ForceDirectories(Deep);
  ForceDirectories(TPath.Combine(Root, 'Vulkan_Package\RunTime_Src'));
  TFile.WriteAllText(TPath.Combine(Root, 'Vulkan_Package\RunTime_Src\Vulkan_Components.pas'), '');
  try
    // Out of the box: this package's VulkanShaders, and nothing else.
    Check('ShaderFolderPath starts as the package''s VulkanShaders', SameText(OldFolder, Repo));
    Check('vgDefaultShaderFolder finds it from the exe', SameText(vgDefaultShaderFolder, Repo));
    Check('it is recognised as the package folder', vgIsPackageShaderFolder(Repo));
    Check('a folder without RunTime_Src beside it is not', not vgIsPackageShaderFolder(A));
    Folders := vgShaderSearchFolders;
    Check('the only folder searched', (Length(Folders) = 1) and SameText(IncludeTrailingPathDelimiter(Folders[0]), Repo));
    Check('OBJ_vert.spv found there', SameText(vgFindShaderFile('OBJ_vert.spv'), Repo + 'OBJ_vert.spv'));
    Check('a sibling Vulkan_Package checkout is found (PRO)',
      SameText(vgLocatePackageShaderFolder(Deep), IncludeTrailingPathDelimiter(Sibling)));
    Check('nothing found where there is no package', vgLocatePackageShaderFolder(TPath.GetTempPath) = '');

    // Not the exe folder, not TEMP (ProgramData, Program Files and Documents
    // went with them).
    TFile.WriteAllText(TPath.Combine(ExeDir, Name), 'x');
    TFile.WriteAllText(TPath.Combine(TPath.GetTempPath, Name), 'x');
    Check('exe folder not searched', vgFindShaderFile(Name) = '');
    Check('TEMP not searched', vgFindShaderFile(Name) = '');
    DeleteFile(TPath.Combine(ExeDir, Name));
    DeleteFile(TPath.Combine(TPath.GetTempPath, Name));

    // Subfolders of ShaderFolderPath, after the folder itself.
    TFile.WriteAllText(TPath.Combine(Sub, Name), 'b');
    ShaderFolderPath := B + '\';
    Check('found in a subfolder of ShaderFolderPath', SameText(vgFindShaderFile(Name), TPath.Combine(Sub, Name)));
    TFile.WriteAllText(TPath.Combine(B, Name), 'b');
    vgClearShaderFileCache;
    Check('a direct hit beats a subfolder', SameText(vgFindShaderFile(Name), TPath.Combine(B, Name)));

    // The cache follows the file.
    DeleteFile(TPath.Combine(B, Name));
    Check('no subfolder search when not asked', vgFindShaderFile(Name, '', False) = '');
    Check('cached hit re-checked after delete', SameText(vgFindShaderFile(Name), TPath.Combine(Sub, Name)));
    DeleteFile(TPath.Combine(Sub, Name));
    Check('gone: not found', vgFindShaderFile(Name) = '');
    TFile.WriteAllText(TPath.Combine(Sub, Name), 'b');
    Check('a miss is not cached: added later is found', vgFindShaderFile(Name) <> '');

    // AdditionalShaderFolders come after ShaderFolderPath.
    TFile.WriteAllText(TPath.Combine(A, Name), 'a');
    TFile.WriteAllText(TPath.Combine(B, Name), 'b');
    AdditionalShaderFolders := [A];
    Check('ShaderFolderPath beats AdditionalShaderFolders', SameText(vgFindShaderFile(Name), TPath.Combine(B, Name)));
    DeleteFile(TPath.Combine(B, Name)); DeleteFile(TPath.Combine(Sub, Name));
    Check('AdditionalShaderFolders searched', SameText(vgFindShaderFile(Name), TPath.Combine(A, Name)));
    AdditionalShaderFolders := nil;

    // A new ShaderFolderPath takes effect at once; '' finds the package again.
    ShaderFolderPath := A + '\';
    Check('new ShaderFolderPath used', SameText(vgFindShaderFile(Name), TPath.Combine(A, Name)));
    ShaderFolderPath := '';
    Check('blank ShaderFolderPath refilled with the package folder',
      SameText(vgFindShaderFile('OBJ_frag.spv'), Repo + 'OBJ_frag.spv') and SameText(ShaderFolderPath, Repo));

    Check('legacy helper uses the same lookup',
      SameText(FileExistsInVariousLocations('OBJ_vert.spv', '', True), vgFindShaderFile('OBJ_vert.spv')));
  finally
    ShaderFolderPath := OldFolder;
    AdditionalShaderFolders := nil;
    vgClearShaderFileCache;
    TDirectory.Delete(Root, True);
  end;
end;

begin
  try Run; RunLookup;
  except on E: Exception do begin Inc(Failures); Writeln(E.ClassName, ': ', E.Message); end; end;
  Writeln('Failures: ', Failures);
  if Failures <> 0 then Halt(1);
end.
