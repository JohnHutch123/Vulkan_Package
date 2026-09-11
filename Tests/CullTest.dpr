program CullTest;

{$APPTYPE CONSOLE}

{ Covers the two halves of CPU frustum culling that can run without a Vulkan
  device:

    - publishing a cull volume onto a renderer for the frame about to be
      recorded (TvgScene.PrepareFrameGlobalData -> IvgGlobalDataTarget), and
    - the per-object decision the draw loop makes
      (TvgVulkanDataStore.ShouldCullObject, which VulkanDraw calls).

  VulkanDraw's actual command recording needs a device and is not covered
  here; what IS covered is every branch that decides whether an object gets
  recorded at all. }

uses
  System.SysUtils,
  System.Math,
  PasVulkan.Math,
  Vulkan_Components_Camera,
  Vulkan_Components,
  Vulkan_Components_DataStore,
  Vulkan_Components_Scene_Renderer;

var
  Failures : Integer = 0;

procedure Check(const Name: string; Got, Expect: Boolean);
begin
  if Got = Expect then
    Writeln(Format('  ok   %-44s %s', [Name, BoolToStr(Got, True)]))
  else
  begin
    Writeln(Format('  FAIL %-44s got %s expected %s',
      [Name, BoolToStr(Got, True), BoolToStr(Expect, True)]));
    Inc(Failures);
  end;
end;

function V(X, Y, Z: Single): TpvVector3;
begin
  Result := TpvVector3.Create(X, Y, Z);
end;

function PlanesEqual(const A, B: TvgFrustrumPlanes): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 0 to 5 do
    if (Abs(A.Planes[I].x - B.Planes[I].x) > 1e-6) or
       (Abs(A.Planes[I].y - B.Planes[I].y) > 1e-6) or
       (Abs(A.Planes[I].z - B.Planes[I].z) > 1e-6) or
       (Abs(A.Planes[I].w - B.Planes[I].w) > 1e-6) then
      Exit(False);
end;

{ A camera 5 units back on +Z looking at the origin. }
function MakeCamera: TvgCamera;
begin
  Result := TvgCamera.Create;
  Result.InitializeFromParameters(V(0, 0, 5), V(0, 0, 0), V(0, 1, 0),
                                  45.0, 0.1, 100.0, 1.0);
end;

// ---------------------------------------------------------------------------
procedure TestRendererPublish;
var
  Eng : TvgRenderEngine;
  Tgt : IvgGlobalDataTarget;
  Cam : TvgCamera;
  Src : TvgFrustrumPlanes;
  Got : TvgFrustrumPlanes;
begin
  Writeln('--- publishing a cull volume onto a renderer ---');

  Eng := TvgRenderEngine.Create(nil);
  Tgt := Eng as IvgGlobalDataTarget;
  Cam := MakeCamera;
  try
    // Culling is on by default but inert until a volume is published, so a
    // renderer that never gets one draws everything rather than nothing.
    Check('culling on by default', Eng.FrustumCulling, True);
    Check('no volume before anything publishes', Eng.GetFrustumPlanes(Got), False);

    Src := Cam.GetFrustumPlanesForAspect(1.0);
    Tgt.SetFrustumPlanes(Src);

    Check('volume available after publish', Eng.GetFrustumPlanes(Got), True);
    Check('volume survives the round trip', PlanesEqual(Src, Got), True);

    // The master switch has to win even with a perfectly good volume loaded,
    // or there is no way to rule the culler out when geometry goes missing.
    Eng.FrustumCulling := False;
    Check('master switch suppresses a valid volume', Eng.GetFrustumPlanes(Got), False);
    Eng.FrustumCulling := True;
    Check('master switch restores it', Eng.GetFrustumPlanes(Got), True);

    // Invalidating must actually take effect, otherwise a frame with no
    // camera would keep culling against the previous frame's camera.
    Tgt.ClearFrustumPlanes;
    Check('cleared volume is gone', Eng.GetFrustumPlanes(Got), False);
  finally
    Cam.Free;
    Eng.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestScenePublish;
var
  Eng   : TvgRenderEngine;
  Tgt   : IvgGlobalDataTarget;
  Scene : TvgScene;
  Cam   : TvgCamera;
  Got   : TvgFrustrumPlanes;
  Want  : TvgFrustrumPlanes;
