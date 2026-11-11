program SkyBoxTest;

{$APPTYPE CONSOLE}

{ Vulkan_SkyBox with no Vulkan device: where the sun and moon are, the
  generated panoramas, and the sky's store coming and going with its scene.

  SkyBoxTest <folder> also writes the two panoramas there, as SkyDay.bmp and
  SkyNight.bmp, to look at. }

uses
  System.SysUtils,
  System.Classes,
  System.Math,
  System.DateUtils,
  System.Diagnostics,
  Vulkan,
  PasVulkan.Math,
  PasVulkan.Math.Double,
  Vulkan_Components_Lookups,
  Vulkan_Components,
  Vulkan_Components_Descriptors,
  Vulkan_Components_DataStore,
  Vulkan_Components_Scene_Renderer,
  Vulkan_WorldAxes,
  Vulkan_Components_Camera,
  Vulkan_SkyBox;

var
  Failures : Integer = 0;

procedure Check(const Name: string; Got, Expect: Boolean);
begin
  if Got = Expect then
    Writeln(Format('  ok   %-52s %s', [Name, BoolToStr(Got, True)]))
  else
  begin
    Writeln(Format('  FAIL %-52s got %s expected %s',
      [Name, BoolToStr(Got, True), BoolToStr(Expect, True)]));
    Inc(Failures);
  end;
end;

procedure CheckNum(const Name: string; Got, Expect, Tol: Double);
begin
  if Abs(Got - Expect) <= Tol then
    Writeln(Format('  ok   %-52s %.3f', [Name, Got]))
  else
  begin
    Writeln(Format('  FAIL %-52s got %.3f expected %.3f +/- %.3f', [Name, Got, Expect, Tol]));
    Inc(Failures);
  end;
end;

function Dot(const A, B: TpvVector3D): Double;
begin
  Result := A.x * B.x + A.y * B.y + A.z * B.z;
end;

procedure TestSun;
var
  D      : TpvVector3D;
  Az, El : Double;
begin
  Writeln('--- sun ---');

  // Greenwich, the June solstice, at its solar noon: as high as it gets
  // there, 90 - latitude + the sun's declination, and due south.
  D := vgSunDirection(EncodeDateTime(2024, 6, 21, 12, 2, 0, 0), 51.4779, 0);
  vgSkyAngles(D, Az, El);
  CheckNum('Greenwich solstice noon: elevation', El, 61.96, 0.15);
  CheckNum('Greenwich solstice noon: azimuth', Az, 180, 1.5);

  // The same night, twelve hours on: below the northern horizon.
  D := vgSunDirection(EncodeDateTime(2024, 6, 21, 0, 2, 0, 0), 51.4779, 0);
  vgSkyAngles(D, Az, El);
  CheckNum('Greenwich solstice midnight: elevation', El, -15.08, 0.15);
  Check('Greenwich solstice midnight: to the north', D.z > 0.9, True);

  // Sydney, the December solstice, solar noon: the sun is to the north.
  D := vgSunDirection(EncodeDateTime(2024, 12, 21, 1, 53, 0, 0), -33.87, 151.21);
  vgSkyAngles(D, Az, El);
  CheckNum('Sydney solstice noon: elevation', El, 79.57, 0.2);
  Check('Sydney solstice noon: to the north', D.z > 0, True);

  // The equator at an equinox: the sun rises due east at six.
  D := vgSunDirection(EncodeDateTime(2024, 3, 20, 6, 7, 0, 0), 0, 0);
  vgSkyAngles(D, Az, El);
  CheckNum('equator equinox sunrise: elevation', El, 0, 1.0);
  CheckNum('equator equinox sunrise: azimuth', Az, 90, 1.0);

  // ... and is overhead at noon.
  D := vgSunDirection(EncodeDateTime(2024, 3, 20, 12, 7, 0, 0), 0, 0);
  vgSkyAngles(D, Az, El);
  Check('equator equinox noon: overhead', El > 88.5, True);

  // West in the afternoon.
  D := vgSunDirection(EncodeDateTime(2024, 3, 20, 16, 0, 0, 0), 0, 0);
  Check('equator equinox afternoon: to the west', D.x < -0.8, True);
