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
  - the real tick thread moves the camera while a key is held, and stops }

uses
  System.SysUtils,
  System.Classes,
  System.Math,
  System.Diagnostics,
  PasVulkan.Math,
  PasVulkan.Math.Double,
  Vulkan_Components_Camera,
  Vulkan_Components_Lookups,
  Vulkan_FirstPerson;

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
    Cam   : TvgCamera;
    Size  : Double;
    Moves : Integer;
    function  FirstPersonCamera: TvgCamera;
    function  FirstPersonSceneSize: Double;
    procedure FirstPersonMoved;
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
    finally
      Host.Cam.Free;
      Host.Cam := nil;
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
