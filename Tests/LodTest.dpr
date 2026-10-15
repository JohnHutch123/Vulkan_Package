program LodTest;

{$APPTYPE CONSOLE}

{ Level of detail without a device:

    - TvgLodBand, the per-object test the draw loop makes (distance, screen
      size, orthographic, LodBias);
    - the scene publishing a level-of-detail view onto a renderer with its
      cull volume, and the renderer's per-frame step keeping it;
    - TvgLodGroup writing bands for whole levels, across stores, and the
      group bookkeeping: objects leaving, anchors, proxies, ClearScene. }

uses
  System.SysUtils,
  System.Math,
  PasVulkan.Math,
  PasVulkan.Math.Double,
  Vulkan_Components_Camera,
  Vulkan_Components,
  Vulkan_Components_DataStore,
  Vulkan_Components_Lookups,
  Vulkan_Components_Scene_Renderer,
  Vulkan_LOD;

type
  TEngineAccess = class(TvgRenderEngine);

var
  Failures : Integer = 0;

procedure Check(const Name: string; Got, Expect: Boolean);
begin
  if Got = Expect then
    Writeln(Format('  ok   %-48s %s', [Name, BoolToStr(Got, True)]))
  else
  begin
    Writeln(Format('  FAIL %-48s got %s expected %s',
      [Name, BoolToStr(Got, True), BoolToStr(Expect, True)]));
    Inc(Failures);
  end;
end;

procedure CheckNum(const Name: string; Got, Expect: Double; Tol: Double = 1e-6);
begin
  if Abs(Got - Expect) <= Tol then
    Writeln(Format('  ok   %-48s %g', [Name, Got]))
  else
  begin
    Writeln(Format('  FAIL %-48s got %g expected %g', [Name, Got, Expect]));
    Inc(Failures);
  end;
end;

function V(X, Y, Z: Single): TpvVector3;
begin
  Result := TpvVector3.Create(X, Y, Z);
end;

function VD(X, Y, Z: Double): TpvVector3D;
begin
  Result := TpvVector3D.Create(X, Y, Z);
end;

function View(X, Y, Z, PixelScale, Bias: Double; Ortho: Boolean = False): TvgLodView;
begin
  Result.Eye        := VD(X, Y, Z);
  Result.PixelScale := PixelScale;
  Result.Ortho      := Ortho;
  Result.Bias       := Bias;
end;

// ---------------------------------------------------------------------------
procedure TestBand;
var
  B : TvgLodBand;
begin
  Writeln('--- TvgLodBand ---');

  B := Default(TvgLodBand);
  Check('no band: always drawn', B.Accepts(View(1e6, 0, 0, 1, 1)), True);

  B := TvgLodBand.Make(lmDistance, V(0, 0, 0), 0, 10, 50);
  Check('distance 5: below the band',  B.Accepts(View(5, 0, 0, 1, 1)), False);
  Check('distance 10: Min is inside',  B.Accepts(View(10, 0, 0, 1, 1)), True);
  Check('distance 30: inside',         B.Accepts(View(0, 30, 0, 1, 1)), True);
  Check('distance 50: Max is outside', B.Accepts(View(0, 0, 50, 1, 1)), False);
  Check('distance 30, bias 2: 60, out', B.Accepts(View(30, 0, 0, 1, 2)), False);
  Check('distance 30, bias 0.5: 15, in', B.Accepts(View(30, 0, 0, 1, 0.5)), True);

  // Radius 1 at distance 10, 500 px per unit at distance 1: 2*1*500/10 = 100 px.
  B := TvgLodBand.Make(lmScreenSize, V(0, 0, 0), 1, 50, 200);
  CheckNum('screen size at 10', B.Measure(View(10, 0, 0, 500, 1)), 100);
  Check('100 px is inside 50..200',  B.Accepts(View(10, 0, 0, 500, 1)), True);
  Check('at 40: 25 px, too small',   B.Accepts(View(40, 0, 0, 500, 1)), False);
  Check('at 4: 250 px, too large',   B.Accepts(View(4, 0, 0, 500, 1)), False);

  // Orthographic: distance plays no part.
  CheckNum('ortho size', B.Measure(View(1000, 0, 0, 50, 1, True)), 100);
  CheckNum('ortho size, bias 2', B.Measure(View(1000, 0, 0, 50, 2, True)), 50);

  // Bias 0: always the finest level - distance 0, screen size infinite.
  B := TvgLodBand.Make(lmDistance, V(0, 0, 0), 0, 0, 10);
  Check('bias 0: finest distance level', B.Accepts(View(1e5, 0, 0, 1, 0)), True);
  B := TvgLodBand.Make(lmScreenSize, V(0, 0, 0), 1, 100, Infinity);
  Check('bias 0: finest screen level',   B.Accepts(View(1e5, 0, 0, 1, 0)), True);
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestStoreApi;
var
  DS   : TvgVulkanDataStore;
  I    : Integer;
  Band : TvgLodBand;
