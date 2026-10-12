program OBJLoaderTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.IOUtils,
  PasVulkan.Math.Double, Vulkan_Components_Lookups,
  Vulkan_Components_Scene_Renderer, Vulkan_SceneLoaders, Vulkan_Loader_OBJ;

const
  Vertices = 'v 0 0 0'#10'v 2.5 0 0'#10'v 2.5 3 0'#10'v 0 3 0'#10;
var
  Failures: Integer = 0;
  Scene: TvgScene;
  Loader: TvgSceneLoader_OBJ;
  FileName: string;

procedure Check(const Name: string; OK: Boolean);
begin
  if OK then Writeln('  ok   ', Name)
  else begin Writeln('  FAIL ', Name); Inc(Failures); end;
end;

procedure Source(const Text: string);
begin
  TFile.WriteAllText(FileName, Text, TEncoding.UTF8);
end;

procedure Reject(const Name, Text: string);
var
  OldStore: TvgObjectStore;
  Raised: Boolean;
begin
  OldStore := Scene.SceneData[0];
  Source(Text);
  Raised := False;
  try Loader.LoadScene;
  except on E: EvgOBJError do Raised := True; end;
  Check(Name, Raised);
  Check(Name + ' preserves scene',
    (Scene.SceneData.Count = 1) and (Scene.SceneData[0] = OldStore));
end;

procedure Run;
var
  Info: TvgSceneLoaderInfo;
  Store: TvgObjectStore;
  Indices: TArray<Cardinal>;
  BMin, BMax: TpvVector3D;
  OldDecimal: Char;
  Raised: Boolean;
  Form, TeaPot: string;
