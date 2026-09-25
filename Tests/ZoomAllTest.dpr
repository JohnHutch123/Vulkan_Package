program ZoomAllTest;

{$APPTYPE CONSOLE}

{ "Zoom to see all data": TvgScene.GetDataBounds gathering the scene's extent,
  and the TvgCamera.ZoomAll family placing a camera that frames it.

  The load-bearing check in this file is the one that pushes all eight corners
  of the data box through the view-projection the RENDERER actually draws with
  (GetViewProjectionMatrixForAspect, at the viewport's aspect and the scene's
  WorldOrigin) and asserts every one lands inside NDC.  Everything else here
  either narrows that down to a specific failure or pins a rule the fit
  depends on.

  Run once under each world axis convention, since "look down" is defined in
  terms of vgWorldUp / vgWorldForward.

  No Vulkan device is used anywhere.  Bounds live in the data store's CPU
  arrays and the camera is pure math. }

uses
  System.SysUtils,
  System.Math,
  PasVulkan.Math,
  PasVulkan.Math.Double,
  Vulkan_WorldAxes,
  Vulkan_Components_Camera,
  Vulkan_Components,
  Vulkan_Components_DataStore,
  Vulkan_Components_Scene_Renderer;

const
  ASPECT_WIDE   = 16.0 / 9.0;
  ASPECT_SQUARE = 1.0;
  ASPECT_TALL   =  9.0 / 16.0;

  MARGIN        = CAMERA_DEFAULT_ZOOM_MARGIN;   // 1.05

var
  Failures : Integer = 0;

procedure Check(const Name: string; Got, Expect: Boolean);
begin
  if Got = Expect then
    Writeln(Format('  ok   %-56s %s', [Name, BoolToStr(Got, True)]))
  else
  begin
    Writeln(Format('  FAIL %-56s got %s expected %s',
      [Name, BoolToStr(Got, True), BoolToStr(Expect, True)]));
    Inc(Failures);
  end;
end;

procedure CheckNum(const Name: string; Got, Expect, Tol: Double);
begin
  if Abs(Got - Expect) <= Tol then
    Writeln(Format('  ok   %-56s %.6f', [Name, Got]))
  else
  begin
    Writeln(Format('  FAIL %-56s got %.9f expected %.9f', [Name, Got, Expect]));
    Inc(Failures);
  end;
end;

procedure CheckInt(const Name: string; Got, Expect: Integer);
begin
  if Got = Expect then
    Writeln(Format('  ok   %-56s %d', [Name, Got]))
  else
  begin
    Writeln(Format('  FAIL %-56s got %d expected %d', [Name, Got, Expect]));
    Inc(Failures);
  end;
end;

// Value must be at most aMax.
procedure CheckAtMost(const Name: string; Got, Limit: Double);
begin
  if Got <= Limit then
    Writeln(Format('  ok   %-56s %.6f <= %.6f', [Name, Got, Limit]))
  else
  begin
    Writeln(Format('  FAIL %-56s got %.9f, limit %.9f', [Name, Got, Limit]));
    Inc(Failures);
  end;
end;

procedure CheckAtLeast(const Name: string; Got, Limit: Double);
begin
  if Got >= Limit then
    Writeln(Format('  ok   %-56s %.6f >= %.6f', [Name, Got, Limit]))
  else
  begin
    Writeln(Format('  FAIL %-56s got %.9f, limit %.9f', [Name, Got, Limit]));
    Inc(Failures);
  end;
end;

function V(X, Y, Z: Double): TpvVector3D;
begin
  Result := TpvVector3D.Create(X, Y, Z);
end;

function VS(X, Y, Z: Single): TpvVector3;
begin
  Result := TpvVector3.Create(X, Y, Z);
end;

function Corner(const aMin, aMax: TpvVector3D; I: Integer): TpvVector3D;
begin
  if (I and 1) = 0 then Result.x := aMin.x else Result.x := aMax.x;
  if (I and 2) = 0 then Result.y := aMin.y else Result.y := aMax.y;
  if (I and 4) = 0 then Result.z := aMin.z else Result.z := aMax.z;
end;

// Where aVP puts aP, in NDC.
function ToNDC(const aVP: TpvMatrix4x4D; const aP: TpvVector3D): TpvVector3D;
var
  C : TpvVector4D;
begin
  C      := aVP * TpvVector4D.Create(aP.x, aP.y, aP.z, 1.0);
  Result := V(C.x / C.w, C.y / C.w, C.z / C.w);
