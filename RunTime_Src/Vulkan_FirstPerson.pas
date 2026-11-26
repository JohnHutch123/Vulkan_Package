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

  Walk (nmWalk) moves along the ground plane whatever the pitch, and keeps
  the eye EyeHeight above the surface IvgGroundProvider reports under it:
    - the ground is the highest surface no more than StepHeight above the
      feet, so stairs and kerbs are climbed and a floor is found under a
      ceiling;
    - a surface steeper than MaxSlope (its normal), anything taller than a
      step, and - with EdgeBehaviour ebStop - the edge of the ground refuse
      the step (OnBlocked);
    - going down is never refused;
    - the eye follows height changes over HeightSmoothing seconds, and
      settles exactly when movement stops.
  With no ground provider, walking is flying on the level.
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
    nmFly,     // first person: keys move, the mouse looks about the eye
    nmWalk     // as nmFly, but on the ground: the eye stays EyeHeight above
               // the surface under it (IvgGroundProvider)
  );

  TvgMoveKey  = (mkForward, mkBack, mkLeft, mkRight, mkUp, mkDown, mkRun, mkSlow);
  TvgMoveKeys = set of TvgMoveKey;

  // Walking off the edge of the ground.
  TvgEdgeBehaviour = (
    ebStop,    // the step is refused, as at a wall (the default)
    ebFloat    // carry on at the same height until there is ground again
  );

  { The surface walk mode follows - see TvgMeshGround (Vulkan_MeshGround) for
    a triangle mesh; a Delaunay surface can answer straight from its
    triangulation.  World coordinates, double. }
  IvgGroundProvider = interface
    ['{0E5B6C47-2C9A-4F0B-8D61-3A7E4B9F12C8}']
    { The highest surface point on the vertical line through aPoint whose
      height (along GroundUp) is at most aMaxHeight - so a floor is found
      under a ceiling, a bridge deck over a road.  aGround: that point;
      aNormal: the surface's normal there, leaning up.  False when the line
      meets no surface at or below aMaxHeight. }
    function  GroundAt(const aPoint: TpvVector3D; aMaxHeight: Double;
                       out aGround, aNormal: TpvVector3D): Boolean;
    // Unit vector: what "up" and "height" mean to GroundAt.
    function  GroundUp: TpvVector3D;
  end;

  // What a first-person controller needs from whoever owns it.
  IvgFirstPersonHost = interface
    ['{9A3D27E1-6B4C-4E8F-A0D5-7C1B2E3F4A60}']
    // The camera to move; nil for none (nothing moves).
    function  FirstPersonCamera: TvgCamera;
    // The size of the data in world units (the diagonal of its bounds), for
    // the automatic speed; 0 when unknown.
    function  FirstPersonSceneSize: Double;
    // The ground walk mode follows; nil for none (walking keeps its height).
    function  FirstPersonGround: IvgGroundProvider;
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

    // Walking
    fMode           : TvgNavigationMode;
    fEyeHeight      : Double;
    fStepHeight     : Double;
    fMaxSlope       : Double;
    fEdge           : TvgEdgeBehaviour;
    fSmoothing      : Double;
    fOnBlocked      : TNotifyEvent;
    fWalkValid      : Boolean;   // fGroundH / fEyeH describe the camera now
    fGrounded       : Boolean;   // fGroundH came from the ground, not a float
    fGroundH        : Double;    // height of the ground under the eye (along up)
    fEyeH           : Double;    // height of the eye, smoothed (along up)

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

    procedure SetMode(const Value: TvgNavigationMode);
    procedure SetEyeHeight(const Value: Double);
    // The ground's up, or the camera's when there is no ground.
    function  WalkUp(aCam: TvgCamera; const aGround: IvgGroundProvider): TpvVector3D;
    { One walking step: aMove (horizontal, world units) then onto the ground.
      aSeconds smooths the eye height; 0 puts it straight at the target.
      False when the step was refused (slope, step, edge). }
    function  WalkStep(const aMove: TpvVector3D; aSeconds: Double): Boolean;
    // The eye straight onto ground + EyeHeight, no smoothing - movement ended.
    procedure SettleWalk;

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

    { Starts walking where the camera is: finds the highest ground below the
      eye (or, with the eye under the surface, the ground above it) and puts
      the eye EyeHeight over it.  Called by SetMode(nmWalk); call it again
      after moving the camera yourself.  False when there is no ground under
      the eye - walking then keeps the eye's height (floating). }
    function  BeginWalk: Boolean;

    property  Held      : TvgMoveKeys read fHeld;
    // Wheel-adjusted multiplier on the speed, 1 at start.
    property  SpeedScale: Double read fSpeedScale write SetSpeedScale;
    { nmFly or nmWalk (nmOrbit: the keys are not routed here at all).
      TvgToolManager.NavigationMode sets it.  Changing to nmWalk calls
      BeginWalk. }
    property  Mode      : TvgNavigationMode read fMode write SetMode;
    // Walking, and the last step found ground (not floating past an edge).
    property  Grounded  : Boolean read fGrounded;
    // Height of the ground under the eye, along the ground's up; valid
    // while walking.
    property  GroundHeight : Double read fGroundH;

  published
    // World units per second.  0 (the default) is automatic: flying, a
    // twentieth of the data's size, so crossing it takes about 20 s whatever
    // its scale; walking, 0.8 x EyeHeight - a stroll at 1.7.
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

    // --- Walking (nmWalk), in world units -------------------------------
    // The eye above the ground.  1.7 suits a scene in metres.  Changed while
    // walking and standing still, the eye moves to the new height at once.
    property EyeHeight       : Double  read fEyeHeight       write SetEyeHeight;
    // The highest rise taken in one step - a kerb, a stair.
    property StepHeight      : Double  read fStepHeight      write fStepHeight;
    // Degrees: steeper climbs are refused.  Going down is never refused.
    property MaxSlope        : Double  read fMaxSlope        write fMaxSlope;
    property EdgeBehaviour   : TvgEdgeBehaviour read fEdge   write fEdge default ebStop;
    // Seconds the eye takes to follow a change in ground height (about two
    // thirds of the way); 0 follows it exactly.  Smooths a coarse surface.
    property HeightSmoothing : Double  read fSmoothing       write fSmoothing;
    // A walking step was refused - too steep, too high, or off the edge.
    property OnBlocked       : TNotifyEvent read fOnBlocked write fOnBlocked;
  end;

  // VGK_* code -> movement key; False for any other key.
  function vgMoveKeyOf(aKey: Word; out aMove: TvgMoveKey): Boolean;

implementation

const
  MAX_TICK_SECONDS = 0.25;
  WHEEL_STEP       = 1.25;
  AUTO_SPEED_SPAN  = 20.0;     // seconds to cross the data at auto speed
  DEFAULT_SPEED    = 1.0;      // units/s when the size of the data is unknown
  WALK_PACE        = 0.8;      // auto walking speed, in eye heights per second
  // While moving, the smoothed eye never sinks below this fraction of
  // EyeHeight over the ground - it lags a climb, it does not go under it.
  MIN_EYE_FRACTION = 0.5;

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
  fMode            := nmFly;
  fEyeHeight       := 1.7;
  fStepHeight      := 0.4;
  fMaxSlope        := 45;
  fEdge            := ebStop;
  fSmoothing       := 0.1;
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
    fEyeHeight       := S.fEyeHeight;
    fStepHeight      := S.fStepHeight;
    fMaxSlope        := S.fMaxSlope;
    fEdge            := S.fEdge;
    fSmoothing       := S.fSmoothing;
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
  begin
    StopTicking;
    // Stopped: the smoothed eye comes the rest of the way at once, so the
    // view at rest is exactly EyeHeight over the ground.
    if fMode = nmWalk then
      SettleWalk;
  end;
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
  else if fMode = nmWalk then
    // Walking pace from the body's own size, not the data's: a 2 km terrain
    // must not be crossed in 20 s on foot.
    Result := Max(fEyeHeight, 1e-6) * WALK_PACE
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
  if fMode = nmWalk then U := 0;      // feet on the ground: no up/down
  if (F = 0) and (R = 0) and (U = 0) then exit;

  Cam := fHost.FirstPersonCamera;
  if not Assigned(Cam) then exit;

  Fwd  := Cam.ForwardVector;
  Rt   := Cam.RightVector;
  if fMode = nmWalk then
  begin
    // Along the ground plane, whatever the pitch: looking down at your feet
    // and pressing forward walks, it does not dig.
    Up  := WalkUp(Cam, fHost.FirstPersonGround);
    Fwd := Fwd - Up * Fwd.Dot(Up);
    Rt  := Rt  - Up * Rt.Dot(Up);
    if Fwd.Length > 1e-12 then Fwd := Fwd.Normalize;
    if Rt.Length  > 1e-12 then Rt  := Rt.Normalize;
  end
  else
    Up := Cam.UpVector;
  Move := Fwd * F + Rt * R + Up * U;
  Len  := Move.Length;
  if Len < 1e-12 then exit;   // e.g. forward + down while looking straight down

  Dist := EffectiveSpeed * aSeconds;
  if mkRun  in fHeld then Dist := Dist * fRunMultiplier;
  if mkSlow in fHeld then Dist := Dist * fSlowMultiplier;

  // Diagonals are no faster than straight lines.
  if fMode = nmWalk then
    WalkStep(Move * (Dist / Len), aSeconds)
  else
  begin
    Cam.Translate(Move * (Dist / Len));
    Moved;
  end;
end;

// ---------------------------------------------------------------------------
//  Walking
// ---------------------------------------------------------------------------

procedure TvgFirstPersonController.SetMode(const Value: TvgNavigationMode);
begin
  if fMode = Value then exit;
  ReleaseAll;
  fMode      := Value;
  fWalkValid := False;
  fGrounded  := False;
  if fMode = nmWalk then
    BeginWalk;
end;

function TvgFirstPersonController.WalkUp(aCam: TvgCamera; const aGround: IvgGroundProvider): TpvVector3D;
begin
  if Assigned(aGround) then
    Result := aGround.GroundUp
  else if Assigned(aCam) then
    Result := aCam.UpVector
  else
    Result := TpvVector3D.Create(0, 0, 1);
end;

function TvgFirstPersonController.BeginWalk: Boolean;
var
  Cam     : TvgCamera;
  Ground  : IvgGroundProvider;
  Up, P   : TpvVector3D;
  G, N    : TpvVector3D;
  EyeH    : Double;
begin
  Result     := False;
  fWalkValid := False;
  fGrounded  := False;
  if not Assigned(fHost) then exit;
  Cam := fHost.FirstPersonCamera;
  if not Assigned(Cam) then exit;

  Ground := fHost.FirstPersonGround;
  Up     := WalkUp(Cam, Ground);
  P      := Cam.Position;
  EyeH   := P.Dot(Up);

  // The ground below the eye; failing that (the eye is under the surface,
  // as an orbit view from below can leave it) whatever is above.
  if Assigned(Ground) and
     (Ground.GroundAt(P, EyeH, G, N) or Ground.GroundAt(P, MaxDouble, G, N)) then
  begin
    fGroundH  := G.Dot(Up);
    fGrounded := True;
    Result    := True;
  end
  else
    fGroundH := EyeH - fEyeHeight;   // float where we are

  fEyeH      := EyeH;
  fWalkValid := True;
  SettleWalk;
end;

procedure TvgFirstPersonController.SetEyeHeight(const Value: Double);
begin
  if Value = fEyeHeight then exit;
  fEyeHeight := Value;
  // Moving, the next step smooths towards it; standing, show it now.
  if (fMode = nmWalk) and not DirectionHeld then
    SettleWalk;
end;

procedure TvgFirstPersonController.SettleWalk;
var
  Cam    : TvgCamera;
  Up     : TpvVector3D;
  Target : Double;
  P      : TpvVector3D;
begin
  if not fWalkValid or not Assigned(fHost) then exit;
  Cam := fHost.FirstPersonCamera;
  if not Assigned(Cam) then exit;

  Up     := WalkUp(Cam, fHost.FirstPersonGround);
  Target := fGroundH + fEyeHeight;
  P      := Cam.Position;
  if Abs(P.Dot(Up) - Target) > 0 then
  begin
    Cam.Translate(Up * (Target - P.Dot(Up)));
    Moved;
  end;
  fEyeH := Target;
end;

function TvgFirstPersonController.WalkStep(const aMove: TpvVector3D; aSeconds: Double): Boolean;
var
  Cam      : TvgCamera;
  Ground   : IvgGroundProvider;
  Up       : TpvVector3D;
  P, NewP  : TpvVector3D;
  G, N     : TpvVector3D;
  NewGH    : Double;
  Climb    : Double;
  Run      : Double;
  Target   : Double;
  EyeH     : Double;
  Found    : Boolean;
  Grounded : Boolean;

  function Refuse: Boolean;
  begin
    if Assigned(fOnBlocked) then
      fOnBlocked(Self);
    Result := False;
  end;

begin
  Result := False;
  if not Assigned(fHost) then exit;
  Cam := fHost.FirstPersonCamera;
  if not Assigned(Cam) then exit;
  if not fWalkValid then
    BeginWalk;

  Ground := fHost.FirstPersonGround;
  Up     := WalkUp(Cam, Ground);
  P      := Cam.Position;
  NewP   := P + aMove;
  Run    := aMove.Length;

  NewGH    := fGroundH;
  Grounded := False;
  if Assigned(Ground) then
  begin
    // Highest surface no higher than a step up: a floor under a ceiling, a
    // deck over a road.  The limit itself refuses anything taller than a
    // step - unless there is lower ground there, which is then where we go.
    Found := Ground.GroundAt(NewP, fGroundH + fStepHeight, G, N);
    if Found then
    begin
      NewGH := G.Dot(Up);
      Climb := NewGH - fGroundH;
      // Climbing onto a surface steeper than MaxSlope is refused.  The
      // surface's own normal, not rise over run: a stair (a step no higher
      // than StepHeight onto a level tread) is a huge rise over a short run
      // but must be walkable; a steep hillside must not.
      if (Climb > 0) and (Run > 0) and
         (N.Dot(Up) < Cos(DegToRad(EnsureRange(fMaxSlope, 0, 90)))) then
        exit(Refuse);
      Grounded := True;
    end
    else
    begin
      // Something there, but higher than a step: a wall or a cliff.
      if Ground.GroundAt(NewP, MaxDouble, G, N) then
        exit(Refuse);
      // Nothing at all: the edge.
      if fEdge = ebStop then
        exit(Refuse);
      // ebFloat: carry on at the same height.
    end;
  end;

  fGroundH  := NewGH;
  fGrounded := Grounded;

  // The eye follows the ground with a lag (smooths a coarse surface), but
  // never falls below half the eye height - it lags a climb, it never sinks
  // into the slope.
  Target := fGroundH + fEyeHeight;
  if (aSeconds <= 0) or (fSmoothing <= 0) then
    EyeH := Target
  else
    EyeH := Target + (fEyeH - Target) * Exp(-aSeconds / fSmoothing);
  if EyeH < fGroundH + fEyeHeight * MIN_EYE_FRACTION then
    EyeH := fGroundH + fEyeHeight * MIN_EYE_FRACTION;
  fEyeH := EyeH;

  NewP := NewP + Up * (EyeH - NewP.Dot(Up));
  Cam.Translate(NewP - P);
  Moved;
  Result := True;
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
  Cam     : TvgCamera;
  Up, Fwd : TpvVector3D;
begin
  if not Assigned(fHost) then exit;
  Cam := fHost.FirstPersonCamera;
  if not Assigned(Cam) then exit;
  if fMode = nmWalk then
  begin
    // Along the ground, then onto it - no smoothing, a drag is not timed.
    Up  := WalkUp(Cam, fHost.FirstPersonGround);
    Fwd := Cam.ForwardVector;
    Fwd := Fwd - Up * Fwd.Dot(Up);
    if Fwd.Length < 1e-12 then exit;
    WalkStep(Fwd.Normalize * aDistance, 0);
    exit;
  end;
  Cam.Translate(Cam.ForwardVector * aDistance);
  Moved;
end;

procedure TvgFirstPersonController.Wheel(aWheelDelta: Integer);
begin
  SpeedScale := fSpeedScale * Power(WHEEL_STEP, aWheelDelta / 120.0);
end;

end.
