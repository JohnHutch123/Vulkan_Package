program CameraTest;

{$APPTYPE CONSOLE}

{ TvgCamera behaviour that the frustum and axis tests do not reach:

  - the cached view-projection follows the camera whichever getter runs first
  - ScreenToWorldRay and WorldToScreenPoint agree with the matrix the renderer
    draws with, and with each other, far from the origin as well as near it
  - screen up is world up, for perspective and orthographic alike
  - Zoom moves by the documented fraction }

uses
  System.SysUtils,
  System.Math,
  PasVulkan.Math,
  PasVulkan.Math.Double,
  Vulkan_Components_Camera;

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
    Writeln(Format('  ok   %-52s %.6f', [Name, Got]))
  else
  begin
    Writeln(Format('  FAIL %-52s got %.9f expected %.9f', [Name, Got, Expect]));
    Inc(Failures);
  end;
end;

procedure CheckVec(const Name: string; const Got, Expect: TpvVector3D; Tol: Double);
begin
  if (Abs(Got.x - Expect.x) <= Tol) and
     (Abs(Got.y - Expect.y) <= Tol) and
     (Abs(Got.z - Expect.z) <= Tol) then
    Writeln(Format('  ok   %-52s (%.6f %.6f %.6f)', [Name, Got.x, Got.y, Got.z]))
  else
  begin
    Writeln(Format('  FAIL %-52s got (%.9f %.9f %.9f) expected (%.9f %.9f %.9f)',
      [Name, Got.x, Got.y, Got.z, Expect.x, Expect.y, Expect.z]));
    Inc(Failures);
  end;
end;

function V(X, Y, Z: Double): TpvVector3D;
begin
  Result := TpvVector3D.Create(X, Y, Z);
end;

// Where aVP puts aP, in NDC.
function ToNDC(const aVP: TpvMatrix4x4D; const aP: TpvVector3D): TpvVector3D;
var
  C : TpvVector4D;
begin
  C      := aVP * TpvVector4D.Create(aP.x, aP.y, aP.z, 1.0);
  Result := V(C.x / C.w, C.y / C.w, C.z / C.w);
end;

function InsideAll(const F: TvgFrustrumPlanes; const P: TpvVector3D): Boolean;
var
  I : Integer;
begin
  Result := True;
  for I := 0 to 5 do
    if F.Planes[I].x * P.x + F.Planes[I].y * P.y + F.Planes[I].z * P.z + F.Planes[I].w < 0 then
      Exit(False);
end;

// ---------------------------------------------------------------------------
procedure TestCachedViewProjection;
var
  Cam : TvgCamera;
  NDC : TpvVector3D;
  S   : TpvVector3D;
  F   : TvgFrustrumPlanes;
begin
  Writeln('--- cached view-projection follows the camera ---');

  Cam := TvgCamera.Create;
  try
    Cam.InitializeFromParameters(V(10, 20, 30), V(10, 20, 0), V(0, 1, 0), 45, 0.1, 1000, 1.0);
    NDC := ToNDC(Cam.GetViewProjectionMatrix, Cam.Target);
    CheckNum('target at NDC centre after InitializeFromParameters', Hypot(NDC.x, NDC.y), 0, 1e-9);

    // GetViewProjectionMatrixForAspect rebuilds the view on a path of its own
    // and clears cfViewDirty; the cached product must still notice.
    Cam.LookAt(V(-50, 5, 7), V(-50, 5, -93), V(0, 1, 0));
    Cam.GetViewProjectionMatrixForAspect(1.0);
    NDC := ToNDC(Cam.GetViewProjectionMatrix, Cam.Target);
    CheckNum('centred when ...ForAspect ran first', Hypot(NDC.x, NDC.y), 0, 1e-9);

    Cam.LookAt(V(3, 4, 5), V(3, 4, -5), V(0, 1, 0));
    Cam.GetViewMatrix;
    NDC := ToNDC(Cam.GetViewProjectionMatrix, Cam.Target);
    CheckNum('centred when GetViewMatrix ran first', Hypot(NDC.x, NDC.y), 0, 1e-9);

    // Only the projection changes here.  A point at the top edge of a 60
    // degree field of view, 10 units ahead, sits at NDC y = +1 in the
    // camera's own (OpenGL-style, Y up) projection.
    Cam.FieldOfView := 60;
    Cam.GetProjectionMatrix;
    // (Tan(Pi / 6), not Tan(DegToRad(30)): an integer argument picks the
    // Single overload of DegToRad and costs 8 digits.)
    NDC := ToNDC(Cam.GetViewProjectionMatrix, V(3, 4 + 10 * Tan(Pi / 6), -5));
    CheckNum('field of view change reaches the cached product', NDC.y, 1.0, 1e-9);

    S := Cam.WorldToScreenPoint(Cam.Target, 800, 800);
    CheckVec('WorldToScreenPoint puts the target mid-screen', V(S.x, S.y, 0), V(400, 400, 0), 1e-9);

    Cam.LookAt(V(1000, 0, 0), V(1000, 0, -100), V(0, 1, 0));
    F := Cam.GetFrustumPlanes;
    Check('GetFrustumPlanes: new view contains its target', InsideAll(F, V(1000, 0, -50)), True);
    Check('GetFrustumPlanes: old view''s target is outside', InsideAll(F, V(3, 4, -5)), False);
  finally
    Cam.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