end;

// ---------------------------------------------------------------------------
//  The screen test every fit has to pass.
//
//  Pushes all eight corners of aMin..aMax through the matrix the renderer
//  draws with and reports how far out the worst one lands:
//    aWorstXY  - max(|ndc.x|, |ndc.y|) over the corners.  <= 1 means on
//                screen; how far BELOW 1 says whether the fit is tight.
//    aWorstZ   - how far outside [0, 1] the worst corner's depth is, 0 when
//                every corner is between the near and far planes.
// ---------------------------------------------------------------------------
procedure MeasureFit(aCam: TvgCamera; const aMin, aMax, aOrigin: TpvVector3D;
                     aAspect: Double; out aWorstXY, aWorstZ: Double);
var
  VP : TpvMatrix4x4D;
  C  : TpvVector4D;
  P  : TpvVector3D;
  I  : Integer;
begin
  aWorstXY := 0;
  aWorstZ  := 0;

  // The exact matrix TvgScene.PrepareFrameGlobalData publishes: the viewport's
  // own aspect, and the geometry measured from the scene's WorldOrigin.
  VP := aCam.GetViewProjectionMatrixForAspect(aAspect, aOrigin);

  for I := 0 to 7 do
  begin
    // Corners are world coordinates; the matrix above expects them relative
    // to the origin, which is how the vertex data is stored.
    P := Corner(aMin, aMax, I) - aOrigin;
    C := VP * TpvVector4D.Create(P.x, P.y, P.z, 1.0);

    // Behind the eye: no fit should ever produce this.
    if C.w <= 0 then
    begin
      aWorstXY := 1.0e30;
      aWorstZ  := 1.0e30;
      Exit;
    end;

    aWorstXY := Max(aWorstXY, Max(Abs(C.x / C.w), Abs(C.y / C.w)));
    aWorstZ  := Max(aWorstZ, Max(-(C.z / C.w), (C.z / C.w) - 1.0));
  end;

  aWorstZ := Max(aWorstZ, 0.0);
end;

// One complete fit assertion: everything on screen, and tight enough to have
// actually been fitted rather than merely stood well back.
//
// aTight is only meaningful when the box is seen square on.  Looked at
// obliquely, the corner furthest out perpendicular to the view may sit at the
// BACK of the box, where perspective shrinks it, so the fit is conservative -
// everything visible, with some margin to spare - rather than touching.  See
// TvgCamera.FitToBounds.
procedure CheckFit(const aWhat: string; aCam: TvgCamera;
                   const aMin, aMax, aOrigin: TpvVector3D; aAspect: Double;
                   aTight: Boolean = True);
var
  WorstXY, WorstZ : Double;
begin
  MeasureFit(aCam, aMin, aMax, aOrigin, aAspect, WorstXY, WorstZ);

  // 1e-9 of slack for the arithmetic, nothing more: this is the promise.
  CheckAtMost(aWhat + ': every corner on screen', WorstXY, 1.0 + 1.0e-9);
  CheckNum   (aWhat + ': every corner between near and far', WorstZ, 0.0, 1e-9);

  // And not wastefully far away.  A camera parked a kilometre back passes the
  // check above and fails this one; together they are the fit.  The data
  // touches the margin on the tighter of the two screen axes, so the worst
  // corner must reach 1/MARGIN.
  if aTight then
    CheckAtLeast(aWhat + ': fit is tight, not merely safe', WorstXY, 1.0 / MARGIN - 1e-6);
end;

// ---------------------------------------------------------------------------
//  A camera looking along -Z from +Z, for the convention-independent checks.
// ---------------------------------------------------------------------------
function MakeCamera: TvgCamera;
begin
  Result := TvgCamera.Create;
  Result.InitializeFromParameters(V(0, 0, 5), V(0, 0, 0), V(0, 1, 0),
                                  45.0, 0.1, 1000.0, ASPECT_WIDE);
end;

// ---------------------------------------------------------------------------
//  1-3. The fit itself: three box shapes x three aspects x two projections.
// ---------------------------------------------------------------------------
procedure TestFit;
type
  TBoxCase = record
    Name : string;
    Min  : TpvVector3D;
    Max  : TpvVector3D;
  end;
var
  Boxes   : array[0..3] of TBoxCase;
  Aspects : array[0..2] of Double;
  AspName : array[0..2] of string;
  Cam     : TvgCamera;
  B, A    : Integer;
  Zero    : TpvVector3D;
