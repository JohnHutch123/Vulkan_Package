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

begin
  try Run;
  except on E: Exception do begin Inc(Failures); Writeln(E.ClassName, ': ', E.Message); end; end;
  Writeln('Failures: ', Failures);
  if Failures <> 0 then Halt(1);
end.
