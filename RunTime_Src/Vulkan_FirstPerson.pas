unit Vulkan_FirstPerson;

{
  Vulkan_FirstPerson.pas

  First-person navigation: walk or fly the camera with the keyboard, and look
  round with the mouse - the view turns about the eye, not about a target.

  TvgFirstPersonController holds the held keys and the speed settings, and
  moves a camera on a timed tick while a movement key is down.  It knows no
  window, scene or renderer: everything it needs comes through
  IvgFirstPersonHost, which TvgToolManager implements.  That keeps it usable
  from anything that can supply a camera - a VR layer driving it from a
  thumbstick, say.

  The tick
    Rendering is on demand: nothing redraws unless asked.  So while a
    movement key is held a small thread wakes every TickInterval ms and
    queues one Tick onto the main thread (TThread.Queue), which moves the
    camera by Speed x elapsed time and asks the host to redraw.  It never
    queues a second tick while one is waiting, and it sleeps on an event
    while no key is held - an idle view costs nothing.

    TThread.Queue runs through the main thread's CheckSynchronize, which a
    VCL or FMX application calls in its message loop.  An application with a
    loop of its own sets AutoTick False and calls Tick itself.

  Keys (VGK_* codes - see Vulkan_Components_Lookups)
    W / Up      forward          S / Down    back
    A / Left    strafe left      D / Right   strafe right
    E / PgUp    up               Q / PgDn    down
    Shift       run (RunMultiplier)
    Ctrl        slow (SlowMultiplier)

  Fly moves along the view direction, so looking up and pressing forward
  climbs.  Up and down are along the camera's UpVector (world up).
}

interface

uses
  System.Classes,
  System.SysUtils,
  System.Math,
  System.SyncObjs,
  System.Diagnostics,
  PasVulkan.Math.Double,
  Vulkan_Components_Camera,
  Vulkan_Components_Lookups;