begin
  Writeln('--- fit: every corner on screen, and tight ---');

  Zero := V(0, 0, 0);

  Boxes[0].Name := 'cube';        Boxes[0].Min := V(-1, -1, -1);    Boxes[0].Max := V(1, 1, 1);
  // Wider than it is tall by more than any of the aspects, so the horizontal
  // constraint is the binding one - the case an ortho fit that stores
  // left/right straight from the data gets wrong at every aspect but one.
  Boxes[1].Name := 'wide flat';   Boxes[1].Min := V(-50, -1, -0.001); Boxes[1].Max := V(50, 1, 0.001);
  Boxes[2].Name := 'tall';        Boxes[2].Min := V(-1, -40, -1);   Boxes[2].Max := V(1, 40, 1);
  // Off-centre, so a fit that assumes the data is around the origin fails.
  Boxes[3].Name := 'off centre';  Boxes[3].Min := V(90, 40, -210);  Boxes[3].Max := V(110, 60, -190);

  Aspects[0] := ASPECT_WIDE;   AspName[0] := '16:9';
  Aspects[1] := ASPECT_SQUARE; AspName[1] := '1:1';
  Aspects[2] := ASPECT_TALL;   AspName[2] := '9:16';

  for B := 0 to High(Boxes) do
    for A := 0 to High(Aspects) do
    begin
      // --- perspective ---
      Cam := MakeCamera;
      try
        Check(Format('%s @ %s persp: fitted', [Boxes[B].Name, AspName[A]]),
          Cam.ZoomAll(Boxes[B].Min, Boxes[B].Max, Aspects[A], MARGIN), True);
        CheckFit(Format('%s @ %s persp', [Boxes[B].Name, AspName[A]]),
          Cam, Boxes[B].Min, Boxes[B].Max, Zero, Aspects[A]);
      finally
        Cam.Free;
      end;

      // --- orthographic ---
      Cam := MakeCamera;
      try
        Cam.ProjectionType := ptOrthographic;
        Check(Format('%s @ %s ortho: fitted', [Boxes[B].Name, AspName[A]]),
          Cam.ZoomAll(Boxes[B].Min, Boxes[B].Max, Aspects[A], MARGIN), True);
        CheckFit(Format('%s @ %s ortho', [Boxes[B].Name, AspName[A]]),
          Cam, Boxes[B].Min, Boxes[B].Max, Zero, Aspects[A]);
      finally
        Cam.Free;
      end;
    end;

  Writeln;
end;

// ---------------------------------------------------------------------------
//  4. Look down - the plan view, in whichever convention is active.
// ---------------------------------------------------------------------------
procedure TestLookDown;
var
  Cam      : TvgCamera;
  BMin,
  BMax,
  Centre   : TpvVector3D;
  Zero     : TpvVector3D;
  M        : TpvMatrix4x4D;
  S        : TpvVector3D;
  Finite   : Boolean;
  R, C     : Integer;
begin
  Writeln('--- look down: a plan view of all the data ---');

  Zero := V(0, 0, 0);

  // A wide, flat sheet lying in the horizontal plane, with a little relief -
  // a height field, which is what a plan view is usually of.  Built in the
  // active convention so "flat" means flat in both.
  vgRangeFromYUp(V(-300, -2, -200), V(300, 2, 200), BMin, BMax);
  Centre := (BMin + BMax) * 0.5;

  Cam := MakeCamera;
  try
    Check('look down: fitted', Cam.ZoomAllLookDown(BMin, BMax, ASPECT_WIDE, MARGIN), True);
    CheckFit('look down persp', Cam, BMin, BMax, Zero, ASPECT_WIDE);

    // The degeneracy this guards: straight down with vgWorldUp as the up
    // vector makes FUpVector.Cross(zaxis) zero and the whole matrix NaN.
    M      := Cam.GetViewMatrix;
    Finite := True;
    for R := 0 to 3 do
      for C := 0 to 3 do
        if IsNan(M.RawComponents[C, R]) or IsInfinite(M.RawComponents[C, R]) then
          Finite := False;
    Check('look down: view matrix is finite', Finite, True);

    // Above the data, looking at the middle of it.
    CheckAtLeast('look down: eye is above the data',
      vgUpComponent(Cam.Position), vgUpComponent(BMax));
    CheckNum('look down: target height is the data centre',
      vgUpComponent(Cam.Target), vgUpComponent(Centre), 1e-6);

    // Orientation: world forward must come out at the TOP of the screen and
    // world right at the RIGHT of it - north up, east right.  A plan view
    // that is mirrored or quarter-turned passes every check above.
    S := Cam.WorldToScreenPoint(Centre + vgWorldForward * 50, 1600, 900);
    CheckAtMost('look down: world forward is in the top half', S.y, 450.0 - 1.0);

    S := Cam.WorldToScreenPoint(Centre + vgWorldRight * 50, 1600, 900);
    CheckAtLeast('look down: world right is in the right half', S.x, 800.0 + 1.0);

    // And the same, orthographic - the projection a map view usually wants.
    Cam.ProjectionType := ptOrthographic;
    Check('look down ortho: fitted', Cam.ZoomAllLookDown(BMin, BMax, ASPECT_WIDE, MARGIN), True);
    CheckFit('look down ortho', Cam, BMin, BMax, Zero, ASPECT_WIDE);

    S := Cam.WorldToScreenPoint(Centre + vgWorldForward * 50, 1600, 900);
    CheckAtMost('look down ortho: world forward is in the top half', S.y, 450.0 - 1.0);
  finally
    Cam.Free;
  end;

  Writeln;
