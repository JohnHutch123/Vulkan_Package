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

// ---------------------------------------------------------------------------
// First person: Look turns the view about the eye, Translate moves both.
procedure TestLookAndTranslate;
var
  Cam     : TvgCamera;
  P0, T0  : TpvVector3D;
  Elev    : Double;
  I       : Integer;
  Base    : TpvVector3D;
begin
  Writeln('--- look / translate ---');

  Cam := TvgCamera.Create;
  try
    // Z up, looking along +X from (0,0,2), target 10 ahead.
    Cam.InitializeFromParameters(V(0, 0, 2), V(10, 0, 2), V(0, 0, 1));
    P0 := Cam.Position;

    Cam.Look(90, 0);
    CheckVec('Look(90,0): eye stays put', Cam.Position, P0, 1e-12);
    CheckVec('...turns left: +X becomes +Y', Cam.ForwardVector, V(0, 1, 0), 1e-12);
    CheckNum('...target distance kept', Cam.Distance, 10, 1e-9);

    Cam.Look(-90, 0);
    CheckVec('Look(-90,0) undoes it', Cam.ForwardVector, V(1, 0, 0), 1e-12);

    Cam.Look(0, 30);
    CheckVec('Look(0,30): eye stays put', Cam.Position, P0, 1e-12);
    CheckNum('...view raised 30 degrees',
      RadToDeg(ArcSin(Cam.ForwardVector.z)), 30, 1e-9);
    CheckVec('...screen up still leans to world up (no roll)',
      V(0, Cam.ViewUpVector.y, 0), V(0, 0, 0), 1e-12);

    // Pitch stops short of the pole whatever is asked.
    for I := 1 to 10 do Cam.Look(0, 45);
    Elev := RadToDeg(ArcSin(Cam.ForwardVector.z));
    CheckNum('pitch clamps at 89 degrees', Elev, 89, 1e-9);
    Check('...view direction still finite', not IsNan(Cam.ForwardVector.x), True);
    for I := 1 to 10 do Cam.Look(0, -45);
    CheckNum('...and at -89 going down', RadToDeg(ArcSin(Cam.ForwardVector.z)), -89, 1e-9);

    // Yaw while pitched keeps the pitch.
    Cam.Look(0, 89 - 20);       // back to -20
    Cam.Look(37, 0);
    CheckNum('yaw keeps the pitch', RadToDeg(ArcSin(Cam.ForwardVector.z)), -20, 1e-9);

    // Translate moves both points, nothing else.
    T0 := Cam.Target;
    P0 := Cam.Position;
    Cam.Translate(V(1, -2, 3));
    CheckVec('Translate moves the eye', Cam.Position, P0 + V(1, -2, 3), 1e-12);
    CheckVec('...and the target', Cam.Target, T0 + V(1, -2, 3), 1e-12);

    // Survey-sized coordinates: double precision all the way.
    Base := V(512345.678, 6123456.789, 102.5);
    Cam.InitializeFromParameters(Base, Base + V(10, 0, 0), V(0, 0, 1));
    Cam.Look(45, 10);
    Cam.Look(-45, -10);
    CheckVec('survey coords: look round and back, eye exact', Cam.Position, Base, 0);
    CheckVec('...target back within 1e-6', Cam.Target, Base + V(10, 0, 0), 1e-6);
    Cam.Translate(V(0.001, 0, 0));
    CheckNum('...a 1 mm step survives', Cam.Position.x - Base.x, 0.001, 1e-7);

    // Y-up convention works the same way.
    Cam.InitializeFromParameters(V(0, 0, 0), V(0, 0, -5), V(0, 1, 0));
    Cam.Look(90, 0);
    CheckVec('Y up: Look(90,0) turns -Z to -X', Cam.ForwardVector, V(-1, 0, 0), 1e-12);
  finally
    Cam.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
//  Stereo pair (TvgStereoSettings and the eye functions)
// ---------------------------------------------------------------------------

function SameMatrix(const A, B: TpvMatrix4x4D; Tol: Double): Boolean;
var
  I, J : Integer;
begin
  Result := True;
  for I := 0 to 3 do
    for J := 0 to 3 do
      if Abs(A.RawComponents[I, J] - B.RawComponents[I, J]) > Tol then
        Exit(False);
end;

