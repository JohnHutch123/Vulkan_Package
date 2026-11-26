program FirstPersonTest;

{$APPTYPE CONSOLE}

{ TvgFirstPersonController without a window or GPU: a fake host supplies the
  camera and counts redraw requests.

  - held keys move the camera along the view, at Speed x seconds
  - diagonals are no faster; Shift runs, Ctrl slows; opposite keys cancel
  - automatic speed follows the size of the data
  - mouse look turns the right way, InvertY flips it
  - the wheel scales the speed
  - key-up finishes the step; ReleaseAll stops everything
  - the real tick thread moves the camera while a key is held, and stops

  Walking (nmWalk) and TvgMeshGround:
  - the ground under a point: floors, bridges, slopes, walls skipped, survey
    coordinates, Y up, and a 5000-triangle grid against the exact plane
  - walk keeps the eye EyeHeight over the ground, horizontal whatever the
    pitch; ramps are followed, steep slopes and tall steps refused, stairs
    climbed, edges stop (or float); under a bridge stays under it
  - the eye height is smoothed while moving and settles on key-up
  - TvgToolManager walks on the scene's own triangles, and follows an edit }

uses
  System.SysUtils,
  System.Classes,
  System.Math,
  System.Diagnostics,
  PasVulkan.Math,
  PasVulkan.Math.Double,
  Vulkan_WorldAxes,
  Vulkan_Components_Camera,
  Vulkan_Components_Lookups,
  Vulkan_Components,
  Vulkan_Components_DataStore,
  Vulkan_Components_Scene_Renderer,
  Vulkan_FirstPerson,
  Vulkan_MeshGround;

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

procedure CheckVec(const Name: string; const Got, Expect: TpvVector3D; Tol: Double);
begin
  if (Abs(Got.x - Expect.x) <= Tol) and
     (Abs(Got.y - Expect.y) <= Tol) and
     (Abs(Got.z - Expect.z) <= Tol) then
    Writeln(Format('  ok   %-56s (%.6f %.6f %.6f)', [Name, Got.x, Got.y, Got.z]))
  else
  begin
    Writeln(Format('  FAIL %-56s got (%.9f %.9f %.9f) expected (%.9f %.9f %.9f)',
      [Name, Got.x, Got.y, Got.z, Expect.x, Expect.y, Expect.z]));
    Inc(Failures);
  end;
end;

function V(X, Y, Z: Double): TpvVector3D;
begin
  Result := TpvVector3D.Create(X, Y, Z);
end;

type
  TFakeHost = class(TInterfacedObject, IvgFirstPersonHost)
    Cam    : TvgCamera;
    Size   : Double;
    Moves  : Integer;
    Ground : IvgGroundProvider;
    function  FirstPersonCamera: TvgCamera;
    function  FirstPersonSceneSize: Double;
    function  FirstPersonGround: IvgGroundProvider;
    procedure FirstPersonMoved;
  end;

  TBlockCounter = class
    Count : Integer;
    procedure Blocked(Sender: TObject);
  end;

procedure TBlockCounter.Blocked(Sender: TObject);
begin
  Inc(Count);
end;

function TFakeHost.FirstPersonGround: IvgGroundProvider;
begin
  Result := Ground;
end;

function TFakeHost.FirstPersonCamera: TvgCamera;
begin
  Result := Cam;
end;

function TFakeHost.FirstPersonSceneSize: Double;
begin
  Result := Size;
end;

procedure TFakeHost.FirstPersonMoved;
begin
  Inc(Moves);
end;

var
  Host     : TFakeHost;
  HostIntf : IvgFirstPersonHost;   // keeps Host alive

// Z up, at (0,0,2) looking along +X.
procedure ResetCamera;
begin
  Host.Cam.InitializeFromParameters(V(0, 0, 2), V(10, 0, 2), V(0, 0, 1));
  Host.Moves := 0;
end;

function NewController: TvgFirstPersonController;
begin
  Result := TvgFirstPersonController.Create(HostIntf);
  Result.AutoTick := False;    // the tests drive Tick themselves
  Result.Speed    := 2.0;      // units per second
end;

// ---------------------------------------------------------------------------
procedure TestKeysAndSpeed;
var
  FP : TvgFirstPersonController;
  K  : TvgMoveKey;
begin
  Writeln('--- keys and speed ---');
  FP := NewController;
  try
    Check('W is a movement key', vgMoveKeyOf(VGK_W, K) and (K = mkForward), True);
    Check('X is not', vgMoveKeyOf(Ord('X'), K), False);

    ResetCamera;
    Check('KeyDown(W) used', FP.KeyDown(VGK_W, []), True);
    FP.Tick(0.2);
    CheckVec('W for 0.2 s at 2/s: 0.4 forward', Host.Cam.Position, V(0.4, 0, 2), 1e-12);
    CheckVec('...the target moves with it', Host.Cam.Target, V(10.4, 0, 2), 1e-12);
    Check('...the host was told', Host.Moves = 1, True);

    FP.KeyDown(VGK_D, []);
    FP.Tick(0.2);
    CheckNum('W+D diagonal: still 0.4 in 0.2 s',
      (Host.Cam.Position - V(0.4, 0, 2)).Length, 0.4, 1e-12);
    Check('...and to the right (-Y with Z up, looking +X)', Host.Cam.Position.y < 0, True);
    FP.ReleaseAll;

    ResetCamera;
    FP.KeyDown(VGK_W, []);
    FP.KeyDown(VGK_S, []);
    FP.Tick(0.2);
    CheckVec('W+S cancel', Host.Cam.Position, V(0, 0, 2), 0);
    Check('...and nothing is redrawn', Host.Moves = 0, True);
    FP.ReleaseAll;

    ResetCamera;
    FP.KeyDown(VGK_E, []);
    FP.Tick(0.2);
    CheckVec('E: up along world up', Host.Cam.Position, V(0, 0, 2.4), 1e-12);
    FP.ReleaseAll;

    ResetCamera;
    Check('Shift key itself is not "used"', FP.KeyDown(VGK_SHIFT, [ssShift]), False);
    FP.KeyDown(VGK_W, [ssShift]);
    FP.Tick(0.2);
    CheckNum('Shift: run x4', Host.Cam.Position.x, 1.6, 1e-12);
    FP.KeyUp(VGK_SHIFT, []);
    FP.KeyDown(VGK_W, [ssCtrl]);     // autorepeat, now with Ctrl
    FP.Tick(0.2);
    // 1e-3: the key-up finishes its step with the real (microseconds) time.
    CheckNum('Ctrl: slow x0.25 (Shift dropped)', Host.Cam.Position.x, 1.7, 1e-3);
    FP.ReleaseAll;
    Check('ReleaseAll clears every key', FP.Held = [], True);

    // Look up, then forward: fly climbs.
    ResetCamera;
    Host.Cam.Look(0, 30);
    FP.KeyDown(VGK_UP, []);
    FP.Tick(0.2);
    CheckNum('looking 30 up, forward climbs sin 30 x 0.4', Host.Cam.Position.z, 2 + 0.2, 1e-12);
    FP.ReleaseAll;

    // A stall is clamped.
    ResetCamera;
    FP.KeyDown(VGK_W, []);
    FP.Tick(5.0);
    CheckNum('a 5 s stall moves only 0.25 s worth', Host.Cam.Position.x, 0.5, 1e-12);
    FP.ReleaseAll;
  finally
    FP.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestAutoSpeedAndWheel;
var
  FP : TvgFirstPersonController;
begin
  Writeln('--- automatic speed, wheel ---');
  FP := NewController;
  try
    FP.Speed  := 0;
    Host.Size := 0;
    CheckNum('auto, size unknown: 1 unit/s', FP.EffectiveSpeed, 1.0, 1e-12);
    Host.Size := 2000;
    CheckNum('auto, 2 km of data: 100 units/s (20 s across)', FP.EffectiveSpeed, 100, 1e-9);
    FP.Wheel(120);
    CheckNum('one wheel notch: x1.25', FP.EffectiveSpeed, 125, 1e-9);
    FP.Wheel(-240);
    CheckNum('two back: x1.25^-1', FP.EffectiveSpeed, 80, 1e-9);
    FP.Speed := 3;
    CheckNum('a set Speed is used as is (times the wheel)', FP.EffectiveSpeed, 3 * 0.8, 1e-9);
  finally
    FP.Free;
    Host.Size := 0;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestLook;
var
  FP : TvgFirstPersonController;
begin
  Writeln('--- mouse look ---');
  FP := NewController;
  try
    ResetCamera;
    FP.Look(90, 0);     // drag right
    CheckVec('drag right turns right (+X to -Y)', Host.Cam.ForwardVector, V(0, -1, 0), 1e-12);
    CheckVec('...the eye stays', Host.Cam.Position, V(0, 0, 2), 0);

    ResetCamera;
    FP.Look(0, -20);    // drag up
    Check('drag up looks up', Host.Cam.ForwardVector.z > 0, True);

    ResetCamera;
    FP.InvertY := True;
    FP.Look(0, -20);
    Check('InvertY: drag up looks down', Host.Cam.ForwardVector.z < 0, True);
    FP.InvertY := False;

    ResetCamera;
    FP.MoveForward(3);
    CheckVec('MoveForward(3)', Host.Cam.Position, V(3, 0, 2), 1e-12);
  finally
    FP.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestKeyUpFinishesStep;
var
  FP : TvgFirstPersonController;
  SW : TStopwatch;
begin
  Writeln('--- key-up finishes the step ---');
  FP := NewController;
  try
    ResetCamera;
    FP.Speed := 10;
    FP.KeyDown(VGK_W, []);
    SW := TStopwatch.StartNew;
    Sleep(50);
    FP.KeyUp(VGK_W, []);
    // Between 50 ms and whatever the sleep really took, at 10/s.
    Check('a 50 ms tap moves about 0.5', InRange(Host.Cam.Position.x, 0.45,
      SW.Elapsed.TotalSeconds * 10 + 1e-6), True);
    Check('KeyUp of an unheld W is still a movement key', FP.KeyUp(VGK_W, []), True);
    Check('nothing held after', FP.Held = [], True);
  finally
    FP.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestTickThread;
var
  FP     : TvgFirstPersonController;
  SW     : TStopwatch;
  X1, X2 : Double;
  M      : Integer;
begin
  Writeln('--- tick thread ---');
  FP := TvgFirstPersonController.Create(HostIntf);
  try
    FP.Speed := 1.0;
    ResetCamera;
    FP.KeyDown(VGK_W, []);

    // The ticks arrive through TThread.Queue: pump them as a message loop would.
    SW := TStopwatch.StartNew;
    while SW.ElapsedMilliseconds < 300 do
    begin
      CheckSynchronize(5);
    end;
    X1 := Host.Cam.Position.x;
    M  := Host.Moves;
    Check(Format('ticks arrived while held (%d)', [M]), M >= 5, True);
    Check('...and moved about 0.3', InRange(X1, 0.15, 0.4), True);

    FP.KeyUp(VGK_W, []);
    X1 := Host.Cam.Position.x;
    SW := TStopwatch.StartNew;
    while SW.ElapsedMilliseconds < 150 do
      CheckSynchronize(5);
    X2 := Host.Cam.Position.x;
    CheckNum('released: no further movement', X2 - X1, 0, 0);
  finally
    FP.Free;      // ends the thread; must not hang or crash
  end;
  // A tick queued just before the free must not run on the freed controller.
  CheckSynchronize(20);
  Check('freed cleanly', True, True);
  Writeln;
end;

// ---------------------------------------------------------------------------
//  Ground
// ---------------------------------------------------------------------------

// A rectangle x0..x1, y0..y1 (Z up) as two triangles, its height running
// linearly from h0 at x0 to h1 at x1.
procedure AddRect(G: TvgMeshGround; x0, y0, x1, y1, h0, h1: Double);
begin
  G.AddTriangle(V(x0, y0, h0), V(x1, y0, h1), V(x1, y1, h1));
  G.AddTriangle(V(x0, y0, h0), V(x1, y1, h1), V(x0, y1, h0));
end;

procedure TestMeshGround;
var
  G      : TvgMeshGround;
  GI     : IvgGroundProvider;
  P, N   : TpvVector3D;
  I, J   : Integer;
  X, Y   : Double;
  Worst  : Double;
  Base   : TpvVector3D;
  Missed : Integer;
begin
  Writeln('--- mesh ground ---');

  G := TvgMeshGround.Create(V(0, 0, 1)); GI := G;
  AddRect(G, -10, -10, 10, 10, 0, 0);
  Check('flat: hit below', GI.GroundAt(V(1, 2, 5), 5, P, N), True);
  CheckVec('...at the point, on the surface', P, V(1, 2, 0), 1e-12);
  CheckVec('...normal up', N, V(0, 0, 1), 1e-12);
  Check('outside the footprint: no hit', GI.GroundAt(V(20, 0, 5), 5, P, N), False);
  Check('limit below the surface: no hit', GI.GroundAt(V(1, 2, 5), -1, P, N), False);
  Check('on a shared edge: hit', GI.GroundAt(V(0, 0, 5), 5, P, N), True);
  Check('on the outer corner: hit', GI.GroundAt(V(10, 10, 5), 5, P, N), True);

  // A deck at 3 over part of the floor.
  AddRect(G, -2, -10, 2, 10, 3, 3);
  GI.GroundAt(V(0, 0, 10), 10, P, N);
  CheckNum('two levels, limit 10: the deck', P.z, 3, 1e-12);
  GI.GroundAt(V(0, 0, 10), 1, P, N);
  CheckNum('...limit 1: the floor under it', P.z, 0, 1e-12);
  // A wall: no footprint, never ground.
  G.AddTriangle(V(5, -1, 0), V(5, 1, 0), V(5, 0, 9));
  GI.GroundAt(V(5, 0, 20), 20, P, N);
  CheckNum('a vertical wall is skipped', P.z, 0, 1e-12);

  // A slope z = 0.5 x.
  G := TvgMeshGround.Create(V(0, 0, 1)); GI := G;
  AddRect(G, 0, -5, 10, 5, 0, 5);
  GI.GroundAt(V(4, 1, 99), 99, P, N);
  CheckNum('slope: height interpolated', P.z, 2, 1e-12);
  CheckVec('...normal leans back', N, V(-0.5, 0, 1).Normalize, 1e-12);

  // Survey coordinates: exact in double.
  Base := V(512345.678, 6123456.789, 100.25);
  G := TvgMeshGround.Create(V(0, 0, 1)); GI := G;
  AddRect(G, Base.x - 50, Base.y - 50, Base.x + 50, Base.y + 50, Base.z, Base.z + 10);
  GI.GroundAt(Base + V(0.001, 0, 50), 1e6, P, N);
  CheckNum('survey coords: height at the middle (+1 mm)', P.z, Base.z + 5 + 0.0001, 1e-9);

  // Y up.
  G := TvgMeshGround.Create(V(0, 1, 0)); GI := G;
  G.AddTriangle(V(-5, 2, -5), V(5, 2, -5), V(5, 2, 5));
  G.AddTriangle(V(-5, 2, -5), V(5, 2, 5), V(-5, 2, 5));
  CheckVec('Y up: GroundUp', GI.GroundUp, V(0, 1, 0), 0);
  Check('Y up: hit', GI.GroundAt(V(1, 9, 1), 9, P, N), True);
  CheckVec('...on the y = 2 floor', P, V(1, 2, 1), 1e-12);

  // A 50 x 50 grid of quads (5000 triangles) on z = 0.3x - 0.2y + 5, through
  // AddMesh: every query must match the plane - the cells must hold every
  // triangle that touches them.
  G := TvgMeshGround.Create(V(0, 0, 1)); GI := G;
  for J := 0 to 49 do
    for I := 0 to 49 do
    begin
      X := I * 2; Y := J * 2;
      G.AddMesh([V(X, Y, 0.3 * X - 0.2 * Y + 5),         V(X + 2, Y, 0.3 * (X + 2) - 0.2 * Y + 5),
                 V(X + 2, Y + 2, 0.3 * (X + 2) - 0.2 * (Y + 2) + 5), V(X, Y + 2, 0.3 * X - 0.2 * (Y + 2) + 5)],
                [0, 1, 2, 0, 2, 3]);
    end;
  CheckNum('grid: 5000 triangles', G.TriangleCount, 5000, 0);
  RandSeed := 1234;
  Worst := 0; Missed := 0;
  for I := 1 to 2000 do
  begin
    X := Random * 100; Y := Random * 100;
    if GI.GroundAt(V(X, Y, 100), 100, P, N) then
      Worst := Max(Worst, Abs(P.z - (0.3 * X - 0.2 * Y + 5)))
    else
      Inc(Missed);
  end;
  CheckNum('...2000 random points all found', Missed, 0, 0);
  CheckNum('...worst height error', Worst, 0, 1e-9);
  Check(Format('...grid used (%d x %d cells)', [G.CellsU, G.CellsV]), (G.CellsU > 10) and (G.CellsV > 10), True);
  Writeln;
end;

// ---------------------------------------------------------------------------
//  Walking
// ---------------------------------------------------------------------------

function NewGround: TvgMeshGround;
begin
  Result      := TvgMeshGround.Create(V(0, 0, 1));
  Host.Ground := Result;
end;

// Camera at (x, 0, z) looking along +X, Z up, walking.
function Walker(x, z: Double): TvgFirstPersonController;
begin
  Host.Cam.InitializeFromParameters(V(x, 0, z), V(x + 10, 0, z), V(0, 0, 1));
  Host.Moves := 0;
  Result := NewController;
  Result.HeightSmoothing := 0;      // exact heights unless a test wants it
  Result.Mode := nmWalk;
end;

procedure TestWalk;
var
  FP : TvgFirstPersonController;
  G  : TvgMeshGround;
  BC : TBlockCounter;
  I  : Integer;
begin
  Writeln('--- walking ---');
  BC := TBlockCounter.Create;
  try
    // Flat floor.
    G := NewGround;
    AddRect(G, -50, -50, 50, 50, 0, 0);
    FP := Walker(0, 10);
    try
      CheckVec('nmWalk drops the eye onto the floor + 1.7', Host.Cam.Position, V(0, 0, 1.7), 1e-12);
      Check('...grounded', FP.Grounded, True);
      CheckVec('...still looking ahead', Host.Cam.ForwardVector, V(1, 0, 0), 1e-12);
      FP.KeyDown(VGK_W, []);
      FP.Tick(0.2);
      CheckVec('W 0.2 s: 0.4 along the floor', Host.Cam.Position, V(0.4, 0, 1.7), 1e-12);
      Host.Cam.Look(0, -60);
      FP.Tick(0.2);
      CheckVec('looking 60 down, W still walks level', Host.Cam.Position, V(0.8, 0, 1.7), 1e-12);
      FP.KeyDown(VGK_E, []);
      FP.Tick(0.2);
      CheckNum('E does not climb', Host.Cam.Position.z, 1.7, 1e-12);
      FP.ReleaseAll;
      FP.Speed := 0;
      CheckNum('auto walking speed: 0.8 x EyeHeight', FP.EffectiveSpeed, 1.36, 1e-12);
    finally
      FP.Free;
    end;

    // A 14 degree ramp up from x = 0.
    G := NewGround;
    AddRect(G, -50, -50, 0, 50, 0, 0);
    AddRect(G, 0, -50, 20, 50, 0, 5);
    FP := Walker(-0.1, 1.7);
    try
      FP.KeyDown(VGK_W, []);
      for I := 1 to 5 do FP.Tick(0.2);
      CheckVec('up a 14 degree ramp: eye 1.7 over it', Host.Cam.Position, V(1.9, 0, 0.25 * 1.9 + 1.7), 1e-12);
      FP.ReleaseAll;
    finally
      FP.Free;
    end;

    // A 63 degree slope: refused, even in steps far below StepHeight.
    G := NewGround;
    AddRect(G, -50, -50, 0, 50, 0, 0);
    AddRect(G, 0, -50, 5, 50, 0, 10);
    FP := Walker(-0.01, 1.7);
    try
      FP.OnBlocked := BC.Blocked;
      BC.Count := 0;
      FP.KeyDown(VGK_W, []);
      FP.Tick(0.01);
      CheckNum('steep slope: the step is refused', Host.Cam.Position.x, -0.01, 1e-12);
      Check('...OnBlocked fired', BC.Count = 1, True);
      FP.ReleaseAll;
    finally
      FP.Free;
    end;

    // Stairs: 0.3 is a step, a further 0.5 is not.
    G := NewGround;
    AddRect(G, -50, -50, 1, 50, 0, 0);
    AddRect(G, 1, -50, 2, 50, 0.3, 0.3);
    AddRect(G, 2, -50, 50, 50, 0.8, 0.8);
    FP := Walker(0.9, 1.7);
    try
      FP.OnBlocked := BC.Blocked;
      BC.Count := 0;
      FP.KeyDown(VGK_W, []);
      FP.Tick(0.1);
      CheckVec('a 0.3 step is climbed', Host.Cam.Position, V(1.1, 0, 2.0), 1e-12);
      Host.Cam.Translate(V(0.8, 0, 0));    // to x = 1.9, on the 0.3 tread
      FP.Tick(0.1);
      CheckNum('a 0.5 step is refused', Host.Cam.Position.x, 1.9, 1e-12);
      Check('...OnBlocked fired', BC.Count = 1, True);
      FP.ReleaseAll;
    finally
      FP.Free;
    end;

    // The edge of the ground.
    G := NewGround;
    AddRect(G, -5, -5, 5, 5, 0, 0);
    FP := Walker(4.9, 1.7);
    try
      FP.KeyDown(VGK_W, []);
      FP.Tick(0.1);
      CheckNum('edge, ebStop: the step off is refused', Host.Cam.Position.x, 4.9, 1e-12);
      FP.EdgeBehaviour := ebFloat;
      FP.Tick(0.1);
      CheckVec('edge, ebFloat: on at the same height', Host.Cam.Position, V(5.1, 0, 1.7), 1e-12);
      Check('...not grounded', FP.Grounded, False);
      FP.Speed := 2;
      Host.Cam.Translate(V(-1, 0, 0));     // back over the ground at x = 4.1
      FP.Tick(0.1);
      Check('...back over it: grounded again', FP.Grounded, True);
      FP.ReleaseAll;
    finally
      FP.Free;
    end;

    // A bridge deck at 3 over x 5..6: walking along the floor goes under it;
    // starting on it stays on it.
    G := NewGround;
    AddRect(G, -50, -50, 50, 50, 0, 0);
    AddRect(G, 5, -50, 6, 50, 3, 3);
    FP := Walker(4.9, 1.7);
    try
      FP.KeyDown(VGK_W, []);
      FP.Tick(0.1);
      CheckVec('under the bridge: still on the floor', Host.Cam.Position, V(5.1, 0, 1.7), 1e-12);
      FP.ReleaseAll;
    finally
      FP.Free;
    end;
    FP := Walker(5.5, 10);
    try
      CheckNum('dropped from above: onto the deck', Host.Cam.Position.z, 4.7, 1e-12);
    finally
      FP.Free;
    end;

    // Smoothing: the eye lags a step up, then settles on key-up.
    G := NewGround;
    AddRect(G, -50, -50, 1, 50, 0, 0);
    AddRect(G, 1, -50, 50, 50, 0.3, 0.3);
    FP := Walker(0.9, 1.7);
    try
      FP.HeightSmoothing := 0.1;
      FP.KeyDown(VGK_W, []);
      FP.Tick(0.1);
      CheckNum('smoothed: the eye lags the step (1 - e^-1)',
        Host.Cam.Position.z, 2.0 - 0.3 * Exp(-1), 1e-9);
      FP.KeyUp(VGK_W, []);
      CheckNum('...key-up settles it at 2.0', Host.Cam.Position.z, 2.0, 1e-12);
    finally
      FP.Free;
    end;

    // No ground at all: walking keeps the height.
    Host.Ground := nil;
    FP := Walker(0, 10);
    try
      CheckNum('no ground: the eye stays where it was', Host.Cam.Position.z, 10, 1e-12);
      Check('...not grounded', FP.Grounded, False);
      Host.Cam.Look(0, -30);
      FP.KeyDown(VGK_W, []);
      FP.Tick(0.2);
      CheckVec('...and W walks level', Host.Cam.Position, V(0.4, 0, 10), 1e-12);
      FP.ReleaseAll;
    finally
      FP.Free;
    end;
  finally
    BC.Free;
    Host.Ground := nil;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
//  The tool manager walking on a scene's own triangles
// ---------------------------------------------------------------------------

// World point from (right, forward, height) in the active axis convention.
function WP(aR, aF, aH: Double): TpvVector3D;
begin
  Result := vgWorldRight * aR + vgWorldForward * aF + vgWorldUp * aH;
end;

procedure TestToolManagerWalk;
var
  Scene : TvgScene;
  Store : TvgObjectStore;
  Obj   : TvgObject;
  Tools : TvgToolManager;
  Cam   : TvgCamera;
  Key   : Word;
  I     : Integer;
  Pts   : array[0..5] of TpvVector3D;
  GI    : IvgGroundProvider;
begin
  Writeln('--- tool manager: walking on the scene ---');
  Tools := TvgToolManager.Create(nil);
  Scene := TvgScene.Create(nil);
  try
    Tools.Scene := Scene;
    Cam := TvgCamera.Create;
    Cam.InitializeFromParameters(WP(0, 0, 10), WP(0, 10, 10), vgWorldUp);
    Scene.Cameras.AddCamera('main', Cam);
    Scene.Cameras.SetActiveCamera('main');

    if not Scene.Load_Begin then
      raise Exception.Create('scene would not enter loading state');
    Store := TvgObjectStore.Create(nil);
    Store.Topology := TRIANGLE_LIST;
    Store.SetupVertexAttributes([vdtPosition]);
    Scene.AddDataStore(Store);
    Obj := Store.AddObject(False);
    Obj.AllocateVertices(6);
    // A 40 x 40 floor at height 2, unindexed.
    Pts[0] := WP(-20, -20, 2); Pts[1] := WP(20, -20, 2); Pts[2] := WP(20, 20, 2);
    Pts[3] := WP(-20, -20, 2); Pts[4] := WP(20, 20, 2);  Pts[5] := WP(-20, 20, 2);
    for I := 0 to 5 do
    begin
      Obj.CurrentVertex := I;
      Obj.SetVertexWorldPosition(Pts[I]);
    end;
    Scene.Load_End;

    GI := Tools.BuildSceneGround;
    Check('BuildSceneGround finds the floor', Assigned(GI), True);
    GI := nil;

    Tools.FirstPerson.AutoTick        := False;
    Tools.FirstPerson.HeightSmoothing := 0;
    Tools.FirstPerson.Speed           := 2;
    Tools.NavigationMode := nmWalk;
    CheckNum('nmWalk: eye 1.7 over the scene floor', vgUpComponent(Cam.Position), 3.7, 1e-6);
    Check('...grounded', Tools.FirstPerson.Grounded, True);

    Key := VGK_W;
    Check('W reaches the walker through the tool manager', Tools.HandleKeyDown(Key, []), True);
    Tools.FirstPerson.Tick(0.5);
    CheckNum('...walked 0.25 s worth (clamped) forward', Cam.Position.Dot(vgWorldForward), 0.5, 1e-6);

    // Raise the floor by 0.3 (within a step): the ground is rebuilt from the
    // edited data.
    Check('edit: raise the floor', Obj.Translate(vgWorldUp * 0.3), True);
    Tools.FirstPerson.Tick(0.1);
    CheckNum('...the walker follows it (eye 4.0)', vgUpComponent(Cam.Position), 4.0, 1e-6);

    Key := VGK_W;
    Tools.HandleKeyUp(Key, []);
    Tools.NavigationMode := nmOrbit;
    Check('nmOrbit: W is not a navigation key any more', Tools.HandleKeyDown(Key, []), False);
  finally
    Tools.Free;
    Scene.Free;
  end;
  Writeln;
end;

begin
  try
    Host          := TFakeHost.Create;
    HostIntf      := Host;
    Host.Cam      := TvgCamera.Create;
    try
      TestKeysAndSpeed;
      TestAutoSpeedAndWheel;
      TestLook;
      TestKeyUpFinishesStep;
      TestTickThread;
      TestMeshGround;
      TestWalk;
      TestToolManagerWalk;
    finally
      Host.Cam.Free;
      Host.Cam := nil;
      Host.Ground := nil;
      HostIntf := nil;
    end;

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