end;

procedure TestMoon;
var
  S, M : TpvVector3D;
begin
  Writeln('--- moon ---');

  // Full: opposite the sun.  New: beside it.  (The moon's path is tilted
  // five degrees to the sun's, so neither is exact.)
  S := vgSunDirection (EncodeDateTime(2024, 6, 22, 1, 8, 0, 0), 40, 0);
  M := vgMoonDirection(EncodeDateTime(2024, 6, 22, 1, 8, 0, 0), 40, 0);
  Check('full moon 2024-06-22: opposite the sun', Dot(S, M) < -0.985, True);

  S := vgSunDirection (EncodeDateTime(2024, 6, 6, 12, 38, 0, 0), 40, 0);
  M := vgMoonDirection(EncodeDateTime(2024, 6, 6, 12, 38, 0, 0), 40, 0);
  Check('new moon 2024-06-06: beside the sun', Dot(S, M) > 0.985, True);

  // First quarter: a right angle away.
  S := vgSunDirection (EncodeDateTime(2024, 6, 14, 5, 18, 0, 0), 40, 0);
  M := vgMoonDirection(EncodeDateTime(2024, 6, 14, 5, 18, 0, 0), 40, 0);
  CheckNum('first quarter 2024-06-14: at right angles', Dot(S, M), 0, 0.06);
end;

procedure TestDirections;
var
  D      : TpvVector3D;
  Az, El : Double;
  Was    : TvgAxisConvention;
begin
  Writeln('--- directions ---');

  D := vgSkyDirection(90, 0);
  Check('azimuth 90 is east', (Abs(D.x - 1) < 1e-9) and (Abs(D.y) < 1e-9) and (Abs(D.z) < 1e-9), True);
  D := vgSkyDirection(0, 0);
  Check('azimuth 0 is north', Abs(D.z - 1) < 1e-9, True);
  D := vgSkyDirection(123, 90);
  Check('elevation 90 is up', Abs(D.y - 1) < 1e-9, True);

  vgSkyAngles(vgSkyDirection(217.5, 33.25), Az, El);
  CheckNum('angles round trip: azimuth', Az, 217.5, 1e-6);
  CheckNum('angles round trip: elevation', El, 33.25, 1e-6);

  Was := vgAxisConvention;
  try
    if vgSetAxisConvention(acYUp) then
    begin
      D := vgSkyToWorld(TpvVector3D.Create(0, 1, 0));
      Check('Y-up: up is +Y', Abs(D.y - 1) < 1e-9, True);
      D := vgSkyToWorld(TpvVector3D.Create(0, 0, 1));
      Check('Y-up: north is -Z', Abs(D.z + 1) < 1e-9, True);
    end;
    if vgSetAxisConvention(acZUp) then
    begin
      D := vgSkyToWorld(TpvVector3D.Create(0, 1, 0));
      Check('Z-up: up is +Z', Abs(D.z - 1) < 1e-9, True);
      D := vgSkyToWorld(TpvVector3D.Create(0, 0, 1));
      Check('Z-up: north is +Y', Abs(D.y - 1) < 1e-9, True);
      D := vgSkyToWorld(TpvVector3D.Create(1, 0, 0));
      Check('Z-up: east is +X', Abs(D.x - 1) < 1e-9, True);
    end;
  finally
    vgSetAxisConvention(Was);
  end;
end;

// The widest difference between the picture's left and right edge columns,
// 0 .. 255: the panorama has to join up round the back.
function SeamError(aBMP: TMemoryStream): Integer;
var
  P             : PByte;
  W, H, Stride  : Integer;
  Y, C          : Integer;
  L, R          : PByte;
begin
  Result := 0;
  P := aBMP.Memory;
  W := PInteger(P + 18)^;
  H := PInteger(P + 22)^;
  Stride := ((W * 3 + 3) div 4) * 4;
  for Y := 0 to H - 1 do
  begin
    L := P + 54 + Y * Stride;
    R := L + (W - 1) * 3;
    for C := 0 to 2 do
      Result := Max(Result, Abs(Integer((L + C)^) - Integer((R + C)^)));
  end;