end;

// ---------------------------------------------------------------------------
//  6. The target lands on the data, so a following Orbit pivots on it.
// ---------------------------------------------------------------------------
procedure TestTarget;
var
  Cam    : TvgCamera;
  BMin,
  BMax   : TpvVector3D;
  Centre : TpvVector3D;
  Zero   : TpvVector3D;
  NDC    : TpvVector3D;
begin
  Writeln('--- target lands on the centre of the data ---');

  Zero   := V(0, 0, 0);
  BMin   := V(10, 20, 30);
  BMax   := V(50, 26, 90);
  Centre := (BMin + BMax) * 0.5;

  Cam := MakeCamera;
  try
    Cam.ZoomAll(BMin, BMax, ASPECT_WIDE, MARGIN);
    CheckNum('target x is the data centre', Cam.Target.x, Centre.x, 1e-9);
    CheckNum('target y is the data centre', Cam.Target.y, Centre.y, 1e-9);
    CheckNum('target z is the data centre', Cam.Target.z, Centre.z, 1e-9);

    // Orbit pivots about the target, so after a zoom-extents the data stays
    // centred as the user turns around it.  Not still *framed* - a box is not
    // a sphere, and a long box turned end-on genuinely needs a wider view -
    // but the thing being looked at must not drift off centre.
    Cam.Orbit(37, 21);
    NDC := ToNDC(Cam.GetViewProjectionMatrixForAspect(ASPECT_WIDE, Zero), Centre);
    CheckNum('data centre stays centred after a 37/21 orbit', Hypot(NDC.x, NDC.y), 0, 1e-9);

    Cam.Orbit(180, 0);
    NDC := ToNDC(Cam.GetViewProjectionMatrixForAspect(ASPECT_WIDE, Zero), Centre);
    CheckNum('data centre stays centred after turning right round', Hypot(NDC.x, NDC.y), 0, 1e-9);

    // And a second ZoomAll from the new angle frames it again - the fit is
    // computed from the direction the camera is actually looking, not from
    // wherever it started.  Not asserted tight: seen from a corner, the box's
    // widest point is at the back, where perspective shrinks it.
    Cam.ZoomAll(BMin, BMax, ASPECT_WIDE, MARGIN);
    CheckFit('re-fitted from the new angle', Cam, BMin, BMax, Zero, ASPECT_WIDE, False);
  finally
    Cam.Free;
  end;

  Writeln;
end;

// ---------------------------------------------------------------------------
//  7. Degenerate input.
// ---------------------------------------------------------------------------
procedure TestDegenerate;
var
  Cam    : TvgCamera;
  Pos,
  Tgt    : TpvVector3D;
  Rev    : UInt64;
  Zero   : TpvVector3D;
  BMin,
  BMax   : TpvVector3D;