begin
  Check('registered for case-insensitive OBJ extension',
    FindSceneLoaderForFile('mesh.OBJ', Info));
  Check('registered class', Info.LoaderClass = TvgSceneLoader_OBJ);
  Check('published file property', Info.FileNameProp = 'FileName');
  Source('# triangle'#10 + Vertices + 'f 1 2 3 # comment'#10);
  vgLoadSceneFile(Scene, FileName);
  Check('registry loads one store', Scene.SceneData.Count = 1);
  Store := Scene.SceneData[0];
  Check('one object', Store.ObjectCount = 1);
  Check('three referenced positions', Store.GetObjectVertexCount(0) = 3);
  Check('triangle topology', Store.Topology = TRIANGLE_LIST);
  Check('one triangle', Store.GetObjectIndexCount(0) = 3);
  Check('one object-ID instance', Store.GetObjectInstanceCount(0) = 1);
  Check('scene bounds', Scene.GetDataBounds(BMin, BMax) and
    (Abs(BMax.x - 2.5) < 1e-6) and (Abs(BMax.y - 3) < 1e-6));

  OldDecimal := FormatSettings.DecimalSeparator;
  try
    FormatSettings.DecimalSeparator := ',';
    Source(Vertices + 'g ignored'#10'f -4 -3 -2 -1'#10);
    Loader.LoadScene;
  finally
    FormatSettings.DecimalSeparator := OldDecimal;
  end;
  Check('reload replaces store', Scene.SceneData.Count = 1);
  Store := Scene.SceneData[0];
  Indices := Store.GetObjectIndices(0);
  Check('negative-index quad triangulated', Length(Indices) = 6);
  Check('fan order preserves winding',
    (Indices[0] = 0) and (Indices[1] = 1) and (Indices[2] = 2) and
    (Indices[3] = 0) and (Indices[4] = 2) and (Indices[5] = 3));
  Check('dot decimals regardless of locale',
    Abs(Store.GetObjectVertexPosition(0, 1).x - 2.5) < 1e-6);
  for Form in ['f 1/1 2/2 3/3', 'f 1//1 2//1 3//1',
    'f 1/1/1 2/2/1 3/3/1'] do
  begin
    Source(Vertices + 'vt 0 0'#10'vt 1 0'#10'vt 1 1'#10'vn 0 0 1'#10 + Form);
    Loader.LoadScene;
    Check('accepts ' + Form, Scene.SceneData[0].GetObjectIndexCount(0) = 3);
  end;
  Source('v 0 0 0'#10'v 5 0 0 2'#10'v 0 3 0'#10#9'f'#9'1'#9'2'#9'3');
  Loader.LoadScene;
  Check('homogeneous vertex and tabs',
    Abs(Scene.SceneData[0].GetObjectVertexPosition(0, 1).x - 2.5) < 1e-6);
  Source('v 0 0 0 1 0 0'#10'v 2.5 0 0 0 1 0'#10'v 0 3 0 0 0 1'#10'f 1 2 3');
  Loader.LoadScene;
  Check('x y z r g b vertex colours accepted',
    (Scene.SceneData[0].GetObjectIndexCount(0) = 3) and
    (Abs(Scene.SceneData[0].GetObjectVertexPosition(0, 1).x - 2.5) < 1e-6));

  Reject('zero index', Vertices + 'f 0 2 3');
  Reject('positive index beyond vertices', Vertices + 'f 1 2 5');
  Reject('negative index beyond vertices', Vertices + 'f -5 -2 -1');
  Reject('short face', Vertices + 'f 1 2');
  Reject('invalid vertex', 'v bad 0 0'#10 + Vertices + 'f 1 2 3');
  Reject('overflow coordinate', 'v 1e100 0 0'#10 + Vertices + 'f 1 2 3');
  Reject('zero weight', 'v 1 0 0 0'#10 + Vertices + 'f 1 2 3');
  Reject('six-value vertex', 'v 1 0 0 1 0'#10 + Vertices + 'f 1 2 3');
  Reject('invalid vertex colour', 'v 1 0 0 1 x 0'#10 + Vertices + 'f 1 2 3');
  Reject('invalid corner', Vertices + 'f 1/ 2 3');
  Reject('no faces', Vertices);
  Reject('empty file', '');
  Source(Vertices + 'f 1 2 3');
  Loader.LoadScene;
  Check('successful load after errors', Scene.SceneData[0].GetObjectIndexCount(0) = 3);

  // A real exported model, when the sample is present.
  TeaPot := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)),
    '..\..\Samples\OBJ Files\TeaPot.obj'));
  if ParamCount > 0 then TeaPot := ParamStr(1);
  if FileExists(TeaPot) then
  begin
    vgLoadSceneFile(Scene, TeaPot);
    Store := Scene.SceneData[0];
    Check('TeaPot.obj: vertices include flat-normal splits', Store.GetObjectVertexCount(0) >= 3644);
    Check('TeaPot.obj: 6320 triangles', Store.GetObjectIndexCount(0) = 3 * 6320);
    Check('TeaPot.obj: bounds', Scene.GetDataBounds(BMin, BMax) and
      (BMin.x < -2.9) and (BMax.x > 3.3) and (BMax.y > 3));
    // back to the one triangle the checks below expect
    Loader.LoadScene;
  end
  else
    Writeln('  skip TeaPot.obj not found: ', TeaPot);

  Raised := False;
  try Loader.StoreScene;
  except on E: EvgOBJError do Raised := True; end;
  Check('saving explicitly rejected', Raised);
  Check('saving did not change file', TFile.ReadAllText(FileName) = Vertices + 'f 1 2 3');
  Loader.FileName := FileName + '.missing';
  Raised := False;
  try Loader.LoadScene;
  except on E: EFOpenError do Raised := True; end;
  Check('missing file reported', Raised);
  Check('missing file preserves geometry', Scene.SceneData[0].GetObjectIndexCount(0) = 3);
  Loader.FileName := '';
  Raised := False;
  try Loader.LoadScene;
  except on E: EvgOBJError do Raised := True; end;
  Check('empty filename reported', Raised);
end;

begin
  FileName := TPath.GetTempFileName;
  Scene := TvgScene.Create(nil);
  Loader := TvgSceneLoader_OBJ.Create(nil);
  try
    try
      Loader.LoadScene;
      Check('missing scene reported', False);
    except on E: EvgOBJError do Check('missing scene reported', True); end;
    Loader.Scene := Scene;
    Loader.FileName := FileName;
    // The helper chooses by extension; use a separate .obj path.
    DeleteFile(FileName);
    FileName := FileName + '.obj';
    Loader.FileName := FileName;
    try Run;
    except on E: Exception do begin
      Writeln(E.ClassName, ': ', E.Message); Inc(Failures);
    end; end;
  finally
    Loader.Free;
    Scene.Free;
    DeleteFile(FileName);
  end;
  Writeln('Failures: ', Failures);
  if Failures <> 0 then Halt(1);
end.