begin
  Writeln('--- scene publishes the volume it renders with ---');

  Eng   := TvgRenderEngine.Create(nil);
  Tgt   := Eng as IvgGlobalDataTarget;
  Scene := TvgScene.Create(nil);
  try
    // No camera yet.  This is the sequence PrepareGlobalAndSceneDescriptors
    // runs: drop the old volume, then ask the scene for a new one.  A scene
    // that cannot supply one must leave it invalid, so everything is drawn
    // rather than culled against a camera that no longer applies.
    Tgt.SetFrustumPlanes(MakeCamera.GetFrustumPlanesForAspect(1.0));
    Check('stale volume present before the frame', Eng.GetFrustumPlanes(Got), True);

    Tgt.ClearFrustumPlanes;
    Scene.PrepareFrameGlobalData(Tgt, 0);
    Check('no camera leaves the volume invalid', Eng.GetFrustumPlanes(Got), False);

    // With a camera the scene must publish one.
    Cam := MakeCamera;
    Scene.Cameras.AddCamera('main', Cam);
    Scene.Cameras.SetActiveCamera('main');

    Tgt.ClearFrustumPlanes;
    Scene.PrepareFrameGlobalData(Tgt, 0);
    Check('camera produces a volume', Eng.GetFrustumPlanes(Got), True);

    // And it must be the volume for the aspect the renderer draws with -
    // culling against any other aspect discards geometry that is on screen.
    Want := Cam.GetFrustumPlanesForAspect(Tgt.GetViewportAspect);
    Check('volume matches the renderer aspect', PlanesEqual(Want, Got), True);
  finally
    Scene.Free;     // owns the camera through its manager
    Eng.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestCullDecision;
var
  DS    : TvgVulkanDataStore;
  Cam   : TvgCamera;
  F     : TvgFrustrumPlanes;
  InView, OffSide, NoBounds : Integer;
begin
  Writeln('--- the per-object decision VulkanDraw makes ---');

  DS  := TvgVulkanDataStore.Create(nil);
  Cam := MakeCamera;
  try
    DS.SetupVertexAttributes([vdtPosition]);
    F := Cam.GetFrustumPlanesForAspect(1.0);

    InView := DS.AddDataObject(False);
    DS.AllocateVertices(InView, 2);
    DS.SetObjectVertexPosition(InView, 0, -0.5, -0.5, -0.5);
    DS.SetObjectVertexPosition(InView, 1,  0.5,  0.5,  0.5);

    OffSide := DS.AddDataObject(False);
    DS.AllocateVertices(OffSide, 2);
    DS.SetObjectVertexPosition(OffSide, 0, 500, -0.5, -0.5);
    DS.SetObjectVertexPosition(OffSide, 1, 501,  0.5,  0.5);

    // Allocated but never written, so it has no bounds at all.
    NoBounds := DS.AddDataObject(False);
    DS.AllocateVertices(NoBounds, 2);

    Check('object in view is drawn',       DS.ShouldCullObject(InView,   F), False);
    Check('object off to the side is cut', DS.ShouldCullObject(OffSide,  F), True);
    Check('object with no bounds is drawn',DS.ShouldCullObject(NoBounds, F), False);

    // cmNever must beat the bounds.  This is what particles rely on: their
    // positions are written by compute, so the CPU box is stale and would
    // cull the simulation the moment it moved away from its seed positions.
    DS.SetObjectCullMode(OffSide, cmNever);
    Check('cmNever overrides an off-screen box',
      DS.ShouldCullObject(OffSide, F), False);

    // Back to cmAuto and it is culled again.
    DS.SetObjectCullMode(OffSide, cmAuto);
    Check('cmAuto culls it once more', DS.ShouldCullObject(OffSide, F), True);

    // cmManual bounds are what gets tested - the point being that geometry
    // the CPU does not author can still be culled if the app knows its extent.
    DS.SetObjectBounds(OffSide, V(-1, -1, -1), V(1, 1, 1));
    Check('manual bounds in view are drawn',
      DS.ShouldCullObject(OffSide, F), False);

    DS.SetObjectBounds(OffSide, V(900, -1, -1), V(901, 1, 1));
    Check('manual bounds off screen are cut',
      DS.ShouldCullObject(OffSide, F), True);

    // Moving the camera must change the answer, not a cached verdict.
    Cam.LookAt(V(0, 0, 5), V(0, 0, 50), V(0, 1, 0));
    F := Cam.GetFrustumPlanesForAspect(1.0);
    Check('in-view object is cut once we look away',
      DS.ShouldCullObject(InView, F), True);

    Cam.LookAt(V(0, 0, 5), V(0, 0, 0), V(0, 1, 0));
    F := Cam.GetFrustumPlanesForAspect(1.0);
    Check('and drawn again once we look back',
      DS.ShouldCullObject(InView, F), False);

    // Moving a mesh in place.  The incrementally accumulated bounds only ever
    // GROW, so after this the box spans both where the object was and where
    // it now is - and it is still (correctly, if wastefully) drawn.  That is
    // the safe direction: the culler over-draws rather than dropping
    // geometry.  Asserted so the behaviour is pinned rather than surprising.
    DS.SetObjectVertexPosition(InView, 0, 800, -0.5, -0.5);
    DS.SetObjectVertexPosition(InView, 1, 801,  0.5,  0.5);
    Check('moved object still drawn (bounds only grow)',
      DS.ShouldCullObject(InView, F), False);

    // RebuildObjectBounds is the remedy: rescan the vertices and the stale
    // half of the box goes away, so the object culls properly again.
    DS.RebuildObjectBounds(InView);
    Check('rebuilt bounds cull the moved object',
      DS.ShouldCullObject(InView, F), True);
  finally
    Cam.Free;
    DS.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestTwoRenderers;