begin
  Writeln('--- degenerate input ---');

  Zero := V(0, 0, 0);

  Cam := MakeCamera;
  try
    Pos := Cam.Position;
    Tgt := Cam.Target;
    Rev := Cam.Revision;

    // An inverted box is how TvgScene.GetDataBounds' "no data" answer would
    // arrive if a caller ignored its Boolean result.  Refusing it is what
    // stops an empty scene throwing the camera somewhere arbitrary.
    Check('inverted box is refused', Cam.ZoomAll(V(1, 1, 1), V(-1, -1, -1), ASPECT_WIDE), False);
    CheckNum('refused: position unchanged', (Cam.Position - Pos).Length, 0, 0);
    CheckNum('refused: target unchanged',   (Cam.Target - Tgt).Length,   0, 0);
    Check   ('refused: nothing invalidated', Cam.Revision = Rev, True);
  finally
    Cam.Free;
  end;

  // A single point: nothing to frame, but the camera must still come out
  // usable rather than pressed against it or full of NaN.
  Cam := MakeCamera;
  try
    Check('single point is accepted', Cam.ZoomAll(V(7, 8, 9), V(7, 8, 9), ASPECT_WIDE), True);
    CheckNum('single point: target is the point', (Cam.Target - V(7, 8, 9)).Length, 0, 1e-9);
    CheckAtLeast('single point: near plane is positive', Cam.NearPlane, 1e-12);
    CheckAtLeast('single point: far is beyond near', Cam.FarPlane - Cam.NearPlane, 1e-12);
    CheckAtLeast('single point: eye is off the point', Cam.Distance, 1e-12);
  finally
    Cam.Free;
  end;

  // A perfectly flat sheet seen edge on: the half-depth along the view
  // direction is exactly zero, which is a divide by zero without the floor.
  Cam := MakeCamera;
  try
    BMin := V(-10, -10, 0);
    BMax := V( 10,  10, 0);
    Check('flat sheet is accepted', Cam.ZoomAll(BMin, BMax, ASPECT_WIDE), True);
    CheckFit('flat sheet', Cam, BMin, BMax, Zero, ASPECT_WIDE);
    CheckAtLeast('flat sheet: far is beyond near', Cam.FarPlane - Cam.NearPlane, 1e-12);

    Cam.ProjectionType := ptOrthographic;
    Check('flat sheet ortho is accepted', Cam.ZoomAll(BMin, BMax, ASPECT_WIDE), True);
    CheckFit('flat sheet ortho', Cam, BMin, BMax, Zero, ASPECT_WIDE);
    CheckAtLeast('flat sheet ortho: near plane is positive', Cam.NearPlane, 1e-12);
  finally
    Cam.Free;
  end;

  // A line: two of the three axes have no size at all.
  Cam := MakeCamera;
  try
    BMin := V(-10, 0, 0);
    BMax := V( 10, 0, 0);
    Check('line is accepted', Cam.ZoomAll(BMin, BMax, ASPECT_WIDE), True);
    CheckFit('line', Cam, BMin, BMax, Zero, ASPECT_WIDE);
  finally
    Cam.Free;
  end;

  // A margin below 1 would crop the data, which is the one thing this call
  // promises not to do, so it is clamped rather than honoured.
  Cam := MakeCamera;
  try
    BMin := V(-10, -10, -10);
    BMax := V( 10,  10,  10);
    Check('margin below 1 is accepted', Cam.ZoomAll(BMin, BMax, ASPECT_WIDE, 0.5), True);
    CheckFit('margin below 1 still shows everything', Cam, BMin, BMax, Zero, ASPECT_WIDE);
  finally
    Cam.Free;
  end;

  // A viewport that has not been sized yet.
  Cam := MakeCamera;
  try
    Check('zero aspect is accepted', Cam.ZoomAll(V(-1, -1, -1), V(1, 1, 1), 0.0), True);
    CheckFit('zero aspect falls back to square', Cam, V(-1, -1, -1), V(1, 1, 1), Zero, 1.0);
  finally
    Cam.Free;
  end;

  // An up vector parallel to the view direction has no horizon to level to,
  // and would make the view matrix NaN.  Refused, not fudged.
  Cam := MakeCamera;
  try
    Check('up parallel to the direction is refused',
      Cam.ZoomAllFromDirection(V(-1, -1, -1), V(1, 1, 1), V(0, -1, 0), V(0, 1, 0),
                               ASPECT_WIDE), False);
  finally
    Cam.Free;
  end;

  Writeln;
end;

// ---------------------------------------------------------------------------
//  9. Depth ratio - the near plane is derived from the scene, not left at
//     CAMERA_DEFAULT_NEAR, or a survey-sized dataset z-fights throughout.
// ---------------------------------------------------------------------------
procedure TestDepthRatio;
var
  Cam  : TvgCamera;
  BMin,
  BMax : TpvVector3D;
