program FrustumTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Math,
  PasVulkan.Math,
  Vulkan_Components_Camera;

var
  Failures : Integer = 0;

function Dist(const P: TpvVector4; X, Y, Z: Single): Single;
begin
  Result := P.x * X + P.y * Y + P.z * Z + P.w;
end;

function InsideAll(const F: TvgFrustrumPlanes; X, Y, Z: Single): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 0 to 5 do
    if Dist(F.Planes[I], X, Y, Z) < 0 then
      Exit(False);
end;

procedure CheckInside(const F: TvgFrustrumPlanes; const Name: string; X, Y, Z: Single; Expect: Boolean);
var
  Got: Boolean;
begin
  Got := InsideAll(F, X, Y, Z);
  if Got = Expect then
    Writeln(Format('  ok   %-28s inside=%s', [Name, BoolToStr(Got, True)]))
  else
  begin
    Writeln(Format('  FAIL %-28s inside=%s expected=%s', [Name, BoolToStr(Got, True), BoolToStr(Expect, True)]));
    Inc(Failures);
  end;
end;

procedure CheckNear(const Name: string; Got, Expect, Tol: Single);
begin
  if Abs(Got - Expect) <= Tol then
    Writeln(Format('  ok   %-28s %.4f (expected %.4f)', [Name, Got, Expect]))
  else
  begin
    Writeln(Format('  FAIL %-28s %.4f (expected %.4f +/- %.4f)', [Name, Got, Expect, Tol]));
    Inc(Failures);
  end;
end;

procedure CheckNormalised(const F: TvgFrustrumPlanes; const Name: string);
var
  I: Integer;
  L: Single;
begin
  for I := 0 to 5 do
  begin
    L := Sqrt(Sqr(F.Planes[I].x) + Sqr(F.Planes[I].y) + Sqr(F.Planes[I].z));
    if Abs(L - 1.0) > 1e-4 then
    begin
      Writeln(Format('  FAIL %-28s plane %d normal length = %.6f', [Name, I, L]));
      Inc(Failures);
      Exit;
    end;
  end;
  Writeln(Format('  ok   %-28s all 6 normals unit length', [Name]));
end;

var
  Cam    : TvgCamera;
  F      : TvgFrustrumPlanes;
  HalfH  : Single;

