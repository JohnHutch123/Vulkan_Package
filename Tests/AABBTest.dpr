program AABBTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Math,
  PasVulkan.Math,
  Vulkan_Components_Camera;

var
  Failures : Integer = 0;

procedure Check(const Name: string; Got, Expect: Boolean);
begin
  if Got = Expect then
    Writeln(Format('  ok   %-34s %s', [Name, BoolToStr(Got, True)]))
  else
  begin
    Writeln(Format('  FAIL %-34s got %s expected %s',
      [Name, BoolToStr(Got, True), BoolToStr(Expect, True)]));
    Inc(Failures);
  end;
end;

procedure CheckVec(const Name: string; const Got, Expect: TpvVector3; Tol: Single);
begin
  if (Abs(Got.x - Expect.x) <= Tol) and
     (Abs(Got.y - Expect.y) <= Tol) and
     (Abs(Got.z - Expect.z) <= Tol) then
    Writeln(Format('  ok   %-34s (%.3f %.3f %.3f)', [Name, Got.x, Got.y, Got.z]))
  else
  begin
    Writeln(Format('  FAIL %-34s got (%.3f %.3f %.3f) expected (%.3f %.3f %.3f)',
      [Name, Got.x, Got.y, Got.z, Expect.x, Expect.y, Expect.z]));
    Inc(Failures);
  end;
end;

procedure CheckNum(const Name: string; Got, Expect, Tol: Single);
begin
  if Abs(Got - Expect) <= Tol then
    Writeln(Format('  ok   %-34s %.4f', [Name, Got]))
  else
  begin
    Writeln(Format('  FAIL %-34s got %.4f expected %.4f', [Name, Got, Expect]));
    Inc(Failures);
  end;
end;

function V(X, Y, Z: Single): TpvVector3;
begin
  Result := TpvVector3.Create(X, Y, Z);
end;

function BoxOf(MinX, MinY, MinZ, MaxX, MaxY, MaxZ: Single): TvgAABB;
begin
  Result.Reset;
  Result.SetBounds(V(MinX, MinY, MinZ), V(MaxX, MaxY, MaxZ));
end;

// ---------------------------------------------------------------------------
procedure TestAABBBasics;
var
  A, B, Z : TvgAABB;
  Raw     : array[0..63] of Byte;
begin
  Writeln('--- TvgAABB basics ---');

  // A zero-filled record must already read as an empty box.
  FillChar(Raw, SizeOf(Raw), 0);
  Move(Raw, Z, SizeOf(Z));
  Check('zero-filled record is invalid', Z.Valid, False);

  A.Reset;
  Check('Reset gives invalid', A.Valid, False);
  CheckNum('empty Radius', A.Radius, 0.0, 1e-6);

  A.GrowPoint(V(1, 2, 3));
  Check('first point validates', A.Valid, True);
  CheckVec('single-point Min', A.Min, V(1, 2, 3), 1e-6);
  CheckVec('single-point Max', A.Max, V(1, 2, 3), 1e-6);
  CheckNum('single-point Radius', A.Radius, 0.0, 1e-6);

  A.GrowPoint(-1, -2, -3);
  CheckVec('grown Min', A.Min, V(-1, -2, -3), 1e-6);
  CheckVec('grown Max', A.Max, V(1, 2, 3), 1e-6);
  CheckVec('Centre', A.Centre, V(0, 0, 0), 1e-6);
  CheckVec('Extents (half size)', A.Extents, V(1, 2, 3), 1e-6);
  CheckVec('Size', A.Size, V(2, 4, 6), 1e-6);
  CheckNum('Radius', A.Radius, Sqrt(1 + 4 + 9), 1e-5);

  // Growing by an empty box must not drag the box to the origin.
  B.Reset;
  A.GrowAABB(B);
  CheckVec('grow by empty leaves Min', A.Min, V(-1, -2, -3), 1e-6);
  CheckVec('grow by empty leaves Max', A.Max, V(1, 2, 3), 1e-6);

  // Growing an empty box by a real one adopts it wholesale.
  B.Reset;
  B.GrowAABB(A);
  Check('empty grown by real is valid', B.Valid, True);
  CheckVec('adopted Min', B.Min, V(-1, -2, -3), 1e-6);

  B := BoxOf(5, 5, 5, 6, 6, 6);
  A.GrowAABB(B);
  CheckVec('union Min', A.Min, V(-1, -2, -3), 1e-6);
  CheckVec('union Max', A.Max, V(6, 6, 6), 1e-6);

  // SetBounds must order its corners.
  A.Reset;
  A.SetBounds(V(10, 10, 10), V(-10, -10, -10));
  CheckVec('SetBounds orders Min', A.Min, V(-10, -10, -10), 1e-6);
  CheckVec('SetBounds orders Max', A.Max, V(10, 10, 10), 1e-6);
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestTransform;
var
  A, T : TvgAABB;
  M    : TpvMatrix4x4;
  S    : Single;