begin
  Writeln('--- the store keeps an object''s band ---');
  DS := TvgVulkanDataStore.Create(nil);
  try
    DS.SetupVertexAttributes([vdtPosition]);
    I := DS.AddDataObject(False);
    DS.AllocateVertices(I, 1);
    Check('new object: no band', DS.GetObjectLod(I).Metric = lmNone, True);
    Check('new object: never skipped', DS.ShouldLodSkipObject(I, View(1e6, 0, 0, 1, 1)), False);

    DS.SetObjectLod(I, TvgLodBand.Make(lmDistance, V(0, 0, 0), 0, 0, 100));
    Band := DS.GetObjectLod(I);
    Check('band kept', (Band.Metric = lmDistance) and (Band.Max = 100), True);
    Check('near: drawn',  DS.ShouldLodSkipObject(I, View(50, 0, 0, 1, 1)), False);
    Check('far: skipped', DS.ShouldLodSkipObject(I, View(150, 0, 0, 1, 1)), True);

    // The band survives the object's data being replaced.
    DS.SetObjectVertexPosition(I, 0, 1, 2, 3);
    Check('band survives a vertex edit', DS.GetObjectLod(I).Metric = lmDistance, True);
    DS.SetObjectHidden(I, True);
    DS.SetObjectHidden(I, False);
    Check('band survives hide/show', DS.GetObjectLod(I).Metric = lmDistance, True);

    DS.ClearObjectLod(I);
    Check('cleared: drawn far away', DS.ShouldLodSkipObject(I, View(150, 0, 0, 1, 1)), False);
  finally
    DS.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestPublish;
var
  Eng   : TvgRenderEngine;
  Scene : TvgScene;
  Cam   : TvgCamera;
  Got   : TvgLodView;
begin
  Writeln('--- the scene publishes a view; the renderer keeps it ---');
  Eng   := TvgRenderEngine.Create(nil);
  Scene := TvgScene.Create(nil);
  try
    Eng.Scene := Scene;
    CheckNum('LodBias defaults to 1', Eng.LodBias, 1);

    TEngineAccess(Eng).PrepareGlobalAndSceneDescriptors(0);
    Check('no camera: no view', Eng.GetLodView(Got), False);

    Scene.WorldOrigin := VD(1000, 2000, 0);
    Cam := TvgCamera.Create;
    Cam.InitializeFromParameters(V(1000, 2000, 50), V(1000, 2000, 0), V(0, 1, 0),
                                 90.0, 0.1, 1000.0, 1.0);
    Scene.Cameras.AddCamera('main', Cam);
    Scene.Cameras.SetActiveCamera('main');

    TEngineAccess(Eng).PrepareGlobalAndSceneDescriptors(0);
    Check('camera: a view', Eng.GetLodView(Got), True);
    // Local to the origin, like the vertices.
    CheckNum('eye x is local', Got.Eye.x, 0, 1e-3);
    CheckNum('eye y is local', Got.Eye.y, 0, 1e-3);
    CheckNum('eye z', Got.Eye.z, 50, 1e-3);
    Check('perspective', Got.Ortho, False);
    // 90 degrees: tan 45 = 1, so one unit per half height; no swapchain: 1080 high.
    CheckNum('pixel scale = half height / tan(fov/2)', Got.PixelScale, 540, 1e-3);
    CheckNum('bias from the renderer', Got.Bias, 1);

    Eng.LodBias := 3;
    Eng.GetLodView(Got);
    CheckNum('LodBias reaches the view', Got.Bias, 3);
    Eng.LodBias := -1;
    CheckNum('negative LodBias is 0', Eng.LodBias, 0);

    Scene.Cameras.RemoveCamera('main');
    TEngineAccess(Eng).PrepareGlobalAndSceneDescriptors(0);
    Check('camera removed: view dropped', Eng.GetLodView(Got), False);
  finally
    Scene.Free;
    Eng.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