type
  // How TvgToolManager drives the camera.
  TvgNavigationMode = (
    nmOrbit,   // turn about the target, pan, dolly - the default
    nmFly      // first person: keys move, the mouse looks about the eye
  );

  TvgMoveKey  = (mkForward, mkBack, mkLeft, mkRight, mkUp, mkDown, mkRun, mkSlow);
  TvgMoveKeys = set of TvgMoveKey;

  // What a first-person controller needs from whoever owns it.
  IvgFirstPersonHost = interface
    ['{6C1F3E0A-4B7D-4A55-9F1E-2D8B7A3C9E51}']
    // The camera to move; nil for none (nothing moves).
    function  FirstPersonCamera: TvgCamera;
    // The size of the data in world units (the diagonal of its bounds), for
    // the automatic speed; 0 when unknown.
    function  FirstPersonSceneSize: Double;
    // The camera moved: redraw.
    procedure FirstPersonMoved;
  end;

  TvgFirstPersonController = class;

  TvgFirstPersonTicker = class(TThread)
  private
    fOwner   : TvgFirstPersonController;
    fWake    : TEvent;
    fRunning : Integer;   // 1 while ticks are wanted (TInterlocked)
    fQueued  : Integer;   // 1 while a tick waits on the main thread
  protected
    procedure Execute; override;
  public
    constructor Create(aOwner: TvgFirstPersonController);
    destructor  Destroy; override;
    procedure Start_;     // ticks wanted
    procedure Stop_;      // no more ticks
    procedure Shutdown;   // ends the thread; drops a queued tick
  end;

  TvgFirstPersonController = class(TPersistent)
  private
    fHost           : IvgFirstPersonHost;
    fHeld           : TvgMoveKeys;
    fSpeed          : Double;
    fRunMultiplier  : Double;
    fSlowMultiplier : Double;
    fSpeedScale     : Double;
    fLookSensitivity: Double;
    fInvertY        : Boolean;
    fAutoTick       : Boolean;
    fTickInterval   : Integer;
    fOnMoved        : TNotifyEvent;

    fTicker        : TvgFirstPersonTicker;
    fClock          : TStopwatch;
    fLastTick       : Int64;     // fClock ticks at the last move

    procedure SetTickInterval(const Value: Integer);
    procedure SetSpeedScale(const Value: Double);
    function  DirectionHeld: Boolean;
    procedure StartTicking;
    procedure StopTicking;
    // The ticker's queued call, on the main thread.
    procedure TimerTick;
    // Seconds since the last move, restarting the count.
    function  TakeElapsed: Double;
    // Tells the host, then OnMoved.
    procedure Moved;

  public
    constructor Create(const aHost: IvgFirstPersonHost);
    destructor  Destroy; override;
    procedure Assign(Source: TPersistent); override;

    { A key went down / up.  True when it is a movement key (W A S D Q E,
      arrows, Page Up/Down), so the window need not pass it on; Shift and
      Ctrl are tracked but return False. }
    function  KeyDown(aKey: Word; aShift: TShiftState): Boolean;
    function  KeyUp(aKey: Word; aShift: TShiftState): Boolean;

    // Forgets every held key and stops moving - focus lost, mode changed.
    procedure ReleaseAll;

    { A mouse-look drag of aDeltaX, aDeltaY, already scaled by the tool
      manager's MouseSensitivity (degrees, as Orbit takes them).  Dragging
      right turns the view right; dragging up looks up unless InvertY. }
    procedure Look(aDeltaX, aDeltaY: Double);

    { Moves the camera forward along its view by aDistance world units -
      for a dolly-button drag. }
    procedure MoveForward(aDistance: Double);

    // A wheel turn: each notch (120) scales the speed by 1.25.
    procedure Wheel(aWheelDelta: Integer);

    { Moves the camera for aSeconds with the keys held now, and tells the
      host.  Called by the internal tick; call it yourself with AutoTick
      False.  Clamped to 0.25 s so a stall does not throw the camera. }
    procedure Tick(aSeconds: Double);

    // Units per second at the moment, before Shift/Ctrl.
    function  EffectiveSpeed: Double;

    property  Held      : TvgMoveKeys read fHeld;
    // Wheel-adjusted multiplier on the speed, 1 at start.
    property  SpeedScale: Double read fSpeedScale write SetSpeedScale;

  published
    // World units per second.  0 (the default) is automatic: a twentieth of
    // the data's size, so crossing it takes about 20 s whatever its scale.
    property Speed           : Double  read fSpeed           write fSpeed;
    property RunMultiplier   : Double  read fRunMultiplier   write fRunMultiplier;
    property SlowMultiplier  : Double  read fSlowMultiplier  write fSlowMultiplier;
    // Multiplies mouse-look on top of the tool manager's MouseSensitivity.
    property LookSensitivity : Double  read fLookSensitivity write fLookSensitivity;
    property InvertY         : Boolean read fInvertY         write fInvertY default False;
    // False: no internal tick - call Tick from your own loop.
    property AutoTick        : Boolean read fAutoTick        write fAutoTick default True;
    // Milliseconds between ticks while moving.
    property TickInterval    : Integer read fTickInterval    write SetTickInterval default 16;
    // After each move or look this controller makes, on the main thread -
    // for a position readout.  Sender is the controller.
    property OnMoved         : TNotifyEvent read fOnMoved write fOnMoved;
  end;

  // VGK_* code -> movement key; False for any other key.
  function vgMoveKeyOf(aKey: Word; out aMove: TvgMoveKey): Boolean;

implementation

const
  MAX_TICK_SECONDS = 0.25;
  WHEEL_STEP       = 1.25;
  AUTO_SPEED_SPAN  = 20.0;     // seconds to cross the data at auto speed
  DEFAULT_SPEED    = 1.0;      // units/s when the size of the data is unknown

function vgMoveKeyOf(aKey: Word; out aMove: TvgMoveKey): Boolean;
begin
  Result := True;
  case aKey of
    VGK_W, VGK_UP    : aMove := mkForward;
    VGK_S, VGK_DOWN  : aMove := mkBack;
    VGK_A, VGK_LEFT  : aMove := mkLeft;
    VGK_D, VGK_RIGHT : aMove := mkRight;
    VGK_E, VGK_PRIOR : aMove := mkUp;
    VGK_Q, VGK_NEXT  : aMove := mkDown;
    VGK_SHIFT        : aMove := mkRun;
    VGK_CONTROL      : aMove := mkSlow;
  else
    aMove  := mkForward;
    Result := False;
  end;
end;

{ TvgFirstPersonTicker }

constructor TvgFirstPersonTicker.Create(aOwner: TvgFirstPersonController);
begin
  fOwner := aOwner;
  fWake  := TEvent.Create(nil, False, False, '');
  inherited Create(False);
end;

destructor TvgFirstPersonTicker.Destroy;
begin
  FreeAndNil(fWake);
  inherited Destroy;
end;

procedure TvgFirstPersonTicker.Execute;
var
  Interval : Integer;