// Casting a ray through a pixel and projecting a point on that ray must give
// the same pixel back, and both must agree with the matrix the renderer uses.
procedure RoundTrips(Cam: TvgCamera; const Name: string; W, H: Double);
const
  Px : array[0..5] of Double = (0.5, 0.0, 1.0, 0.0, 1.0, 0.3);
  Py : array[0..5] of Double = (0.5, 0.0, 0.0, 1.0, 1.0, 0.8);
var
  I         : Integer;
  X, Y      : Double;
  Origin    : TpvVector3D;
  Dir, P, S : TpvVector3D;
  NDC       : TpvVector3D;
  Worst     : Double;
  WorstVP   : Double;
begin
  Dir := Cam.ScreenToWorldRay(W * 0.5, H * 0.5, W, H, Origin);
  CheckVec(Name + ': centre ray is the view direction', Dir, Cam.ForwardVector, 1e-9);

  Worst   := 0;
  WorstVP := 0;
  for I := 0 to High(Px) do
  begin
    X   := Px[I] * W;
    Y   := Py[I] * H;
    Dir := Cam.ScreenToWorldRay(X, Y, W, H, Origin);
    P   := Origin + Dir * 25.0;

    S     := Cam.WorldToScreenPoint(P, W, H);
    Worst := Max(Worst, Hypot(S.x - X, S.y - Y));

    // The renderer's matrix, mapped to pixels the way Vulkan's viewport does.
    NDC     := ToNDC(Cam.GetViewProjectionMatrixForAspect(W / H), P);
    WorstVP := Max(WorstVP, Hypot((NDC.x + 1) * 0.5 * W - X, (NDC.y + 1) * 0.5 * H - Y));
  end;
  CheckNum(Name + ': pixel -> ray -> pixel, worst error (px)', Worst, 0, 1e-6);
  CheckNum(Name + ': ray agrees with the render matrix (px)', WorstVP, 0, 1e-6);
end;

procedure TestScreenRays;
var
  Cam    : TvgCamera;
  Origin : TpvVector3D;
  O2     : TpvVector3D;
  Dir    : TpvVector3D;
begin
  Writeln('--- ScreenToWorldRay / WorldToScreenPoint ---');

  Cam := TvgCamera.Create;
  try
    // Camera aspect 1.0 but a 16:9 viewport: the rays must follow the
    // viewport, because that is what the renderer draws with.
    Cam.InitializeFromParameters(V(0, 0, 5), V(0, 0, 0), V(0, 1, 0), 45, 0.1, 10000, 1.0);
    RoundTrips(Cam, 'near origin', 1920, 1080);

    // The old ray ran from the world origin, not the eye: 6 degrees out here
    // and pointing almost straight up at (0, 100000, 0).
    Cam.LookAt(V(1000, 0, 1000), V(1000, 0, 990), V(0, 1, 0));
    RoundTrips(Cam, 'at (1000, 0, 1000)', 1920, 1080);

    Cam.LookAt(V(0, 100000, 0), V(0, 100000, -10), V(0, 1, 0));
    RoundTrips(Cam, 'at (0, 100000, 0)', 1920, 1080);

    // Survey coordinates, Z up, looking north and slightly down.
    Cam.LookAt(V(523456.789, 875432.109, 150.25), V(523456.789, 875532.109, 120.0), V(0, 0, 1));
    RoundTrips(Cam, 'survey coordinates', 1920, 1080);

    Cam.SetOrthographic(-10, 10, 10, -10, 0.1, 1000);
    RoundTrips(Cam, 'orthographic, survey coordinates', 1920, 1080);

    // Orthographic rays are parallel, so the origin is what varies.
    Dir := Cam.ScreenToWorldRay(0, 0, 1920, 1080, Origin);
    CheckVec('orthographic corner ray is the view direction', Dir, Cam.ForwardVector, 1e-9);
    Cam.ScreenToWorldRay(1920, 1080, 1920, 1080, O2);
    Check('orthographic rays start at different points', (Origin - O2).Length > 1.0, True);
  finally
    Cam.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure UpIsUp(Cam: TvgCamera; const Name: string);
