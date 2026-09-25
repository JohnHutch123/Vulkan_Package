program AxisConventionTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Math,
  PasVulkan.Math,
  PasVulkan.Math.Double,
  Vulkan_Assert,
  Vulkan_WorldAxes,
  Vulkan_Components_Camera;

var
  Failures : Integer = 0;

procedure Check(const Name: string; Got, Expect: Boolean);
begin
  if Got = Expect then
    Writeln(Format('  ok   %-40s %s', [Name, BoolToStr(Got, True)]))
  else
  begin
    Writeln(Format('  FAIL %-40s got %s expected %s',
      [Name, BoolToStr(Got, True), BoolToStr(Expect, True)]));
    Inc(Failures);
  end;
end;

procedure CheckVec(const Name: string; const Got, Expect: TpvVector3D; Tol: Double);
begin
  if (Abs(Got.x - Expect.x) <= Tol) and
     (Abs(Got.y - Expect.y) <= Tol) and
     (Abs(Got.z - Expect.z) <= Tol) then
    Writeln(Format('  ok   %-40s (%.3f %.3f %.3f)', [Name, Got.x, Got.y, Got.z]))
  else
  begin
    Writeln(Format('  FAIL %-40s got (%.3f %.3f %.3f) expected (%.3f %.3f %.3f)',
      [Name, Got.x, Got.y, Got.z, Expect.x, Expect.y, Expect.z]));
    Inc(Failures);
  end;
end;

procedure CheckNum(const Name: string; Got, Expect, Tol: Double);
begin
  if Abs(Got - Expect) <= Tol then
    Writeln(Format('  ok   %-40s %.4f', [Name, Got]))
  else
  begin
    Writeln(Format('  FAIL %-40s got %.4f expected %.4f', [Name, Got, Expect]));
    Inc(Failures);
  end;
end;

function V(X, Y, Z: Double): TpvVector3D;
begin
  Result := TpvVector3D.Create(X, Y, Z);
end;

function Transform(const M: TpvMatrix4x4D; const P: TpvVector3D): TpvVector3D;
begin
  Result := (M * TpvVector4D.Create(P.x, P.y, P.z, 1.0)).xyz;
end;

function MatrixIsFinite(const M: TpvMatrix4x4D): Boolean;
var
  I, J : Integer;
begin
  Result := True;
  for I := 0 to 3 do
    for J := 0 to 3 do
      if IsNan(M.RawComponents[I, J]) or IsInfinite(M.RawComponents[I, J]) then
        Exit(False);
end;

// Height of the eye above the target, in degrees.
function Elevation(Cam: TvgCamera): Double;
begin
  Result := RadToDeg(ArcSin(EnsureRange(
    vgUpComponent((Cam.Position - Cam.Target).Normalize), -1.0, 1.0)));
end;

// CustomAssert raises in DEBUG builds and only logs otherwise; either way a
// refused change must leave the convention where it was.
function TrySetConvention(aValue: TvgAxisConvention): Boolean;
begin
  try
    Result := vgSetAxisConvention(aValue);
  except
    on EvgVulkanAssertException do
      Result := False;
  end;
end;

const
  ConventionName : array[TvgAxisConvention] of string = ('acYUp', 'acZUp');

// ---------------------------------------------------------------------------
procedure TestBasis;
var
  M : TpvMatrix4x4D;
begin
  Writeln('--- basis and conversions ---');

  if vgAxisConvention = acZUp then
  begin
    CheckVec('up is +Z', vgWorldUp, V(0, 0, 1), 1e-6);
    CheckVec('forward is +Y', vgWorldForward, V(0, 1, 0), 1e-6);
  end
  else
  begin
    CheckVec('up is +Y', vgWorldUp, V(0, 1, 0), 1e-6);
    CheckVec('forward is -Z', vgWorldForward, V(0, 0, -1), 1e-6);
  end;

  // Right-handed: the same cross product gives up in both conventions.
  CheckVec('Right x Forward = Up', vgWorldRight.Cross(vgWorldForward), vgWorldUp, 1e-6);
  CheckNum('up component of up', vgUpComponent(vgWorldUp), 1.0, 1e-6);
  CheckNum('up component of forward', vgUpComponent(vgWorldForward), 0.0, 1e-6);

  CheckVec('FromYUp maps Y-up up to up', vgFromYUp(0, 1, 0), vgWorldUp, 1e-6);
  CheckVec('ToYUp(FromYUp(v)) = v', vgToYUp(vgFromYUp(V(1, 2, 3))), V(1, 2, 3), 1e-6);

  // A rotation, not a reflection: winding and culling must not change.
  M := vgYUpToWorldMatrix;
  CheckNum('det(YUpToWorld) = +1', M.Determinant, 1.0, 1e-6);
  CheckVec('matrix agrees with vgFromYUp', Transform(M, V(1, 2, 3)), vgFromYUp(1, 2, 3), 1e-5);
  CheckVec('WorldToYUp undoes YUpToWorld',
    Transform(vgWorldToYUpMatrix, Transform(M, V(1, 2, 3))), V(1, 2, 3), 1e-5);

  CheckVec('horizontal plane normal is up', vgPlaneNormal(wpHorizontal), vgWorldUp, 1e-6);
  CheckNum('front plane is vertical', vgUpComponent(vgPlaneNormal(wpFront)), 0.0, 1e-6);
  CheckNum('side plane is vertical', vgUpComponent(vgPlaneNormal(wpSide)), 0.0, 1e-6);
  CheckNum('front and side planes differ',
    vgPlaneNormal(wpFront).Dot(vgPlaneNormal(wpSide)), 0.0, 1e-6);
  if vgAxisConvention = acYUp then
    // Must match what the drag tool always used, so Y-up users see no change.
    CheckVec('Y-up front plane unchanged', vgPlaneNormal(wpFront), V(0, 0, 1), 1e-6);
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestCamera;
var
  Cam    : TvgCamera;
  Ray, N : TpvVector3D;
  T      : Double;