end;

procedure TestPanoramas(const aFolder: String);
var
  A, B  : TMemoryStream;
  Watch : TStopwatch;
  W     : Integer;
begin
  Writeln('--- panoramas ---');
  A := TMemoryStream.Create;
  B := TMemoryStream.Create;
  try
    W := 1024;
    if aFolder <> '' then
      W := VG_SKY_TEXTURE_WIDTH;     // the night panorama as an application gets it

    Watch := TStopwatch.StartNew;
    vgSkyGenerateDay(W, A);
    Writeln(Format('       day   %d x %d in %d ms', [W, W div 2, Watch.ElapsedMilliseconds]));
    Check('day: a BMP file', (A.Size > 54) and (PWord(A.Memory)^ = $4D42), True);
    Check('day: of the size asked for', A.Size = 54 + Int64(W) * (W div 2) * 3, True);
    // Clouds differ a little from one column to the next; a seam would be a
    // jump.
    Check('day: joins up at the seam', SeamError(A) < 24, True);
    vgSkyGenerateDay(W, B);
    Check('day: the same picture every time',
          (A.Size = B.Size) and CompareMem(A.Memory, B.Memory, A.Size), True);
    if aFolder <> '' then
      A.SaveToFile(IncludeTrailingPathDelimiter(aFolder) + 'SkyDay.bmp');

    A.Clear;
    B.Clear;
    Watch := TStopwatch.StartNew;
    vgSkyGenerateNight(W, A);
    Writeln(Format('       night %d x %d in %d ms', [W, W div 2, Watch.ElapsedMilliseconds]));
    Check('night: a BMP file', (A.Size > 54) and (PWord(A.Memory)^ = $4D42), True);
    Check('night: of the size asked for', A.Size = 54 + Int64(W) * (W div 2) * 3, True);
    vgSkyGenerateNight(W, B);
    Check('night: the same picture every time',
          (A.Size = B.Size) and CompareMem(A.Memory, B.Memory, A.Size), True);
    if aFolder <> '' then
      A.SaveToFile(IncludeTrailingPathDelimiter(aFolder) + 'SkyNight.bmp');

    // A width that is not a power of two is rounded down to one.
    A.Clear;
    vgSkyGenerateDay(700, A);
    Check('width 700 gives 512', PInteger(PByte(A.Memory) + 18)^ = 512, True);
  finally
    A.Free;
    B.Free;
  end;
end;

procedure TestScene;
var
  Scene     : TvgScene;
  Sky       : TvgSkyBox;
  Data      : TvgObjectStore;
  Obj       : TvgObject;
  MinP, MaxP: TpvVector3D;
  First     : TvgSkyStore;
  Cam       : TvgCamera;
  Dist      : Double;
  Height    : Double;
  Axis      : TvgSkyUpAxis;