begin
  while not Terminated do
  begin
    if TInterlocked.CompareExchange(fRunning, 0, 0) = 0 then
    begin
      fWake.WaitFor(INFINITE);
      Continue;
    end;

    Interval := fOwner.fTickInterval;
    if Interval < 1 then Interval := 1;
    Sleep(Interval);
    if Terminated then Break;

    // One tick at a time: a busy main thread gets one, not a backlog.
    if (TInterlocked.CompareExchange(fRunning, 0, 0) = 1) and
       (TInterlocked.CompareExchange(fQueued, 1, 0) = 0) then
      Queue(
        procedure
        begin
          TInterlocked.Exchange(fQueued, 0);
          fOwner.TimerTick;
        end);
  end;
end;

procedure TvgFirstPersonTicker.Start_;
begin
  TInterlocked.Exchange(fRunning, 1);
  fWake.SetEvent;
end;

procedure TvgFirstPersonTicker.Stop_;
begin
  TInterlocked.Exchange(fRunning, 0);
end;

procedure TvgFirstPersonTicker.Shutdown;
begin
  Stop_;
  Terminate;
  fWake.SetEvent;
  WaitFor;
  // A tick queued before the thread ended must not run on a freed owner.
  TThread.RemoveQueuedEvents(Self);
end;

{ TvgFirstPersonController }

constructor TvgFirstPersonController.Create(const aHost: IvgFirstPersonHost);
begin
  inherited Create;
  fHost            := aHost;
  fSpeed           := 0;
  fRunMultiplier   := 4.0;
  fSlowMultiplier  := 0.25;
  fSpeedScale      := 1.0;
  fLookSensitivity := 1.0;
  fInvertY         := False;
  fAutoTick        := True;
  fTickInterval    := 16;
  fClock           := TStopwatch.StartNew;
end;

destructor TvgFirstPersonController.Destroy;
begin
  if Assigned(fTicker) then
  begin
    fTicker.Shutdown;
    FreeAndNil(fTicker);
  end;
  fHost := nil;
  inherited Destroy;
end;

procedure TvgFirstPersonController.Assign(Source: TPersistent);
var
  S : TvgFirstPersonController;
begin
  if Source is TvgFirstPersonController then
  begin
    S := TvgFirstPersonController(Source);
    fSpeed           := S.fSpeed;
    fRunMultiplier   := S.fRunMultiplier;
    fSlowMultiplier  := S.fSlowMultiplier;
    fLookSensitivity := S.fLookSensitivity;
    fInvertY         := S.fInvertY;
    fAutoTick        := S.fAutoTick;
    fTickInterval    := S.fTickInterval;
  end
  else
    inherited Assign(Source);
end;

procedure TvgFirstPersonController.SetTickInterval(const Value: Integer);
begin
  fTickInterval := EnsureRange(Value, 1, 1000);
end;

procedure TvgFirstPersonController.SetSpeedScale(const Value: Double);
begin
  fSpeedScale := EnsureRange(Value, 1e-4, 1e4);
end;

function TvgFirstPersonController.DirectionHeld: Boolean;
begin
  Result := fHeld * [mkForward, mkBack, mkLeft, mkRight, mkUp, mkDown] <> [];
end;

function TvgFirstPersonController.TakeElapsed: Double;
var
  Now_ : Int64;
begin
  Now_      := fClock.ElapsedTicks;
  Result    := (Now_ - fLastTick) / TStopwatch.Frequency;
  fLastTick := Now_;
end;

procedure TvgFirstPersonController.Moved;
begin
  if Assigned(fHost) then
    fHost.FirstPersonMoved;
  if Assigned(fOnMoved) then
    fOnMoved(Self);
end;

procedure TvgFirstPersonController.StartTicking;
begin
  fLastTick := fClock.ElapsedTicks;
  if not fAutoTick then exit;
  if not Assigned(fTicker) then
    fTicker := TvgFirstPersonTicker.Create(Self);
  fTicker.Start_;
end;

procedure TvgFirstPersonController.StopTicking;
begin
  if Assigned(fTicker) then
    fTicker.Stop_;
end;

procedure TvgFirstPersonController.TimerTick;
begin
  if not DirectionHeld then
  begin
    StopTicking;
    exit;
  end;
  Tick(TakeElapsed);
end;

function TvgFirstPersonController.KeyDown(aKey: Word; aShift: TShiftState): Boolean;
var
  M      : TvgMoveKey;
  WasHeld: Boolean;