begin
  Writeln('--- depth range follows the scene size ---');

  BMin := V(-5000, -300, -5000);
  BMax := V( 5000,  300,  5000);

  Cam := MakeCamera;
  try
    Cam.ZoomAll(BMin, BMax, ASPECT_WIDE, MARGIN);
    CheckAtMost('persp: far/near stays inside float32 depth',
      Cam.FarPlane / Cam.NearPlane, 1.0e5);

    // The near plane must still clear the nearest data, or the fit clips what
    // it just framed - the other half of choosing it at all.
    CheckAtMost('persp: near plane is in front of the data',
      Cam.NearPlane, Cam.Distance - (BMax - BMin).Length * 0.5);

    Cam.ProjectionType := ptOrthographic;
    Cam.ZoomAll(BMin, BMax, ASPECT_WIDE, MARGIN);
    CheckAtMost('ortho: far/near stays inside float32 depth',
      Cam.FarPlane / Cam.NearPlane, 1.0e5);
  finally
    Cam.Free;
  end;

  Writeln;
end;

// ---------------------------------------------------------------------------
//  8. TvgScene.GetDataBounds
// ---------------------------------------------------------------------------
procedure TestSceneBounds;
var
  Scene     : TvgScene;
  StoreA,
  StoreB    : TvgObjectStore;
  O1, O2,
  O3, O4    : TvgObject;
  BMin,
  BMax      : TpvVector3D;
  Box       : TvgAABB;
begin
  Writeln('--- TvgScene.GetDataBounds ---');

  Scene := TvgScene.Create(nil);
  try
    // Nothing in it at all.
    Check('empty scene has no bounds', Scene.GetDataBounds(BMin, BMax), False);

    if not Scene.Load_Begin then
      raise Exception.Create('scene would not enter loading state');

    StoreA := TvgObjectStore.Create(nil);   // the scene owns it once added
    StoreA.SetupVertexAttributes([vdtPosition]);
    Scene.AddDataStore(StoreA);

    StoreB := TvgObjectStore.Create(nil);
    StoreB.SetupVertexAttributes([vdtPosition]);
    Scene.AddDataStore(StoreB);

    // Allocated but never written: no bounds at all.  Must contribute
    // nothing, rather than dragging the union onto the local origin.
    O1 := StoreA.AddObject(False);
    O1.AllocateVertices(2);
    Check('store present but no vertices written', Scene.GetDataBounds(BMin, BMax), False);

    // Two objects in one store.
    O1.CurrentVertex := 0;
    O1.SetVertexPosition(-4, -1, -1);
    O1.CurrentVertex := 1;
    O1.SetVertexPosition(-2,  1,  1);

    O2 := StoreA.AddObject(False);
    O2.AllocateVertices(2);
    O2.CurrentVertex := 0;
    O2.SetVertexPosition(2, -3, -1);
    O2.CurrentVertex := 1;
    O2.SetVertexPosition(4,  1,  1);

    Check('bounds available once something is written', Scene.GetDataBounds(BMin, BMax), True);
    CheckNum('union over two objects: min x', BMin.x, -4, 1e-5);
    CheckNum('union over two objects: max x', BMax.x,  4, 1e-5);
    CheckNum('union over two objects: min y', BMin.y, -3, 1e-5);

    // And across stores.
    O3 := StoreB.AddObject(False);
    O3.AllocateVertices(2);
    O3.CurrentVertex := 0;
    O3.SetVertexPosition(-1, -1, -9);
    O3.CurrentVertex := 1;
    O3.SetVertexPosition( 1,  7,  9);

    Scene.GetDataBounds(BMin, BMax);
    CheckNum('union across stores: max y', BMax.y,  7, 1e-5);
    CheckNum('union across stores: min z', BMin.z, -9, 1e-5);

    // cmNever says "my bounds cannot be trusted" - typically geometry a
    // compute shader owns.  Zooming to it would frame whatever the CPU last
    // happened to write, so it is left out.
    O4 := StoreB.AddObject(False);
    O4.AllocateVertices(2);
    O4.CurrentVertex := 0;
    O4.SetVertexPosition(500, 500, 500);
    O4.CurrentVertex := 1;
    O4.SetVertexPosition(501, 501, 501);

    Scene.GetDataBounds(BMin, BMax);
    CheckNum('cmAuto object is included', BMax.x, 501, 1e-3);

    StoreB.SetObjectCullMode(O4.ObjIndex, cmNever);
    Scene.GetDataBounds(BMin, BMax);
    CheckNum('cmNever object is excluded', BMax.x, 4, 1e-5);

    // ...but it can opt back in by supplying bounds, which is what cmManual
    // is for.  The box the application gave is the one used.
    StoreB.SetObjectBounds(O4.ObjIndex, VS(100, 100, 100), VS(120, 120, 120));
    Scene.GetDataBounds(BMin, BMax);
    CheckNum('cmManual object is included at its own bounds', BMax.x, 120, 1e-5);

    StoreB.SetObjectCullMode(O4.ObjIndex, cmNever);

    // Hiding an object takes it out of the zoom, so "zoom to all" means all
    // of what is on screen.
    O2.VisibleON := False;
    Scene.GetDataBounds(BMin, BMax);
    CheckNum('hidden object is excluded', BMax.x, 1, 1e-5);

    Scene.GetDataBounds(BMin, BMax, False);
    CheckNum('...but included when aVisibleOnly is False', BMax.x, 4, 1e-5);
    O2.VisibleON := True;

    // The local overload: the same union, left in the store's own space.
    Check('local overload reports bounds', Scene.GetDataBounds(Box), True);
    Check('local box is valid', Box.Valid, True);
    CheckNum('local box max x', Box.Max.x, 4, 1e-5);

    Scene.Load_End;
  finally
    Scene.Free;      // owns both stores
  end;

  Writeln;