var
  Above, Right : TpvVector3D;
begin
  Above := Cam.WorldToScreenPoint(Cam.Target + Cam.UpVector * 0.5, 1000, 1000);
  Right := Cam.WorldToScreenPoint(Cam.Target + Cam.RightVector * 0.5, 1000, 1000);
  Check(Name + ': a point above the target is in the top half', Above.y < 500, True);
  Check(Name + ': a point to the right is in the right half', Right.x > 500, True);
end;

procedure TestOrientation;
var
  Cam : TvgCamera;
begin
  Writeln('--- screen orientation ---');

  Cam := TvgCamera.Create;
  try
    Cam.InitializeFromParameters(V(0, 0, 5), V(0, 0, 0), V(0, 1, 0), 45, 0.1, 100, 1.0);
    UpIsUp(Cam, 'perspective');

    // BuildProjectionForAspect negated Y only for perspective, so an
    // orthographic camera drew upside down.
    Cam.SetOrthographic(-2, 2, 2, -2, 0.1, 100);
    UpIsUp(Cam, 'orthographic');
  finally
    Cam.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
// ViewUpVector is the screen's up in the world.  The HUD axis gizmo is drawn
// from it: drawn from UpVector - the orbit reference, which never tilts - it
// turned with the yaw only.
procedure TestViewUp;
var
  Cam    : TvgCamera;
  U, P   : TpvVector3D;
  S0, S1 : TpvVector3D;
begin
  Writeln('--- view up ---');

  Cam := TvgCamera.Create;
  try
    Cam.InitializeFromParameters(V(0, 0, 5), V(0, 0, 0), V(0, 1, 0), 45, 0.1, 100, 1.0);
    CheckVec('level: the view up is the reference up', Cam.ViewUpVector, V(0, 1, 0), 1e-12);

    Cam.Orbit(0, 30);
    U := Cam.ViewUpVector;
    CheckVec('pitched: the reference up stays', Cam.UpVector, V(0, 1, 0), 0);
    CheckNum('...the view up is a unit vector', U.Length, 1, 1e-12);
    CheckNum('...at right angles to the view', U.Dot(Cam.ForwardVector), 0, 1e-12);
    CheckNum('...and to the right vector', U.Dot(Cam.RightVector), 0, 1e-12);
    // cos 30 as Sqrt(3)/2: Delphi resolves DegToRad(30) to its Single
    // overload, which is only good to 1e-8.
    CheckNum('...tilted by the pitch (cos 30)', U.Dot(Cam.UpVector), Sqrt(3.0) / 2, 1e-9);

    // And it is up on the screen: a step along it from the target moves
    // straight up in the image (y decreases), not sideways.
    P  := Cam.Target;
    S0 := Cam.WorldToScreenPoint(P, 800, 600);
    S1 := Cam.WorldToScreenPoint(P + U * 0.1, 800, 600);
    CheckNum('...a step along it: no sideways move on screen', S1.x - S0.x, 0, 1e-6);
    Check('...and up the screen', S1.y < S0.y, True);

    // Yaw alone keeps it level.
    Cam.Orbit(0, -30);
    Cam.Orbit(40, 0);
    CheckVec('yawed only: level again', Cam.ViewUpVector, V(0, 1, 0), 1e-9);
  finally
    Cam.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestZoom;
var
  Cam : TvgCamera;
begin
  Writeln('--- zoom ---');

  Cam := TvgCamera.Create;
  try
    Cam.InitializeFromParameters(V(0, 0, 10), V(0, 0, 0), V(0, 1, 0));

    // Zoom read its own uninitialised local variable instead of the
    // Distance property, so the step size was garbage.
    Cam.Zoom(1);
    CheckNum('Zoom(1) moves 10% closer', Cam.Distance, 9.0, 1e-9);
    Cam.Zoom(-1);
    CheckNum('Zoom(-1) moves 10% further', Cam.Distance, 9.9, 1e-9);
    CheckVec('zoom keeps the view direction', Cam.ForwardVector, V(0, 0, -1), 1e-12);
  finally
    Cam.Free;
  end;
  Writeln;
end;

begin
  try
    TestCachedViewProjection;
    TestScreenRays;
    TestOrientation;
    TestZoom;
    TestViewUp;

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