begin
  Writeln('--- camera defaults ---');

  Cam := TvgCamera.Create;
  try
    CheckVec('new camera up', Cam.UpVector, vgWorldUp, 1e-6);
    Check('new camera view matrix finite', MatrixIsFinite(Cam.GetViewMatrix), True);
    Check('new camera not looking along up',
      Abs(Cam.ForwardVector.Dot(vgWorldUp)) < 0.99, True);

    Cam.InitializeAsDefault;
    CheckVec('default camera up', Cam.UpVector, vgWorldUp, 1e-6);
    Check('default view matrix finite', MatrixIsFinite(Cam.GetViewMatrix), True);
    Check('default camera above the ground', vgUpComponent(Cam.Position) > 0, True);

    // The centre of the screen must land on the target, on the ground plane.
    Ray := Cam.ScreenToWorldRay(50, 50, 100, 100);
    N   := vgPlaneNormal(wpHorizontal);
    Check('centre ray points down at the ground', Ray.Dot(N) < 0, True);
    T := -Cam.Position.Dot(N) / Ray.Dot(N);
    CheckVec('centre ray hits the target',
      Cam.Position + Ray * T, Cam.Target, 1e-3);
  finally
    Cam.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestOrbit;
var
  Cam     : TvgCamera;
  P0      : TpvVector3D;
  H0, D0  : Double;
  E0      : Double;
  I       : Integer;
begin
  Writeln('--- camera orbit ---');

  Cam := TvgCamera.Create;
  try
    Cam.InitializeAsDefault;
    P0 := Cam.Position;
    H0 := vgUpComponent(Cam.Position - Cam.Target);
    D0 := Cam.Distance;

    for I := 1 to 18 do
      Cam.Orbit(10, 0, True);
    CheckNum('yaw keeps height (180 deg)', vgUpComponent(Cam.Position - Cam.Target), H0, 1e-3);
    CheckNum('yaw keeps distance (180 deg)', Cam.Distance, D0, 1e-3);
    // Half a turn about up negates both horizontal components and keeps height.
    CheckVec('180 deg yaw is opposite side',
      Cam.Position, V(-P0.x, 0, 0) + vgWorldUp * vgUpComponent(P0) -
                    vgWorldForward * P0.Dot(vgWorldForward), 1e-3);

    for I := 1 to 18 do
      Cam.Orbit(10, 0, True);
    CheckVec('360 deg yaw returns to start', Cam.Position, P0, 1e-3);

    E0 := Elevation(Cam);
    Cam.Orbit(0, 5, True);
    Check('positive pitch raises the eye', Elevation(Cam) > E0, True);
    CheckNum('pitch keeps distance', Cam.Distance, D0, 1e-3);

    for I := 1 to 40 do
      Cam.Orbit(3, 10, True);
    Check('pitch stops short of the top pole', Elevation(Cam) <= 89.01, True);
    Check('view matrix finite at the top', MatrixIsFinite(Cam.GetViewMatrix), True);

    for I := 1 to 40 do
      Cam.Orbit(3, -10, True);
    Check('pitch stops short of the bottom pole', Elevation(Cam) >= -89.01, True);
    Check('view matrix finite at the bottom', MatrixIsFinite(Cam.GetViewMatrix), True);
    CheckNum('distance survives the poles', Cam.Distance, D0, 1e-2);
  finally
    Cam.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestLock;
const
  Other : array[TvgAxisConvention] of TvgAxisConvention = (acZUp, acYUp);
var
  Cam  : TvgCamera;
  Conv : TvgAxisConvention;
begin
  Writeln('--- set-once rule ---');

  Conv := vgAxisConvention;
  CheckNum('no live users between tests', vgAxisConventionUsers, 0, 0);

  Cam := TvgCamera.Create;
  try
    CheckNum('camera holds the convention', vgAxisConventionUsers, 1, 0);
    Check('change refused while a camera lives', TrySetConvention(Other[Conv]), False);
    Check('convention left unchanged', vgAxisConvention = Conv, True);
    Check('setting the same value is allowed', TrySetConvention(Conv), True);
  finally
    Cam.Free;
  end;

  CheckNum('camera releases on free', vgAxisConventionUsers, 0, 0);
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure RunFor(aConvention: TvgAxisConvention);
begin
  Writeln('===== ', ConventionName[aConvention], ' =====');
  Check('switch convention with nothing alive', TrySetConvention(aConvention), True);
  Writeln;

  TestBasis;
  TestCamera;
  TestOrbit;
  TestLock;
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
