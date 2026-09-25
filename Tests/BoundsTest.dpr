program BoundsTest;

{$APPTYPE CONSOLE}

{ Exercises the per-object bounding boxes TvgVulkanDataStore maintains for
  frustum culling.  Nothing here touches Vulkan: the store accumulates bounds
  in its CPU arrays, so it can be driven without a device. }

uses
  System.SysUtils,
  System.Math,
  PasVulkan.Math,
  Vulkan_Components_Camera,
  Vulkan_Components_Descriptors,
  Vulkan_Components_DataStore;

var
  Failures : Integer = 0;

procedure Check(const Name: string; Got, Expect: Boolean);
begin
  if Got = Expect then
    Writeln(Format('  ok   %-38s %s', [Name, BoolToStr(Got, True)]))
  else
  begin
    Writeln(Format('  FAIL %-38s got %s expected %s',
      [Name, BoolToStr(Got, True), BoolToStr(Expect, True)]));
    Inc(Failures);
  end;
end;

procedure CheckVec(const Name: string; const Got, Expect: TpvVector3; Tol: Single);
begin
  if (Abs(Got.x - Expect.x) <= Tol) and
     (Abs(Got.y - Expect.y) <= Tol) and
     (Abs(Got.z - Expect.z) <= Tol) then
    Writeln(Format('  ok   %-38s (%.3f %.3f %.3f)', [Name, Got.x, Got.y, Got.z]))
  else
  begin
    Writeln(Format('  FAIL %-38s got (%.3f %.3f %.3f) expected (%.3f %.3f %.3f)',
      [Name, Got.x, Got.y, Got.z, Expect.x, Expect.y, Expect.z]));
    Inc(Failures);
  end;
end;

function V(X, Y, Z: Single): TpvVector3;
begin
  Result := TpvVector3.Create(X, Y, Z);
end;

{ Translation matrix in the shape SetObjectInstanceMatrix expects.
  TvgMatrix4x4S is RawComponents[column, row], so the translation lives in
  column 3 - which the M-names spell M41/M42/M43. }
function TranslationS(TX, TY, TZ: Single): TvgMatrix4x4S;
begin
  Result     := TvgMatrix4x4S.Identity;
  Result.M41 := TX;
  Result.M42 := TY;
  Result.M43 := TZ;
end;

// ---------------------------------------------------------------------------
procedure TestNonInstanced;
var
  DS  : TvgVulkanDataStore;
  Obj : Integer;
  B   : TvgAABB;
begin
  Writeln('--- non-instanced object ---');
  DS := TvgVulkanDataStore.Create(nil);
  try
    DS.SetupVertexAttributes([vdtPosition, vdtColor]);

    Obj := DS.AddDataObject(False);

    // A brand new object has no bounds, and must therefore be drawn.
    B := DS.GetObjectWorldBounds(Obj);
    Check('new object has no bounds', B.Valid, False);
    Check('no bounds means visible',
      vgFrustumTestAABB(Default(TvgFrustrumPlanes), B), True);
    Check('new object is cmAuto', DS.GetObjectCullMode(Obj) = cmAuto, True);

    DS.AllocateVertices(Obj, 3);

    // Still nothing written, so still no bounds.
    Check('allocated but unwritten has no bounds',
      DS.GetObjectWorldBounds(Obj).Valid, False);

    DS.SetObjectVertexPosition(Obj, 0, -1, -2, -3);
    DS.SetObjectVertexPosition(Obj, 1,  4,  5,  6);
    DS.SetObjectVertexPosition(Obj, 2,  0,  0,  0);

    B := DS.GetObjectLocalBounds(Obj);
    Check('local bounds valid', B.Valid, True);
    CheckVec('local Min', B.Min, V(-1, -2, -3), 1e-5);
    CheckVec('local Max', B.Max, V( 4,  5,  6), 1e-5);

    // With no instancing there is no model matrix in this draw path, so the
    // vertices are already world space and world bounds mirror local.
    B := DS.GetObjectWorldBounds(Obj);
    CheckVec('world Min mirrors local', B.Min, V(-1, -2, -3), 1e-5);
    CheckVec('world Max mirrors local', B.Max, V( 4,  5,  6), 1e-5);

    // A later write must extend the box.
    DS.SetObjectVertexPosition(Obj, 2, 100, 0, 0);
    B := DS.GetObjectWorldBounds(Obj);
    CheckVec('bounds grow on later write', B.Max, V(100, 5, 6), 1e-4);
  finally
    DS.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestInstanced;
var
  DS  : TvgVulkanDataStore;
  Obj : Integer;
  B   : TvgAABB;