var
  WideEng, TallEng : TvgRenderEngine;
  WideTgt, TallTgt : IvgGlobalDataTarget;
  Cam   : TvgCamera;
  DS    : TvgVulkanDataStore;
  Obj   : Integer;
  Wide, Tall : TvgFrustrumPlanes;
  X     : Single;
begin
  Writeln('--- one scene, two viewport shapes ---');

  WideEng := TvgRenderEngine.Create(nil);
  TallEng := TvgRenderEngine.Create(nil);
  WideTgt := WideEng as IvgGlobalDataTarget;
  TallTgt := TallEng as IvgGlobalDataTarget;
  Cam     := MakeCamera;
  DS      := TvgVulkanDataStore.Create(nil);
  try
    DS.SetupVertexAttributes([vdtPosition]);

    // Just outside a square viewport's right edge at the origin plane, but
    // inside a 3:1 one.  A single shared cull volume would get one of the two
    // renderers wrong - which is why the volume lives on the renderer.
    X   := 5.0 * Tan(DegToRad(45.0) / 2) * 1.5;

    Obj := DS.AddDataObject(False);
    DS.AllocateVertices(Obj, 2);
    DS.SetObjectVertexPosition(Obj, 0, X - 0.1, -0.1, -0.1);
    DS.SetObjectVertexPosition(Obj, 1, X + 0.1,  0.1,  0.1);

    WideTgt.SetFrustumPlanes(Cam.GetFrustumPlanesForAspect(3.0));
    TallTgt.SetFrustumPlanes(Cam.GetFrustumPlanesForAspect(1.0));

    Check('wide renderer has its own volume', WideEng.GetFrustumPlanes(Wide), True);
    Check('tall renderer has its own volume', TallEng.GetFrustumPlanes(Tall), True);

    Check('drawn on the wide viewport', DS.ShouldCullObject(Obj, Wide), False);
    Check('cut on the square viewport', DS.ShouldCullObject(Obj, Tall), True);
  finally
    DS.Free;
    Cam.Free;
    TallEng.Free;
    WideEng.Free;
  end;
  Writeln;
end;

begin
  try
    TestRendererPublish;
    TestScenePublish;
    TestCullDecision;
    TestTwoRenderers;

    if Failures = 0 then
      Writeln('ALL CHECKS PASSED')
    else
    begin
      Writeln(Format('%d CHECK(S) FAILED', [Failures]));
      ExitCode := 1;
    end;
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION: ', E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