end;

// ---------------------------------------------------------------------------
//  5. Survey coordinates through a WorldOrigin.
// ---------------------------------------------------------------------------
procedure TestSurveyCoordinates;
const
  OX = 612345.678;
  OY = 5432109.876;
var
  Scene  : TvgScene;
  Store  : TvgObjectStore;
  Obj    : TvgObject;
  Cam    : TvgCamera;
  Origin : TpvVector3D;
  BMin,
  BMax   : TpvVector3D;
  P0, P1 : TpvVector3D;
  EMin,
  EMax   : TpvVector3D;
begin
  Writeln('--- survey coordinates: bounds and fit through a WorldOrigin ---');

  // Six digits before the decimal, three after - float32 steps are 62.5 mm
  // there, which is the whole reason WorldOrigin exists.  The corners must
  // come back in double, absolute, to the millimetre.
  P0 := vgFromYUp(OX - 250.125, 12.5, OY - 300.875);
  P1 := vgFromYUp(OX + 250.375, 47.5, OY + 300.125);

  // P0 and P1 are two opposite corners, but NOT necessarily min and max:
  // acZUp negates a component, which leaves that axis with min > max.  That
  // is what vgRangeFromYUp is for, and what GetDataBounds must agree with.
  vgRangeFromYUp(V(OX - 250.125, 12.5, OY - 300.875),
                 V(OX + 250.375, 47.5, OY + 300.125), EMin, EMax);

  Origin := vgFromYUp(OX, 20, OY);

  Scene := TvgScene.Create(nil);
  try
    Scene.WorldOrigin := Origin;
    CheckNum('WorldOrigin accepted before any data', (Scene.WorldOrigin - Origin).Length, 0, 0);

    if not Scene.Load_Begin then
      raise Exception.Create('scene would not enter loading state');

    Store := TvgObjectStore.Create(nil);
    Store.SetupVertexAttributes([vdtPosition]);
    Scene.AddDataStore(Store);

    Obj := Store.AddObject(False);
    Obj.AllocateVertices(2);

    // SetVertexWorldPosition subtracts the origin in double and stores the
    // small offset as float32 - the path a real loader takes.
    Obj.CurrentVertex := 0;
    Obj.SetVertexWorldPosition(P0);
    Obj.CurrentVertex := 1;
    Obj.SetVertexWorldPosition(P1);

    Scene.Load_End;

    Check('survey bounds available', Scene.GetDataBounds(BMin, BMax), True);

    // 1 mm.  A union taken in world float32, or corners converted before the
    // double add, would be out by tens of millimetres here.
    CheckAtMost('survey bounds: min is exact to 1 mm', (BMin - EMin).Length, 0.001);
    CheckAtMost('survey bounds: max is exact to 1 mm', (BMax - EMax).Length, 0.001);

    Cam := TvgCamera.Create;
    try
      Scene.Cameras.AddCamera('main', Cam);
      Scene.Cameras.SetActiveCamera('main');

      Check('survey: perspective fit', Cam.ZoomAll(BMin, BMax, ASPECT_WIDE, MARGIN), True);
      CheckFit('survey persp', Cam, BMin, BMax, Origin, ASPECT_WIDE);

      Check('survey: look down', Cam.ZoomAllLookDown(BMin, BMax, ASPECT_WIDE, MARGIN), True);
      CheckFit('survey look down', Cam, BMin, BMax, Origin, ASPECT_WIDE);

      Cam.ProjectionType := ptOrthographic;
      Check('survey: ortho look down', Cam.ZoomAllLookDown(BMin, BMax, ASPECT_SQUARE, MARGIN), True);
      CheckFit('survey ortho look down', Cam, BMin, BMax, Origin, ASPECT_SQUARE);
    except
      Cam.Free;    // only if the manager never took it
      raise;
    end;
  finally
    Scene.Free;    // owns the store and, through its manager, the camera
  end;

  Writeln;