begin
  Writeln('--- instanced object (idtMatrix) ---');
  DS := TvgVulkanDataStore.Create(nil);
  try
    DS.SetupVertexAttributes([vdtPosition]);
    DS.SetupInstanceAttributes([idtMatrix]);

    Obj := DS.AddDataObject(True);
    DS.AllocateVertices(Obj, 2);
    DS.SetObjectVertexPosition(Obj, 0, -1, -1, -1);
    DS.SetObjectVertexPosition(Obj, 1,  1,  1,  1);

    DS.AllocateInstances(Obj, 3);
    DS.SetObjectInstanceMatrix(Obj, 0, TranslationS(  0, 0, 0));
    DS.SetObjectInstanceMatrix(Obj, 1, TranslationS( 10, 0, 0));
    DS.SetObjectInstanceMatrix(Obj, 2, TranslationS(  0, 0, -20));

    // Local bounds are the unit box regardless of where the instances put it.
    B := DS.GetObjectLocalBounds(Obj);
    CheckVec('local Min unaffected by instances', B.Min, V(-1, -1, -1), 1e-5);
    CheckVec('local Max unaffected by instances', B.Max, V( 1,  1,  1), 1e-5);

    // World bounds must be the union over all three placements.  This also
    // proves the raw reinterpretation of TvgMatrix4x4S as TpvMatrix4x4 in
    // GetInstanceMatrix reads the translation from the right place - if the
    // layout assumption were wrong, these would not move at all, or would
    // move along the wrong axis.
    B := DS.GetObjectWorldBounds(Obj);
    Check('world bounds valid', B.Valid, True);
    CheckVec('union Min', B.Min, V( -1, -1, -21), 1e-4);
    CheckVec('union Max', B.Max, V( 11,  1,   1), 1e-4);

    // Moving an instance must move the world bound.
    DS.SetObjectInstanceMatrix(Obj, 1, TranslationS(50, 0, 0));
    B := DS.GetObjectWorldBounds(Obj);
    CheckVec('union Max after moving instance', B.Max, V(51, 1, 1), 1e-4);

    // Widening the mesh must widen every instance's placement of it.  Only X
    // moves here (to -5), so X picks that up directly while Z stays at the
    // -20 instance's -1 + -20.
    DS.SetObjectVertexPosition(Obj, 0, -5, -1, -1);
    B := DS.GetObjectWorldBounds(Obj);
    CheckVec('union Min after widening mesh', B.Min, V(-5, -1, -21), 1e-4);

    // Deepening it in Z must push the -20 instance's contribution further out.
    DS.SetObjectVertexPosition(Obj, 0, -5, -1, -5);
    B := DS.GetObjectWorldBounds(Obj);
    CheckVec('union Min after deepening mesh', B.Min, V(-5, -1, -25), 1e-4);
  finally
    DS.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestCullModes;
var
  DS  : TvgVulkanDataStore;
  Obj : Integer;
  B   : TvgAABB;
begin
  Writeln('--- cull modes ---');
  DS := TvgVulkanDataStore.Create(nil);
  try
    DS.SetupVertexAttributes([vdtPosition]);

    Obj := DS.AddDataObject(False);
    DS.AllocateVertices(Obj, 2);
    DS.SetObjectVertexPosition(Obj, 0, -1, -1, -1);
    DS.SetObjectVertexPosition(Obj, 1,  1,  1,  1);

    DS.SetObjectCullMode(Obj, cmNever);
    Check('cull mode is cmNever', DS.GetObjectCullMode(Obj) = cmNever, True);

    // Supplying bounds selects cmManual, so they are actually used.
    DS.SetObjectBounds(Obj, V(-100, -100, -100), V(100, 100, 100));
    Check('SetObjectBounds selects cmManual',
      DS.GetObjectCullMode(Obj) = cmManual, True);

    B := DS.GetObjectWorldBounds(Obj);
    CheckVec('manual Min', B.Min, V(-100, -100, -100), 1e-4);
    CheckVec('manual Max', B.Max, V( 100,  100,  100), 1e-4);

    // THE point of cmManual: vertex writes must not overwrite what the
    // application supplied.  Geometry a compute shader owns would otherwise
    // have its bounds quietly replaced by stale CPU positions.
    DS.SetObjectVertexPosition(Obj, 0, -2, -2, -2);
    B := DS.GetObjectWorldBounds(Obj);
    CheckVec('manual Min survives a vertex write', B.Min, V(-100, -100, -100), 1e-4);
    CheckVec('manual Max survives a vertex write', B.Max, V( 100,  100,  100), 1e-4);

    // Local bounds still track the geometry underneath.
    B := DS.GetObjectLocalBounds(Obj);
    CheckVec('local still tracks vertices', B.Min, V(-2, -2, -2), 1e-4);

    // Going back to cmAuto hands the bounds back to the vertex data.
    DS.SetObjectCullMode(Obj, cmAuto);
    B := DS.GetObjectWorldBounds(Obj);
    CheckVec('cmAuto rebuilds from vertices Min', B.Min, V(-2, -2, -2), 1e-4);
    CheckVec('cmAuto rebuilds from vertices Max', B.Max, V( 1,  1,  1), 1e-4);

    // SetObjectBounds must order corners handed over the wrong way round.
    DS.SetObjectBounds(Obj, V(5, 5, 5), V(-5, -5, -5));
    B := DS.GetObjectWorldBounds(Obj);
    CheckVec('reversed corners ordered Min', B.Min, V(-5, -5, -5), 1e-4);
    CheckVec('reversed corners ordered Max', B.Max, V( 5,  5,  5), 1e-4);
  finally
    DS.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestIndependence;