begin
  try
    Cam := TvgCamera.Create;
    try
      // Camera 5 units back on +Z looking at the origin down -Z.
      Cam.InitializeFromParameters(TpvVector3.Create(0, 0, 5),
                                   TpvVector3.Create(0, 0, 0),
                                   TpvVector3.Create(0, 1, 0),
                                   45.0,    // FOV
                                   0.01,    // near
                                   1000.0,  // far
                                   1.0);    // aspect

      // Half-height of the frustum at the origin (5 units in front of the eye).
      HalfH := 5.0 * Tan(DegToRad(45.0) / 2);
      Writeln(Format('Frustum half-extent at the origin = %.4f', [HalfH]));
      Writeln;

      Writeln('--- GetFrustumPlanesForAspect(1.0), perspective ---');
      F := Cam.GetFrustumPlanesForAspect(1.0);

      CheckNormalised(F, 'normalisation');

      // Signed distance from the origin to the near plane.  Near plane sits at
      // z = 5 - 0.01 = 4.99, the origin is 4.99 in front of it.
      CheckNear('origin -> near plane', Dist(F.Planes[FRUSTUM_PLANE_NEAR], 0, 0, 0), 4.99, 0.01);
      // Far plane at z = 5 - 1000; origin is 995 inside it.  The tolerance is
      // wide because a near/far ratio of 100000 makes the far plane's
      // extraction (w - z, two nearly equal numbers) badly conditioned in
      // float32; see the tight check under 'well-conditioned depth range'.
      CheckNear('origin -> far plane', Dist(F.Planes[FRUSTUM_PLANE_FAR], 0, 0, 0), 995.0, 6.0);

      CheckInside(F, 'origin',                 0,   0,    0,   True);
      CheckInside(F, 'behind camera',          0,   0,   50,   False);
      CheckInside(F, 'beyond far plane',       0,   0, -2000,  False);
      CheckInside(F, 'inside right edge',  HalfH * 0.9, 0, 0,  True);
      CheckInside(F, 'outside right edge', HalfH * 1.1, 0, 0,  False);
      CheckInside(F, 'inside left edge',  -HalfH * 0.9, 0, 0,  True);
      CheckInside(F, 'outside left edge', -HalfH * 1.1, 0, 0,  False);
      CheckInside(F, 'inside top edge',    0,  HalfH * 0.9, 0, True);
      CheckInside(F, 'outside top edge',   0,  HalfH * 1.1, 0, False);
      CheckInside(F, 'inside bottom edge',  0, -HalfH * 0.9, 0, True);
      CheckInside(F, 'outside bottom edge', 0, -HalfH * 1.1, 0, False);
      Writeln;

      // Aspect 2 doubles the horizontal extent but leaves the vertical alone.
      Writeln('--- GetFrustumPlanesForAspect(2.0), wide viewport ---');
      F := Cam.GetFrustumPlanesForAspect(2.0);
      CheckNormalised(F, 'normalisation');
      CheckInside(F, 'x at 1.5x halfH',  HalfH * 1.5, 0, 0, True);   // now on screen
      CheckInside(F, 'x at 2.5x halfH',  HalfH * 2.5, 0, 0, False);  // still off screen
      CheckInside(F, 'y at 1.1x halfH',  0, HalfH * 1.1, 0, False);  // vertical unchanged
      Writeln;

      Writeln('--- GetFrustumPlanes (camera aspect 1.0) ---');
      F := Cam.GetFrustumPlanes;
      CheckNormalised(F, 'normalisation');
      CheckInside(F, 'origin',            0, 0, 0,  True);
      CheckInside(F, 'behind camera',     0, 0, 50, False);
      Writeln;

      // With a sane near/far ratio the far plane is well conditioned, which
      // confirms the wide tolerance above is float32 precision and not a
      // mistake in the extraction.
      Writeln('--- well-conditioned depth range (near 0.1, far 100) ---');
      Cam.NearPlane := 0.1;
      Cam.FarPlane  := 100.0;
      F := Cam.GetFrustumPlanesForAspect(1.0);
      CheckNormalised(F, 'normalisation');
      CheckNear('origin -> near plane', Dist(F.Planes[FRUSTUM_PLANE_NEAR], 0, 0, 0), 4.9,  0.01);
      CheckNear('origin -> far plane',  Dist(F.Planes[FRUSTUM_PLANE_FAR],  0, 0, 0), 95.0, 0.05);
      CheckInside(F, 'origin',          0, 0,    0, True);
      CheckInside(F, 'just inside far', 0, 0,  -94, True);
      CheckInside(F, 'just beyond far', 0, 0,  -96, False);
      Writeln;

      Cam.NearPlane := 0.01;
      Cam.FarPlane  := 1000.0;

      Writeln('--- orthographic projection ---');
      Cam.SetOrthographic(-10, 10, 10, -10, 0.1, 100);
      F := Cam.GetFrustumPlanesForAspect(1.0);
      CheckNormalised(F, 'normalisation');
      CheckInside(F, 'origin',            0,   0,  0,   True);
      CheckInside(F, 'inside box edge',   9,   0,  0,   True);
      CheckInside(F, 'outside box edge',  11,  0,  0,   False);
      CheckInside(F, 'behind camera',     0,   0,  50,  False);
      CheckInside(F, 'beyond far plane',  0,   0, -200, False);
      Writeln;

    finally
      Cam.Free;
    end;

    if Failures = 0 then
      Writeln('ALL CHECKS PASSED')
    else
      Writeln(Format('%d CHECK(S) FAILED', [Failures]));

  except
    on E: Exception do
    begin
      Writeln('EXCEPTION: ', E.ClassName, ': ', E.Message);
      ExitCode := 2;
      Exit;
    end;
  end;

  if Failures > 0 then
    ExitCode := 1;
end.
