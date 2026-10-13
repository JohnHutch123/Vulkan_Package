program AppendSceneTest;

{$APPTYPE CONSOLE}

{ vgAppendSceneFile without a device: a file's stores join a scene that
  already has data, leaving that data alone - geometry, object IDs and
  texture descriptors intact; a failed load changes nothing; and appended
  stores can be instanced. }

uses
  System.SysUtils, System.Classes, System.IOUtils,
  Vcl.Graphics,
  PasVulkan.Math, PasVulkan.Math.Double,
  Vulkan_Components, Vulkan_Components_Lookups, Vulkan_Components_Camera,
  Vulkan_Components_Descriptors, Vulkan_Components_DataStore,
  Vulkan_Components_Scene_Renderer, Vulkan_Loader_OBJ, Vulkan_SceneLoaders,
  Vulkan_Instancing;

var
  Failures : Integer = 0;
  Folder   : string;

procedure Check(const Name: string; OK: Boolean);
begin
  if OK then Writeln('  ok   ', Name)
  else begin Inc(Failures); Writeln('  FAIL ', Name); end;
end;

function WriteFile(const aName, aText: string): string;
begin
  Result := TPath.Combine(Folder, aName);
  TFile.WriteAllText(Result, aText, TEncoding.ASCII);
end;

function Near(A, B: Double): Boolean;
begin Result := Abs(A - B) < 1E-5; end;

procedure TestAppend;
var
  Scene          : TvgScene;
  A              : TvgObjectStore;
  Added, Again   : TArray<TvgObjectStore>;
  Box            : TvgAABB;
  Warnings       : TArray<string>;
  IDA1, IDA2,
  IDB1, IDB2     : Cardinal;
  Raised         : Boolean;
  Tex            : TvgDescriptorArray_Texture;
  Copies         : TvgInstanceSet;
  M              : TvgMatrixArray;
  Loader         : TvgSceneLoader_OBJ;
begin
  Scene := TvgScene.Create(nil);
  try
    // What the scene has before: a unit quad.
    vgLoadSceneFile(Scene, WriteFile('quad.obj', 'v 0 0 0'#10'v 1 0 0'#10'v 1 1 0'#10'v 0 1 0'#10'f 1 2 3 4'#10));
    Check('the scene starts with one store', Scene.SceneData.Count = 1);
    A := Scene.SceneData[0];
    A.GetObjectInstanceObjID(0, 0, IDA1, IDA2);

    // A triangle well away from it, with a textured material.
    WriteFile('tri.mtl', 'newmtl Painted'#10'map_Kd checker.bmp'#10);
    Added := vgAppendSceneFile(Scene, WriteFile('tri.obj',
      'mtllib tri.mtl'#10'v 10 0 0'#10'v 11 0 0'#10'v 10 1 0'#10'vt 0 0'#10'vt 1 0'#10'vt 0 1'#10 +
      'usemtl Painted'#10'f 1/1 2/2 3/3'#10), Warnings);
    Check('one store appended and returned', Length(Added) = 1);
    Check('the scene now has both', (Scene.SceneData.Count = 2) and
      (Scene.SceneData.IndexOf(A) >= 0) and (Scene.SceneData.IndexOf(Added[0]) >= 0));
    Check('the appended store belongs to the scene', Added[0].Scene = Scene);
    Check('no warnings for a clean file', Length(Warnings) = 0);
    Check('the first store kept its four vertices', A.GetObjectVertexCount(0) = 4);
    Check('the appended store kept its three', Added[0].GetObjectVertexCount(0) = 3);
    Box := Added[0].GetObjectLocalBounds(0);
    Check('the appended geometry is where the file put it',
      Box.Valid and Near(Box.Min.x, 10) and Near(Box.Max.x, 11) and Near(Box.Max.y, 1));
    Added[0].GetObjectInstanceObjID(0, 0, IDB1, IDB2);
    A.GetObjectInstanceObjID(0, 0, IDA1, IDA2);
    Check('object IDs set and distinct', ((IDB1 <> 0) or (IDB2 <> 0)) and ((IDB1 <> IDA1) or (IDB2 <> IDA2)));
    Tex := nil;
    if Added[0].ObjectStoreRes.Descriptors.Count > 0 then
      Tex := TvgDescriptorArray_Texture(Added[0].ObjectStoreRes.Descriptors[0].Descriptor);
    Check('the texture came with it', Assigned(Tex) and Tex.TextureData[0].TextureFrame[0].HasTextureSource);

    // Twice is two sets, not one replacing the other.
    Again := vgAppendSceneFile(Scene, TPath.Combine(Folder, 'tri.obj'));
    Check('appending again adds another', (Length(Again) = 1) and (Again[0] <> Added[0]) and
      (Scene.SceneData.Count = 3));

    // A bad file: raises, and the scene is as it was.
    Raised := False;
    try vgAppendSceneFile(Scene, WriteFile('bad.obj', 'v 0 0 0'#10'f 1 2 9'#10));
    except on E: Exception do Raised := True; end;
    Check('a bad file raises', Raised);
    Check('...and leaves the scene alone', (Scene.SceneData.Count = 3) and (A.GetObjectVertexCount(0) = 4));

    // A loader already on a scene would clear it when pointed elsewhere.
    Loader := TvgSceneLoader_OBJ.Create(nil);
    try
      Loader.Scene := Scene;
      Raised := False;
      try vgAppendSceneFile(Scene, TPath.Combine(Folder, 'tri.obj'), Loader);
      except on E: EvgSceneLoaderError do Raised := True; end;
      Check('a loader with a scene is refused, nothing cleared', Raised and (Scene.SceneData.Count = 3));
    finally
      // Freed, not set to nil: setting Scene clears the scene it had.
      Loader.Free;
    end;

    // A caller's own loader, with no scene: used, then let go.
    Loader := TvgSceneLoader_OBJ.Create(nil);
    try
      Again := vgAppendSceneFile(Scene, TPath.Combine(Folder, 'tri.obj'), Loader);
      Check('a given loader is used and left with no scene', (Length(Again) = 1) and (Loader.Scene = nil));
    finally
      Loader.Free;
    end;

    // Appended stores repeat like any other.
    Copies := TvgInstanceSet.Create(Added);
    try
      SetLength(M, 5);
      for var I := 0 to High(M) do M[I] := TvgMatrix4x4S.Identity;
      Copies.SetMatrices(M);
      Check('appended store instanced: five copies', Added[0].GetObjectInstanceCount(0) = 5);
    finally
      Copies.Free;
    end;
  finally
    Scene.Free;
  end;
  Check('the scene frees appended stores with its own', True);
end;

var BMP: TBitmap; ID: TGUID;
begin
  CreateGUID(ID);
  Folder := TPath.Combine(TPath.GetTempPath, 'AppendSceneTest-' + GUIDToString(ID));
  ForceDirectories(Folder);
  BMP := TBitmap.Create;
  try
    BMP.SetSize(2, 2); BMP.PixelFormat := pf24bit;
    BMP.SaveToFile(TPath.Combine(Folder, 'checker.bmp'));
    try
      TestAppend;
    except
      on E: Exception do begin Inc(Failures); Writeln(E.ClassName, ': ', E.Message); end;
    end;
  finally
    BMP.Free;
    TDirectory.Delete(Folder, True);
  end;
  if Failures = 0 then Writeln('ALL CHECKS PASSED')
  else Writeln('Failures: ', Failures);
  if Failures <> 0 then Halt(1);
end.