var
  DS   : TvgVulkanDataStore;
  A, B : Integer;
  Box  : TvgAABB;
begin
  Writeln('--- objects share the vertex array, not their bounds ---');
  DS := TvgVulkanDataStore.Create(nil);
  try
    DS.SetupVertexAttributes([vdtPosition]);

    A := DS.AddDataObject(False);
    DS.AllocateVertices(A, 2);
    DS.SetObjectVertexPosition(A, 0, 0, 0, 0);
    DS.SetObjectVertexPosition(A, 1, 1, 1, 1);

    B := DS.AddDataObject(False);
    DS.AllocateVertices(B, 2);
    DS.SetObjectVertexPosition(B, 0, 100, 100, 100);
    DS.SetObjectVertexPosition(B, 1, 101, 101, 101);

    // Both objects live in one interleaved array; their boxes must not bleed
    // into each other, or a distant object would keep a nearby one on screen.
    Box := DS.GetObjectWorldBounds(A);
    CheckVec('object A Min', Box.Min, V(0, 0, 0), 1e-5);
    CheckVec('object A Max', Box.Max, V(1, 1, 1), 1e-5);

    Box := DS.GetObjectWorldBounds(B);
    CheckVec('object B Min', Box.Min, V(100, 100, 100), 1e-5);
    CheckVec('object B Max', Box.Max, V(101, 101, 101), 1e-5);
  finally
    DS.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestAgainstCamera;
var
  DS   : TvgVulkanDataStore;
  Cam  : TvgCamera;
  Near, Far_ : Integer;
  F    : TvgFrustrumPlanes;
begin
  Writeln('--- store bounds against a real camera frustum ---');
  DS  := TvgVulkanDataStore.Create(nil);
  Cam := TvgCamera.Create;
  try
    DS.SetupVertexAttributes([vdtPosition]);

    // One small object in front of the camera, one far off to the side.
    Near := DS.AddDataObject(False);
    DS.AllocateVertices(Near, 2);
    DS.SetObjectVertexPosition(Near, 0, -0.5, -0.5, -0.5);
    DS.SetObjectVertexPosition(Near, 1,  0.5,  0.5,  0.5);

    Far_ := DS.AddDataObject(False);
    DS.AllocateVertices(Far_, 2);
    DS.SetObjectVertexPosition(Far_, 0, 500, -0.5, -0.5);
    DS.SetObjectVertexPosition(Far_, 1, 501,  0.5,  0.5);

    Cam.InitializeFromParameters(V(0, 0, 5), V(0, 0, 0), V(0, 1, 0),
                                 45.0, 0.1, 100.0, 1.0);
    F := Cam.GetFrustumPlanesForAspect(1.0);

    Check('object in view is kept',
      vgFrustumTestAABB(F, DS.GetObjectWorldBounds(Near)), True);
    Check('object off to the side is culled',
      vgFrustumTestAABB(F, DS.GetObjectWorldBounds(Far_)), False);

    // cmNever exists so an object can opt out; its bounds say "cull me", and
    // the draw loop must consult the mode rather than the box alone.
    DS.SetObjectCullMode(Far_, cmNever);
    Check('opted-out object still reports cmNever',
      DS.GetObjectCullMode(Far_) = cmNever, True);
  finally
    Cam.Free;
    DS.Free;
  end;
  Writeln;
end;

begin
  try
    TestNonInstanced;
    TestInstanced;
    TestCullModes;
    TestIndependence;
    TestAgainstCamera;

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