begin
  Writeln('--- scene ---');
  Scene := TvgScene.Create(nil);
  try
    Check('no sky until asked for', vgSkyBox(Scene, False) = nil, True);
    Sky := vgSkyBox(Scene);
    Check('made on demand', Assigned(Sky), True);
    Check('the same one again', vgSkyBox(Scene) = Sky, True);
    Check('not in the scene until Visible', (Sky.Store = nil) and (Scene.SceneData.Count = 0), True);

    Sky.TextureWidth := 256;        // quick to make
    Sky.Visible := True;
    Check('Visible adds its store', Assigned(Sky.Store) and (Scene.SceneData.IndexOf(Sky.Store) >= 0), True);
    Check('one object, three vertices',
          (Sky.Store.GetObjectCount = 1) and (Sky.Store.GetObjectItem(0).VertexCount = 3), True);
    Check('two textures', Sky.Store.ObjectStoreRes.Descriptors.Count = 2, True);
    Check('not selectable', Sky.Store.GetObjectItem(0).Selectable, False);
    Check('never culled', Sky.Store.GetObjectCullMode(0) = cmNever, True);
    Check('no bounds to zoom to', Scene.GetDataBounds(MinP, MaxP), False);

    // A change is written into the same three vertices.
    Sky.Mode := skmNight;
    Check('night: day factor 0', Sky.DayFactor = 0, True);
    Check('night: still three vertices', Sky.Store.GetObjectItem(0).VertexCount = 3, True);
    Check('night: the moon is up', Sky.MoonElevation >= 10, True);
    Sky.Mode := skmDay;
    Check('day: day factor 1', Sky.DayFactor = 1, True);
    Check('day: the sun is up', Sky.SunElevation >= 8, True);

    // Up by choice, whatever the package's convention is.
    Sky.Mode := skmAuto;
    Sky.SetSunPosition(0, 90);                       // overhead
    Check('up axis: the world''s by default', Sky.UpAxis = skuWorld, True);
    Check('up axis: world follows the convention', Sky.IsZUp = (vgAxisConvention = acZUp), True);
    Sky.UpAxis := skuZUp;
    Check('Z up: overhead is +Z', Sky.IsZUp and (Abs(Sky.SunDirection.z - 1) < 1e-9), True);
    Sky.SetSunPosition(0, 0);                        // on the northern horizon
    Check('Z up: north is +Y', Abs(Sky.SunDirection.y - 1) < 1e-9, True);
    Sky.SetSunPosition(90, 0);
    Check('Z up: east is +X', Abs(Sky.SunDirection.x - 1) < 1e-9, True);
    Sky.UpAxis := skuYUp;
    Check('Y up: east is +X', Abs(Sky.SunDirection.x - 1) < 1e-9, True);
    Sky.SetSunPosition(0, 0);
    Check('Y up: north is -Z', (not Sky.IsZUp) and (Abs(Sky.SunDirection.z + 1) < 1e-9), True);
    Sky.SetSunPosition(0, 90);
    Check('Y up: overhead is +Y', Abs(Sky.SunDirection.y - 1) < 1e-9, True);
    Check('up axis: still three vertices', Sky.Store.GetObjectItem(0).VertexCount = 3, True);
    // A camera turned to the sky's up: level again, as far and as high.
    Cam := TvgCamera.Create;
    Scene.Cameras.AddCamera('Main', Cam);
    Cam.Target   := TpvVector3D.Create(10, 20, 30);
    Cam.UpVector := vgWorldUp;
    Cam.Position := TpvVector3D.Create(10 + 3, 20 - 4, 30 + 2);
    Dist   := (Cam.Position - Cam.Target).Length;
    Height := (Cam.Position - Cam.Target).Dot(Cam.UpVector);
    Sky.UpAxis := skuWorld;
    Check('align: nothing to do for the world''s up', Sky.AlignCamera, False);
    for Axis in [skuYUp, skuZUp, skuYUp] do
    begin
      Sky.UpAxis := Axis;
      Sky.AlignCamera;                                   // the scene's active camera
      Check('align: camera up is the sky''s', (Cam.UpVector - Sky.UpVector).Length < 1e-9, True);
      CheckNum('align: as far from the target', (Cam.Position - Cam.Target).Length, Dist, 1e-9);
      CheckNum('align: as high above it', (Cam.Position - Cam.Target).Dot(Sky.UpVector), Height, 1e-9);
      Check('align: again changes nothing', Sky.AlignCamera(Cam), False);
    end;
    // Upside down is half a turn.
    Cam.UpVector := TpvVector3D.Create(-Sky.UpVector.x, -Sky.UpVector.y, -Sky.UpVector.z);
    Check('align: from upside down', Sky.AlignCamera(Cam) and ((Cam.UpVector - Sky.UpVector).Length < 1e-9), True);
    CheckNum('align: upside down keeps the distance', (Cam.Position - Cam.Target).Length, Dist, 1e-9);

    Sky.UpAxis := skuWorld;
    Sky.SunTracksTime := True;

    // By hand.
    Sky.Mode := skmAuto;
    Sky.SetSunPosition(270, 30);
    CheckNum('sun by hand: azimuth', Sky.SunAzimuth, 270, 1e-6);
    CheckNum('sun by hand: elevation', Sky.SunElevation, 30, 1e-6);
    Check('sun by hand: day', Sky.DayFactor = 1, True);
    Sky.SetSunPosition(270, -30);
    Check('sun by hand, below: night', Sky.DayFactor = 0, True);
    Sky.SetSunPosition(270, 0);
    // Night turns to day between 9 degrees below the horizon and 2 above.
    CheckNum('sun by hand, on the horizon: nearly day', Sky.DayFactor, 0.91, 0.02);
    Sky.SetSunPosition(270, -5);
    CheckNum('sun by hand, 5 below: dusk', Sky.DayFactor, 0.31, 0.03);
    Sky.SetSunPosition(270, -9.5);
    Check('sun by hand, 9.5 below: night', Sky.DayFactor = 0, True);

    // By a clock of our own: Greenwich at the solstice.
    Sky.SunTracksTime := True;
    Sky.UseSystemTime := False;
    Sky.Latitude  := 51.4779;
    Sky.Longitude := 0;
    Sky.UTCOffset := 1;                                     // summer time
    Sky.DateTime  := EncodeDateTime(2024, 6, 21, 13, 2, 0, 0);
    CheckNum('own clock: noon elevation', Sky.SunElevation, 61.96, 0.15);
    Sky.DateTime  := EncodeDateTime(2024, 6, 21, 1, 2, 0, 0);
    Check('own clock: midnight is night', Sky.DayFactor = 0, True);

    // A load frees every store; the sky comes back when it ends.
    First := Sky.Store;
    Check('Load_Begin', Scene.Load_Begin, True);
    Check('gone while loading', (Sky.Store = nil) and (Scene.SceneData.Count = 0), True);
    Data := TvgObjectStore.Create(nil);
    Data.SetupVertexAttributes([vdtPosition]);
    Data.Topology := TRIANGLE_LIST;
    Check('data added', Scene.AddDataStore(Data), True);
    Obj := Data.AddObject(False);
    Obj.AddVertex;  Obj.SetVertexPosition(-5, 0, 0);
    Obj.AddVertex;  Obj.SetVertexPosition( 5, 0, 0);
    Obj.AddVertex;  Obj.SetVertexPosition( 0, 8, 0);
    Scene.Load_End;
    Check('back after Load_End', Assigned(Sky.Store) and (Scene.SceneData.IndexOf(Sky.Store) >= 0), True);
    Check('two stores', Scene.SceneData.Count = 2, True);
    Check('bounds are the data alone',
          Scene.GetDataBounds(MinP, MaxP) and (Abs(MinP.x + 5) < 1e-6) and (Abs(MaxP.y - 8) < 1e-6), True);
    if First = nil then ;   // the old pointer is dead: only that it was replaced matters

    // Cleared on its own, with no load to follow: back straight away.
    Scene.ClearScene;
    Check('back after ClearScene', Assigned(Sky.Store) and (Scene.SceneData.Count = 1), True);

    // Removed behind its back.
    Scene.RemoveDataStore(Sky.Store);
    Check('removed by the scene: forgotten', Sky.Store = nil, True);
    Sky.Refresh;
    Check('Refresh puts it back', Assigned(Sky.Store), True);

    // Switched off, it stays off through a load.
    Sky.Visible := False;
    Check('Visible off removes it', (Sky.Store = nil) and (Scene.SceneData.Count = 0), True);
    Check('Load_Begin', Scene.Load_Begin, True);
    Scene.Load_End;
    Check('still off after a load', Sky.Store = nil, True);

    Sky.Visible := True;
    Check('on again', Assigned(Sky.Store), True);
  finally
    Scene.Free;      // with the sky in it
  end;
  Check('scene freed with the sky in it', True, True);
end;

var
  Folder : String;
begin
  try
    Folder := '';
    if ParamCount >= 1 then
      Folder := ParamStr(1);

    TestSun;
    TestMoon;
    TestDirections;
    TestPanoramas(Folder);
    TestScene;
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION ', E.ClassName, ': ', E.Message);
      Inc(Failures);
    end;
  end;

  Writeln;
  if Failures = 0 then
    Writeln('SkyBoxTest: all checks passed')
  else
    Writeln(Format('SkyBoxTest: %d check(s) FAILED', [Failures]));
  ExitCode := Ord(Failures <> 0);
end.