begin
  Writeln('--- TvgAABB.Transform ---');

  // Empty stays empty.
  A.Reset;
  T := A.Transform(TpvMatrix4x4.Identity);
  Check('empty transforms to empty', T.Valid, False);

  A := BoxOf(-1, -1, -1, 1, 1, 1);

  T := A.Transform(TpvMatrix4x4.Identity);
  CheckVec('identity Min', T.Min, V(-1, -1, -1), 1e-5);
  CheckVec('identity Max', T.Max, V(1, 1, 1), 1e-5);

  // Pure translation must move the box and not resize it.
  M := TpvMatrix4x4.CreateTranslation(10, 20, 30);
  T := A.Transform(M);
  CheckVec('translated Centre', T.Centre, V(10, 20, 30), 1e-4);
  CheckVec('translated Extents', T.Extents, V(1, 1, 1), 1e-4);

  // Uniform scale.
  M := TpvMatrix4x4.CreateScale(2, 3, 4);
  T := A.Transform(M);
  CheckVec('scaled Centre', T.Centre, V(0, 0, 0), 1e-4);
  CheckVec('scaled Extents', T.Extents, V(2, 3, 4), 1e-4);

  // 45 degrees about Z: the unit box's enclosing AABB grows to sqrt(2) in X
  // and Y and is unchanged in Z.  This is the Arvo bound, and it is exact for
  // this case.
  M := TpvMatrix4x4.CreateRotateZ(DegToRad(45));
  T := A.Transform(M);
  S := Sqrt(2.0);
  CheckVec('rot45Z Extents', T.Extents, V(S, S, 1), 1e-4);
  CheckVec('rot45Z Centre', T.Centre, V(0, 0, 0), 1e-4);

  // 90 degrees about Z maps the box onto itself.
  M := TpvMatrix4x4.CreateRotateZ(DegToRad(90));
  T := A.Transform(M);
  CheckVec('rot90Z Extents', T.Extents, V(1, 1, 1), 1e-4);

  // Rotation about an off-centre box must carry the centre round with it.
  A := BoxOf(9, -1, -1, 11, 1, 1);           // centre (10,0,0)
  M := TpvMatrix4x4.CreateRotateZ(DegToRad(90));
  T := A.Transform(M);
  CheckVec('off-centre rot90Z Centre', T.Centre, V(0, 10, 0), 1e-3);
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestFrustumCull;
var
  Cam   : TvgCamera;
  F     : TvgFrustrumPlanes;
  A     : TvgAABB;
  HalfH : Single;