end;

// ---------------------------------------------------------------------------
//  The TvgToolManager front door.
// ---------------------------------------------------------------------------
procedure TestToolManager;
var
  Scene : TvgScene;
  Tools : TvgToolManager;
  Store : TvgObjectStore;
  Obj   : TvgObject;
  Cam   : TvgCamera;
  Zero  : TpvVector3D;
  BMin,
  BMax  : TpvVector3D;
begin
  Writeln('--- TvgToolManager entry points ---');

  Zero  := V(0, 0, 0);
  Tools := TvgToolManager.Create(nil);
  Scene := TvgScene.Create(nil);
  try
    // No scene yet: must refuse rather than reach through a nil.
    Check('no scene: ZoomAll refuses', Tools.ZoomAll, False);

    Tools.Scene := Scene;
    Check('no camera: ZoomAll refuses', Tools.ZoomAll, False);

    Cam := TvgCamera.Create;
    Cam.InitializeAsDefault;
    Scene.Cameras.AddCamera('main', Cam);
    Scene.Cameras.SetActiveCamera('main');

    Check('no data: ZoomAll refuses', Tools.ZoomAll, False);

    if not Scene.Load_Begin then
      raise Exception.Create('scene would not enter loading state');

    Store := TvgObjectStore.Create(nil);
    Store.SetupVertexAttributes([vdtPosition]);
    Scene.AddDataStore(Store);

    Obj := Store.AddObject(False);
    Obj.AllocateVertices(2);
    Obj.CurrentVertex := 0;
    Obj.SetVertexPosition(-30, -4, -20);
    Obj.CurrentVertex := 1;
    Obj.SetVertexPosition( 30,  4,  20);

    Scene.Load_End;

    Scene.GetDataBounds(BMin, BMax);

    // No linker and no renderer, so the aspect falls back to square - which
    // is exactly what a window that has not been sized yet would give.
    CheckNum('aspect falls back to square', Tools.GetViewportAspectRatio, 1.0, 0);

    Check('ZoomAll succeeds with data and a camera', Tools.ZoomAll, True);
    CheckFit('tool manager ZoomAll', Cam, BMin, BMax, Zero, 1.0);

    Check('ZoomAllLookDown succeeds', Tools.ZoomAllLookDown, True);
    CheckFit('tool manager look down', Cam, BMin, BMax, Zero, 1.0);
    CheckAtLeast('look down: eye above the data', vgUpComponent(Cam.Position), vgUpComponent(BMax));

    // The plan view switches the projection as well as the direction.
    Check('ZoomAllPlanView succeeds', Tools.ZoomAllPlanView, True);
    Check('plan view is orthographic', Cam.ProjectionType = ptOrthographic, True);
    CheckFit('tool manager plan view', Cam, BMin, BMax, Zero, 1.0);
  finally
    Tools.Free;
    Scene.Free;
  end;

  Writeln;
end;

// ---------------------------------------------------------------------------

const
  ConventionName : array[TvgAxisConvention] of string = ('Y up', 'Z up');

procedure RunFor(aConvention: TvgAxisConvention);
begin
  Writeln('===== ', ConventionName[aConvention], ' =====');
  // Refused while any camera or particle system is alive, so every test above
  // frees what it creates.
  Check('switch convention with nothing alive', vgSetAxisConvention(aConvention), True);
  Writeln;

  TestFit;
  TestLookDown;
  TestTarget;
  TestDegenerate;
  TestDepthRatio;
  TestSceneBounds;
  TestSurveyCoordinates;
  TestToolManager;
end;

begin
  try
    RunFor(acYUp);
    RunFor(acZUp);

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