function InsideTol(const F: TvgFrustrumPlanes; const P: TpvVector3D; Tol: Double): Boolean;
var
  I : Integer;
begin
  Result := True;
  for I := 0 to 5 do
    if F.Planes[I].x * P.x + F.Planes[I].y * P.y + F.Planes[I].z * P.z + F.Planes[I].w < -Tol then
      Exit(False);
end;

// NDC (x, y, z) back to a local point through aVP.
function FromNDC(const aInvVP: TpvMatrix4x4D; X, Y, Z: Double): TpvVector3D;
var
  C : TpvVector4D;
begin
  C      := aInvVP * TpvVector4D.Create(X, Y, Z, 1.0);
  Result := V(C.x / C.w, C.y / C.w, C.z / C.w);
end;

procedure TestStereo;
const
  ASPECT = 0.9;            // one eye of a 16:10 window split in two
  SEP    = 0.064;
  CONV   = 10.0;
var
  Cam      : TvgCamera;
  Origin   : TpvVector3D;
  Fwd, Rt  : TpvVector3D;
  Up       : TpvVector3D;
  PosL     : TpvVector3D;
  EL, ER   : TpvVector3D;
  VPL, VPR : TpvMatrix4x4D;
  VPM      : TpvMatrix4x4D;
  InvL     : TpvMatrix4x4D;
  InvR     : TpvMatrix4x4D;
  NL, NR   : TpvVector3D;
  P        : TpvVector3D;
  F        : TvgFrustrumPlanes;
  FM       : TvgFrustrumPlanes;
  Rev      : UInt64;
  I        : Integer;
  Shift    : Double;
  Ok, Hit  : Boolean;
  Other    : TvgStereoSettings;
  Seed     : Cardinal;

  function Rnd: Double;
  begin
    Seed := Seed xor (Seed shl 13); Seed := Seed xor (Seed shr 17); Seed := Seed xor (Seed shl 5);
    Result := Seed / 4294967296.0;
  end;

  // A point aAhead along the view from the camera, aRight / aUp across it,
  // relative to Origin.
  function Ahead(aAhead, aRight, aUp: Double): TpvVector3D;
  begin
    Result := PosL + Fwd * aAhead + Rt * aRight + Up * aUp;
  end;