begin
  Writeln('--- vgFrustumTestAABB ---');

  Cam := TvgCamera.Create;
  try
    // Eye 5 back on +Z looking at the origin; 45 deg FOV, square viewport.
    Cam.InitializeFromParameters(V(0, 0, 5), V(0, 0, 0), V(0, 1, 0),
                                 45.0, 0.1, 100.0, 1.0);
    F := Cam.GetFrustumPlanesForAspect(1.0);

    HalfH := 5.0 * Tan(DegToRad(45.0) / 2);   // ~2.071 at the origin

    // No bounds -> must be drawn.
    A.Reset;
    Check('empty box is kept', vgFrustumTestAABB(F, A), True);

    A := BoxOf(-0.5, -0.5, -0.5, 0.5, 0.5, 0.5);
    Check('box at origin', vgFrustumTestAABB(F, A), True);

    A := BoxOf(-0.5, -0.5, 49.5, 0.5, 0.5, 50.5);
    Check('box behind the camera', vgFrustumTestAABB(F, A), False);

    A := BoxOf(-0.5, -0.5, -200.5, 0.5, 0.5, -199.5);
    Check('box beyond the far plane', vgFrustumTestAABB(F, A), False);

    A := BoxOf(100, -0.5, -0.5, 101, 0.5, 0.5);
    Check('box far off to the right', vgFrustumTestAABB(F, A), False);

    A := BoxOf(-101, -0.5, -0.5, -100, 0.5, 0.5);
    Check('box far off to the left', vgFrustumTestAABB(F, A), False);

    A := BoxOf(-0.5, 100, -0.5, 0.5, 101, 0.5);
    Check('box far above', vgFrustumTestAABB(F, A), False);

    A := BoxOf(-0.5, -101, -0.5, 0.5, -100, 0.5);
    Check('box far below', vgFrustumTestAABB(F, A), False);

    // THE case that matters: a box whose CENTRE is outside the frustum but
    // which still pokes into view.  A centre-only test would wrongly cull it;
    // the extent term is what saves it.
    A.Reset;
    A.SetBounds(V(HalfH * 0.9, -0.5, -0.5), V(HalfH * 3.0, 0.5, 0.5));
    Check('centre outside, box overlaps', vgFrustumTestAABB(F, A), True);

    // A huge box enclosing the whole frustum must be kept.
    A := BoxOf(-1000, -1000, -1000, 1000, 1000, 1000);
    Check('box enclosing the frustum', vgFrustumTestAABB(F, A), True);

    // A box straddling the near plane.
    A := BoxOf(-0.5, -0.5, 4.8, 0.5, 0.5, 5.2);
    Check('box straddling the near plane', vgFrustumTestAABB(F, A), True);

    // Rotating the camera away must cull what was previously in view.
    A := BoxOf(-0.5, -0.5, -0.5, 0.5, 0.5, 0.5);
    Cam.LookAt(V(0, 0, 5), V(0, 0, 50), V(0, 1, 0));   // look away
    F := Cam.GetFrustumPlanesForAspect(1.0);
    Check('origin after looking away', vgFrustumTestAABB(F, A), False);

    Cam.LookAt(V(0, 0, 5), V(0, 0, 0), V(0, 1, 0));    // look back
    F := Cam.GetFrustumPlanesForAspect(1.0);
    Check('origin after looking back', vgFrustumTestAABB(F, A), True);

    // Culling must follow an instance transform: the same local box pushed
    // off to the side by its matrix has to drop out of view.
    Cam.LookAt(V(0, 0, 5), V(0, 0, 0), V(0, 1, 0));
    F := Cam.GetFrustumPlanesForAspect(1.0);
    A := BoxOf(-0.5, -0.5, -0.5, 0.5, 0.5, 0.5);
    Check('local box, identity instance',
      vgFrustumTestAABB(F, A.Transform(TpvMatrix4x4.Identity)), True);
    Check('local box, instance moved aside',
      vgFrustumTestAABB(F, A.Transform(TpvMatrix4x4.CreateTranslation(200, 0, 0))), False);
    Check('local box, instance moved slightly',
      vgFrustumTestAABB(F, A.Transform(TpvMatrix4x4.CreateTranslation(0.5, 0, 0))), True);
  finally
    Cam.Free;
  end;
  Writeln;
end;

begin
  try
    TestAABBBasics;
    TestTransform;
    TestFrustumCull;

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