begin
  Result := False;
  if not vgMoveKeyOf(aKey, M) then exit;

  WasHeld := DirectionHeld;
  if (M in [mkRun, mkSlow]) and DirectionHeld then
    // The speed changes from here on: move at the old one up to now.
    Tick(TakeElapsed);
  Include(fHeld, M);
  Result := not (M in [mkRun, mkSlow]);

  // With a direction key the platform's own modifier state is the truth: a
  // Shift/Ctrl press or release can miss us (made while another window had
  // focus).
  if Result then
  begin
    if ssShift in aShift then Include(fHeld, mkRun)  else Exclude(fHeld, mkRun);
    if ssCtrl  in aShift then Include(fHeld, mkSlow) else Exclude(fHeld, mkSlow);
  end;

  if DirectionHeld and not WasHeld then
    StartTicking;
end;

function TvgFirstPersonController.KeyUp(aKey: Word; aShift: TShiftState): Boolean;
var
  M : TvgMoveKey;
begin
  Result := False;
  if not vgMoveKeyOf(aKey, M) then exit;
  if not (M in fHeld) then exit(not (M in [mkRun, mkSlow]));

  // Move for the time since the last tick first, so a short tap still moves
  // and the step does not depend on when the timer last fired.
  if DirectionHeld then
    Tick(TakeElapsed);

  Exclude(fHeld, M);
  Result := not (M in [mkRun, mkSlow]);

  if not DirectionHeld then
    StopTicking;
end;

procedure TvgFirstPersonController.ReleaseAll;
begin
  fHeld := [];
  StopTicking;
end;

function TvgFirstPersonController.EffectiveSpeed: Double;
var
  Size : Double;
begin
  if fSpeed > 0 then
    Result := fSpeed
  else
  begin
    Size := 0;
    if Assigned(fHost) then
      Size := fHost.FirstPersonSceneSize;
    if Size > 0 then
      Result := Size / AUTO_SPEED_SPAN
    else
      Result := DEFAULT_SPEED;
  end;
  Result := Result * fSpeedScale;
end;

procedure TvgFirstPersonController.Tick(aSeconds: Double);
var
  Cam      : TvgCamera;
  Fwd, Rt  : TpvVector3D;
  Up       : TpvVector3D;
  Move     : TpvVector3D;
  F, R, U  : Integer;
  Len      : Double;
  Dist     : Double;
begin
  // The time up to here is spent, whoever called: a key-up then finishes
  // from this point, not from the last internal tick.
  fLastTick := fClock.ElapsedTicks;

  if not Assigned(fHost) then exit;
  if aSeconds <= 0 then exit;
  if aSeconds > MAX_TICK_SECONDS then aSeconds := MAX_TICK_SECONDS;

  F := Ord(mkForward in fHeld) - Ord(mkBack in fHeld);
  R := Ord(mkRight   in fHeld) - Ord(mkLeft in fHeld);
  U := Ord(mkUp      in fHeld) - Ord(mkDown in fHeld);
  if (F = 0) and (R = 0) and (U = 0) then exit;

  Cam := fHost.FirstPersonCamera;
  if not Assigned(Cam) then exit;

  Fwd  := Cam.ForwardVector;
  Rt   := Cam.RightVector;
  Up   := Cam.UpVector;
  Move := Fwd * F + Rt * R + Up * U;
  Len  := Move.Length;
  if Len < 1e-12 then exit;   // e.g. forward + down while looking straight down

  Dist := EffectiveSpeed * aSeconds;
  if mkRun  in fHeld then Dist := Dist * fRunMultiplier;
  if mkSlow in fHeld then Dist := Dist * fSlowMultiplier;

  // Diagonals are no faster than straight lines.
  Cam.Translate(Move * (Dist / Len));
  Moved;
end;

procedure TvgFirstPersonController.Look(aDeltaX, aDeltaY: Double);
var
  Cam : TvgCamera;
begin
  if not Assigned(fHost) then exit;
  Cam := fHost.FirstPersonCamera;
  if not Assigned(Cam) then exit;

  // Screen Y grows downwards: dragging up (negative dY) looks up.
  if fInvertY then
    Cam.Look(-aDeltaX * fLookSensitivity,  aDeltaY * fLookSensitivity)
  else
    Cam.Look(-aDeltaX * fLookSensitivity, -aDeltaY * fLookSensitivity);
  Moved;
end;

procedure TvgFirstPersonController.MoveForward(aDistance: Double);
var
  Cam : TvgCamera;
begin
  if not Assigned(fHost) then exit;
  Cam := fHost.FirstPersonCamera;
  if not Assigned(Cam) then exit;
  Cam.Translate(Cam.ForwardVector * aDistance);
  Moved;
end;

procedure TvgFirstPersonController.Wheel(aWheelDelta: Integer);
begin
  SpeedScale := fSpeedScale * Power(WHEEL_STEP, aWheelDelta / 120.0);
end;

end.