begin
  Writeln('--- stereo pair ---');
  Seed := 2463534242;
  Cam := TvgCamera.Create;
  Other := TvgStereoSettings.Create;
  try
    Check('Stereo: off by default', Cam.Stereo.Enabled, False);
    CheckNum('...EyeSeparation 0.064', Cam.Stereo.EyeSeparation, SEP, 0);
    CheckNum('...Convergence 10', Cam.Stereo.Convergence, CONV, 0);

    Rev := Cam.Revision;
    Cam.Stereo.Enabled := True;
    Check('changing a setting bumps Revision', Cam.Revision > Rev, True);
    Rev := Cam.Revision;
    Cam.Stereo.Enabled := True;
    Check('...setting the same value does not', Cam.Revision = Rev, True);
    Cam.Stereo.EyeSeparation := -1;
    CheckNum('negative EyeSeparation becomes 0', Cam.Stereo.EyeSeparation, 0, 0);
    Cam.Stereo.Convergence := 0;
    CheckNum('Convergence 0 becomes the default', Cam.Stereo.Convergence, CONV, 0);
    Other.EyeSeparation := 0.1;
    Other.Convergence   := 3;
    Other.SwapEyes      := True;
    Cam.Stereo := Other;
    Check('assigning Stereo copies it (not the same object)',
          (Cam.Stereo <> Other) and SameValue(Cam.Stereo.EyeSeparation, 0.1) and
          (Cam.Stereo.Convergence = 3) and Cam.Stereo.SwapEyes and not Cam.Stereo.Enabled, True);
    Cam.Stereo.EyeSeparation := SEP;
    Cam.Stereo.Convergence   := CONV;

    // A survey-sized camera, looking obliquely and a little down.
    Origin := V(512345.25, 6987654.75, 230.0);
    Cam.InitializeFromParameters(Origin + V(3, -4, 1.7), Origin + V(13, 2, 0.5), V(0, 0, 1));
    PosL := Cam.Position - Origin;
    Fwd  := Cam.ForwardVector;
    Rt   := Cam.RightVector;
    Up   := Cam.ViewUpVector;

    EL := Cam.EyePosition(eyLeft);
    ER := Cam.EyePosition(eyRight);
    CheckVec('the eyes are either side of Position', (EL + ER) * 0.5, Cam.Position, 1e-9);
    CheckNum('...EyeSeparation apart', (ER - EL).Length, SEP, 1e-9);
    CheckNum('...along RightVector (right eye on the right)', (ER - EL).Normalize.Dot(Rt), 1, 1e-12);

    VPL := Cam.GetEyeViewProjectionMatrixForAspect(eyLeft,  ASPECT, Origin);
    VPR := Cam.GetEyeViewProjectionMatrixForAspect(eyRight, ASPECT, Origin);
    VPM := Cam.GetViewProjectionMatrixForAspect(ASPECT, Origin);
    Check('eye VP = eye projection x eye view',
          SameMatrix(VPL, Cam.GetEyeViewMatrixForOrigin(eyLeft, Origin) *
                          Cam.GetEyeProjectionMatrixForAspect(eyLeft, ASPECT), 1e-12), True);

    // Zero parallax on the whole convergence plane; no vertical parallax.
    Ok := True; Hit := True;
    for I := 1 to 50 do
    begin
      P  := Ahead(CONV, (Rnd - 0.5) * 6, (Rnd - 0.5) * 4);
      NL := ToNDC(VPL, P);
      NR := ToNDC(VPR, P);
      if Abs(NL.x - NR.x) > 1e-9 then Ok := False;
      if (Abs(NL.y - NR.y) > 1e-9) or (Abs(NL.y - ToNDC(VPM, P).y) > 1e-9) then Hit := False;
    end;
    Check('a point at Convergence: the same x in both eyes', Ok, True);
    Check('...and the same y as mono (no vertical parallax)', Hit, True);
    CheckNum('straight ahead at Convergence is the centre', ToNDC(VPL, Ahead(CONV, 0, 0)).x, 0, 1e-9);

    // At infinity the eyes differ by twice the projection shift.
    Shift := (SEP * 0.5) * (Cos(DegToRad(Cam.FieldOfView) / 2) / Sin(DegToRad(Cam.FieldOfView) / 2)) /
             (ASPECT * CONV);
    P := Ahead(1e9, 0, 0);
    CheckNum('a point at infinity: right eye at +shift', ToNDC(VPR, P).x,  Shift, 1e-7);
    CheckNum('...left eye at -shift', ToNDC(VPL, P).x, -Shift, 1e-7);
    P := Ahead(2, 0, 0);
    Check('nearer than Convergence: crossed (in front of the screen)',
          ToNDC(VPR, P).x < ToNDC(VPL, P).x, True);
    P := Ahead(40, 1, 0.5);
    Check('further: uncrossed (behind the screen)', ToNDC(VPR, P).x > ToNDC(VPL, P).x, True);

    // The eyes are symmetric about the mono view: their NDC x average is
    // mono's for points at Convergence and at any depth the same pair...
    P := Ahead(25, -2, 1);
    CheckNum('the eyes average to mono', (ToNDC(VPL, P).x + ToNDC(VPR, P).x) * 0.5, ToNDC(VPM, P).x, 1e-9);
    CheckNum('...and share mono''s depth', ToNDC(VPL, P).z, ToNDC(VPM, P).z, 1e-9);

    // Survey precision: the local result does not depend on how far away
    // the origin is - the same view with the origin at (0, 0, 0) and the
    // camera near it gives the same matrix.
    Cam.InitializeFromParameters(V(3, -4, 1.7), V(13, 2, 0.5), V(0, 0, 1));
    Check('survey origin: eye VP matches the same view near (0,0,0)',
          SameMatrix(VPL, Cam.GetEyeViewProjectionMatrixForAspect(eyLeft, ASPECT, V(0, 0, 0)), 1e-9), True);
    Cam.InitializeFromParameters(Origin + V(3, -4, 1.7), Origin + V(13, 2, 0.5), V(0, 0, 1));

    // Separation 0: two mono eyes.
    Cam.Stereo.EyeSeparation := 0;
    Check('EyeSeparation 0: each eye is the mono VP',
          SameMatrix(Cam.GetEyeViewProjectionMatrixForAspect(eyRight, ASPECT, Origin), VPM, 1e-12), True);
    Cam.Stereo.EyeSeparation := SEP;

    // The cull volume holds both frusta (and mono's).
    F    := Cam.GetStereoFrustumPlanesForAspect(ASPECT, Origin);
    FM   := Cam.GetFrustumPlanesForAspect(ASPECT, Origin);
    InvL := VPL.Inverse;
    InvR := VPR.Inverse;
    Ok := True;
    for I := 1 to 2000 do
    begin
      // NDC depth 0.05..0.999 is inside for both depth conventions.
      P := FromNDC(InvL, Rnd * 2 - 1, Rnd * 2 - 1, 0.05 + Rnd * 0.949);
      if not InsideTol(F, P, 1e-6) then Ok := False;
      P := FromNDC(InvR, Rnd * 2 - 1, Rnd * 2 - 1, 0.05 + Rnd * 0.949);
      if not InsideTol(F, P, 1e-6) then Ok := False;
      P := FromNDC(VPM.Inverse, Rnd * 2 - 1, Rnd * 2 - 1, 0.05 + Rnd * 0.949);
      if not InsideTol(F, P, 1e-6) then Ok := False;
    end;
    Check('stereo cull volume holds both eyes'' frusta, and mono''s', Ok, True);
    // ...the far corners of each (NDC depth 0.99999 is about 1800 away with
    // the default near/far - far beyond Convergence).
    Ok := True;
    for I := 0 to 3 do
    begin
      P := FromNDC(InvL, 2 * (I and 1) - 1, 2 * (I shr 1) - 1, 0.99999);
      if not InsideTol(F, P, 1e-6) then Ok := False;
      P := FromNDC(InvR, 2 * (I and 1) - 1, 2 * (I shr 1) - 1, 0.99999);
      if not InsideTol(F, P, 1e-6) then Ok := False;
    end;
    Check('...including the far corners of each', Ok, True);
    // Not simply each eye's outer plane: just outside the right eye's left
    // edge, beyond Convergence, is outside the left eye too - and outside
    // the volume.
    P := FromNDC(InvR, -1.05, 0, 0.9999);     // about 200 away
    Check('beyond Convergence the right eye''s left edge is the outer one',
          (ToNDC(VPL, P).x < -1) and not InsideTol(F, P, 0), True);
    Check('...a point inside every eye is inside', InsideTol(F, Ahead(30, 0, 0), 0), True);
    Check('...and the volume is no looser than mono on top/bottom/near/far',
          (Abs(F.Planes[FRUSTUM_PLANE_TOP].w    - FM.Planes[FRUSTUM_PLANE_TOP].w)    < 1e-6) and
          (Abs(F.Planes[FRUSTUM_PLANE_BOTTOM].w - FM.Planes[FRUSTUM_PLANE_BOTTOM].w) < 1e-6) and
          (Abs(F.Planes[FRUSTUM_PLANE_NEAR].w   - FM.Planes[FRUSTUM_PLANE_NEAR].w)   < 1e-6) and
          (Abs(F.Planes[FRUSTUM_PLANE_FAR].w    - FM.Planes[FRUSTUM_PLANE_FAR].w)    < 1e-6), True);

    // Orthographic: no parallax, the mono results.
    Cam.SetOrthographic(-5, 5, 4, -4, 0.1, 500);
    VPM := Cam.GetViewProjectionMatrixForAspect(ASPECT, Origin);
    Check('orthographic: each eye is the mono VP',
          SameMatrix(Cam.GetEyeViewProjectionMatrixForAspect(eyLeft,  ASPECT, Origin), VPM, 0) and
          SameMatrix(Cam.GetEyeViewProjectionMatrixForAspect(eyRight, ASPECT, Origin), VPM, 0), True);
    CheckVec('...the eyes are at Position', Cam.EyePosition(eyRight), Cam.Position, 0);
    FM := Cam.GetFrustumPlanesForAspect(ASPECT, Origin);
    F  := Cam.GetStereoFrustumPlanesForAspect(ASPECT, Origin);
    Ok := True;
    for I := 0 to 5 do
      if (F.Planes[I] - FM.Planes[I]).Length > 0 then Ok := False;
    Check('...the cull volume is mono''s', Ok, True);
  finally
    Other.Free;
    Cam.Free;
  end;
  Writeln;
end;

begin
  try
    TestStereo;
    TestLookAndTranslate;
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