function NewStore: TvgObjectStore;
begin
  Result := TvgObjectStore.Create(nil);
  Result.SetupVertexAttributes([vdtPosition]);
  Result.Topology := POINT_LIST;
end;

function AddPoint(aStore: TvgObjectStore; X: Single): TvgObject;
begin
  Result := aStore.AddObject(False);
  Result.AddVertex;
  Result.SetVertexPosition(X, 0, 0);
end;

procedure TestGroup;
var
  Scene    : TvgScene;
  S1, S2   : TvgObjectStore;
  Fine1, Fine2, Mid, Coarse, Other : TvgObject;
  Groups   : TvgLodGroups;
  G        : TvgLodGroup;
  Band     : TvgLodBand;
  Anchor   : TpvMatrix4x4D;
  Staging  : TvgScene;
  Moved    : TvgObjectStore;
  MovedObj : TvgObject;
begin
  Writeln('--- TvgLodGroup ---');
  Scene := TvgScene.Create(nil);
  try
    Scene.WorldOrigin := VD(100, 0, 0);
    if not Scene.Load_Begin then raise Exception.Create('Load_Begin refused');
    S1 := NewStore; Scene.AddDataStore(S1);
    S2 := NewStore; Scene.AddDataStore(S2);
    Fine1  := AddPoint(S1, 0);
    Fine2  := AddPoint(S2, 0);     // level 0 spans two stores
    Mid    := AddPoint(S1, 0);
    Coarse := AddPoint(S2, 0);
    Other  := AddPoint(S1, 5);
    Scene.Load_End;

    Check('no groups until asked', vgLodGroups(Scene, False) = nil, True);
    Groups := vgLodGroups(Scene);
    Check('made on first use', Assigned(Groups) and (vgLodGroups(Scene, False) = Groups), True);

    G := Groups.Add(lmDistance, 'tree');
    G.AddLevel; G.AddLevel; G.AddLevel; G.AddLevel;
    G.AddObject(0, Fine1); G.AddObject(0, Fine2);
    G.AddObject(1, Mid);
    G.AddObject(2, Coarse);
    // level 3 empty: nothing beyond 300
    G.SetThresholds([50, 100, 300]);
    G.SetCentre(VD(110, 0, 0));
    G.Apply;

    Band := Fine2.GetLod;
    Check('level 0 band', (Band.Metric = lmDistance) and (Band.Min = 0) and (Band.Max = 50), True);
    CheckNum('centre is local to the origin', Band.Centre.x, 10);
    Band := Coarse.GetLod;
    Check('level 2 band', (Band.Min = 100) and (Band.Max = 300), True);
    Check('other objects untouched', Other.GetLod.Metric = lmNone, True);

    // Eye at local (10, 0, d): distance d from the centre.
    Check('at 20: level 0',  G.LevelFor(View(10, 0, 20, 1, 1)) = 0, True);
    Check('at 70: level 1',  G.LevelFor(View(10, 0, 70, 1, 1)) = 1, True);
    Check('at 200: level 2', G.LevelFor(View(10, 0, 200, 1, 1)) = 2, True);
    Check('at 500: nothing', G.LevelFor(View(10, 0, 500, 1, 1)) = -1, True);
    Check('both level-0 parts drawn at 20',
      (not S1.ShouldLodSkipObject(Fine1.ObjIndex, View(10, 0, 20, 1, 1))) and
      (not S2.ShouldLodSkipObject(Fine2.ObjIndex, View(10, 0, 20, 1, 1))), True);
    Check('both left out at 70',
      S1.ShouldLodSkipObject(Fine1.ObjIndex, View(10, 0, 70, 1, 1)) and
      S2.ShouldLodSkipObject(Fine2.ObjIndex, View(10, 0, 70, 1, 1)), True);

    Check('level 0 is not a proxy', vgIsLodProxy(Fine1), False);
    Check('level 1 is a proxy', vgIsLodProxy(Mid), True);
    Check('outside any group: not a proxy', vgIsLodProxy(Other), False);
    Check('GroupOf', Groups.GroupOf(Coarse) = G, True);

    try
      G.SetThresholds([100, 50]);
      Check('descending distance thresholds refused', False, True);
    except
      on EvgLodError do Check('descending distance thresholds refused', True, True);
    end;

    // An anchor: centre in its frame, thresholds scaled with it.
    // Scale 2, then move 100 along x.
    Anchor := TpvMatrix4x4D.Create(2, 0, 0, 0,  0, 2, 0, 0,  0, 0, 2, 0,  100, 0, 0, 1);
    G.SetCentre(VD(5, 0, 0));
    G.SetAnchor(Fine1, Anchor);
    G.Apply;
    CheckNum('anchored centre: (5*2)+100, local 10', Fine1.GetLod.Centre.x, 10, 1e-4);
    CheckNum('anchored threshold scaled by 2', Fine1.GetLod.Max, 100, 1e-3);
    vgLodAnchorMoved(Fine1, TpvMatrix4x4D.CreateTranslation(VD(200, 0, 0)));
    CheckNum('anchor moved: centre follows', Fine1.GetLod.Centre.x, 105, 1e-4);
    CheckNum('anchor moved: scale back to 1', Fine1.GetLod.Max, 50, 1e-3);

    // An object leaving the scene leaves its group.
    S2.RemoveObject(Coarse);
    Check('removed object left its level', Length(G.Levels[2]) = 0, True);
    G.RemoveObject(Mid);
    Check('RemoveObject clears the band', Mid.GetLod.Metric = lmNone, True);
    Check('and it is no proxy now', vgIsLodProxy(Mid), False);

    // Appending another scene's stores brings its groups.
    Staging := TvgScene.Create(nil);
    try
      Staging.WorldOrigin := Scene.WorldOrigin;
      if not Staging.Load_Begin then raise Exception.Create('Load_Begin refused');
      Moved := NewStore; Staging.AddDataStore(Moved);
      MovedObj := AddPoint(Moved, 0);
      Staging.Load_End;
      with vgLodGroups(Staging).Add do
      begin
        AddLevel; AddLevel;
        AddObject(1, MovedObj);
        SetThresholds([10]);
        Apply;
      end;
      Staging.MoveExtensionsTo(Scene);
      Staging.ExtractDataStore(Moved);
      Scene.AddDataStoreLive(Moved);
      Check('group moved with the stores', Groups.Count = 2, True);
      Check('its object kept its group', Groups.GroupOf(MovedObj) <> nil, True);
      Check('and is a proxy here', vgIsLodProxy(MovedObj), True);
    finally
      Staging.Free;
    end;

    // ClearScene (Load_Begin) takes the groups with the stores.
    if not Scene.Load_Begin then raise Exception.Create('Load_Begin refused');
    Check('cleared with the scene', Groups.Count = 0, True);
    Scene.Load_End;
  finally
    Scene.Free;
  end;
  Writeln;
end;

begin
  try
    TestBand;
    TestStoreApi;
    TestPublish;
    TestGroup;
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION ', E.ClassName, ': ', E.Message);
      Inc(Failures);
    end;
  end;
  if Failures = 0 then
    Writeln('ALL PASSED')
  else
    Writeln(Failures, ' FAILED');
  ExitCode := Ord(Failures > 0);
end.
