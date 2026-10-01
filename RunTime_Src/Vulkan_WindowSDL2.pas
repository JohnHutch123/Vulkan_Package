{ TvgSDL2Window

  Presents a Vulkan session in an SDL2 window instead of a VCL control - the
  SDL counterpart of TvgWindowVCL.  Connect it to a linker the same way:

      Window := TvgSDL2Window.Create(Self);
      Window.Caption := 'Model';
      Window.VulkanLink := Linker1;       //or Linker1.WindowIntf := Window
      Instance1.Active := True;           //starts the session

  The SDL window is created on first use (when the session builds its
  surface) and SDL's video subsystem is started with the first window and
  stopped with the last, so merely linking this unit or loading its package
  does not touch SDL.  Nothing is created at design time.

  SDL reports resizing, closing and input through its event queue, which
  the application must drain.  Call TvgSDL2Window.ProcessEvents regularly -
  from Application.OnIdle, a timer, or your own loop.  It forwards mouse,
  wheel and key input to the linker (and so to its tool manager), rebuilds
  the swap chain on resize and repaints on expose.  Closing the window fires
  OnClose; unless the handler refuses, this window's linker is disabled and
  the SDL window destroyed - other windows keep running.  Set Active True
  (or re-enable the linker) to open it again.

  Needs SDL 2.0.6 or later (Vulkan support).  Compile with
  PasVulkanUseSDL2, PasVulkanUseSDL2WithVulkanSupport and
  PasVulkanUseSDL2WithStaticVulkanSupport defined, as VulkanPkg_SDL2R280
  does.  PasVulkan.SDL2 links SDL statically against 'sdl2.dll' (Win32) or
  'sdl264.dll' (Win64), so a Win64 application must ship SDL2.dll under the
  name sdl264.dll. }

unit Vulkan_WindowSDL2;

interface

uses
  System.SysUtils,
  System.Classes,
  System.UITypes,
  System.Generics.Collections,
  Vulkan,
  PasVulkan.SDL2,
  Vulkan_Components,
  Vulkan_Components_Lookups;

type
  ESDL2WindowError = class(Exception);

  { CanClose False keeps the window open. }
  TvgSDL2CloseEvent = procedure(Sender: TObject; var CanClose: Boolean) of object;

  TvgSDL2Window = class(TComponent, IvgVulkanWindow)
  private
    class var fWindows  : TList<TvgSDL2Window>;   //live SDL windows, for event routing
    class var fSDLUsers : Integer;                //windows holding SDL's video subsystem

    var
    fLinker         : TvgLinker;
    fVulkanActive   : Boolean;

    fSDLWindow      : PSDL_Window;
    fWindowID       : TSDLUInt32;
    fRepaintPending : Boolean;
    fButtons        : set of TvgMouseButton;      //held, for the Shift state of moves

    fCaption        : string;
    fLeft, fTop     : Integer;
    fWidth, fHeight : Integer;
    fResizable      : Boolean;
    fClearColor     : TAlphaColor;
    fCrossHairCursor: Boolean;

    fOnClose        : TvgSDL2CloseEvent;
    fOnResize       : TNotifyEvent;

    class procedure AcquireSDL;
    class procedure ReleaseSDL;
    class function  FindWindow(aWindowID: TSDLUInt32): TvgSDL2Window;

    procedure CreateSDLWindow;
    procedure DestroySDLWindow;
    procedure HandleEvent(const aEvent: TSDL_Event);
    function  ShiftState(aMouseState: TSDLUInt32): TShiftState;
    function  VulkanInstanceHandle: TVkInstance;

    function  GetActive: Boolean;
    procedure SetActive(const Value: Boolean);
    function  GetHandleAllocated: Boolean;
    procedure SetCaption(const Value: string);
    procedure SetWidth(const Value: Integer);
    procedure SetHeight(const Value: Integer);

  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;

  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Drains SDL's event queue and hands each event to its window.  Call it
      regularly (Application.OnIdle, a timer, your own loop). }
    class procedure ProcessEvents;

    { The SDL window, nil until the session first needs it. }
    property SDLWindow       : PSDL_Window read fSDLWindow;
    property HandleAllocated : Boolean     read GetHandleAllocated;

    //IvgVulkanWindow
    function  GetLinker: TvgLinker;
    procedure SetLinker(const Value: TvgLinker);

    procedure SetDisabled;
    procedure SetDesigning;
    procedure SetEnabled(aComp: TvgBaseComponent = nil);
    procedure DisableParent(ToRoot: Boolean = False);

    procedure vgWindowSizeCallback(var WinWidth, WinHeight: TvkUint32);
    procedure vgWindowInvalidate(DoPaint: Boolean);
    procedure vgWindowBackgroundColor(var aColor: TVkClearValue);
    function  vgWindowGetSurface(var aSurface: TVkSurfaceKHR): Boolean;
    function  vgCrossHairON: Boolean;

{$if defined(Android)}
    procedure SurfaceWinPlatformCallback(var aWindow: PVkAndroidANativeWindow);
{$ifend}
{$if defined(Wayland) and defined(Unix)}
    procedure SurfaceWinPlatformCallback(var aDisplay: PVkWaylandDisplay; var aSurface: PVkWaylandSurface);
{$ifend}
{$if defined(Win32) or defined(Win64)}
    procedure SurfaceWinPlatformCallback(var aWinInstance: TVkHWND; var aModInstance: TVkHINSTANCE);
{$ifend}
{$if defined(XCB) and defined(Unix)}
    procedure SurfaceWinPlatformCallback(var aConnection: PVkXCBConnection; var aWindow: TVkXCBWindow);
{$ifend}
{$if defined(XLIB) and defined(Unix)}
    procedure SurfaceWinPlatformCallback(var aDisplay: PVkXLIBDisplay; var aWindow: TVkXLIBWindow);
{$ifend}
{$if defined(MoltenVK_IOS) and defined(Darwin)}
    procedure SurfaceWinPlatformCallback(var aView: PVkVoid);
{$ifend}
{$if defined(MoltenVK_MacOS) and defined(Darwin)}
    procedure SurfaceWinPlatformCallback(var aView: PVkVoid);
{$ifend}

  published
    property Active     : Boolean   read GetActive write SetActive stored False;
    property VulkanLink : TvgLinker read GetLinker write SetLinker;

    property Caption    : string  read fCaption   write SetCaption;
    { SDL_WINDOWPOS_CENTERED / SDL_WINDOWPOS_UNDEFINED or a position.  Used
      when the SDL window is created. }
    property Left       : Integer read fLeft      write fLeft   default Integer(SDL_WINDOWPOS_CENTERED);
    property Top        : Integer read fTop       write fTop    default Integer(SDL_WINDOWPOS_CENTERED);
    property Width      : Integer read fWidth     write SetWidth  default 800;
    property Height     : Integer read fHeight    write SetHeight default 600;
    property Resizable  : Boolean read fResizable write fResizable default True;

    property ClearColor : TAlphaColor read fClearColor write fClearColor default TAlphaColors.Black;
    property CrossHairCursor : Boolean read fCrossHairCursor write fCrossHairCursor default False;

    property OnClose    : TvgSDL2CloseEvent read fOnClose  write fOnClose;
    property OnResize   : TNotifyEvent      read fOnResize write fOnResize;
  end;

implementation

{ Not declared by PasVulkan.SDL2. }
function SDL_GetWindowID(window: PSDL_Window): TSDLUInt32; cdecl; external SDL2LibName;
procedure SDL_QuitSubSystem(flags: TSDLUInt32); cdecl; external SDL2LibName;

const
  //SDL_BUTTON(X) masks of SDL_MouseMotionEvent.state
  cSDLButtonLMask = 1 shl (SDL_BUTTON_LEFT - 1);
  cSDLButtonMMask = 1 shl (SDL_BUTTON_MIDDLE - 1);
  cSDLButtonRMask = 1 shl (SDL_BUTTON_RIGHT - 1);
  cSDLMouseWheelFlipped = 1;

  cWheelDelta = 120;   //one notch, as WM_MOUSEWHEEL reports it

{ SDL key code -> the VCL virtual-key code the tool manager (VGK_*) expects.
  0 when the key has no equivalent. }
function vgKeyFromSDL(aSym: TSDLInt32): Word;
begin
  Result := 0;
  case aSym of
    SDLK_BACKSPACE : Result := VGK_BACK;
    SDLK_TAB       : Result := VGK_TAB;
    SDLK_RETURN,
    SDLK_KP_ENTER  : Result := VGK_RETURN;
    SDLK_ESCAPE    : Result := VGK_ESCAPE;
    SDLK_SPACE     : Result := VGK_SPACE;
    SDLK_DELETE    : Result := VGK_DELETE;
    SDLK_INSERT    : Result := $2D;
    SDLK_PAGEUP    : Result := $21;
    SDLK_PAGEDOWN  : Result := $22;
    SDLK_END       : Result := $23;
    SDLK_HOME      : Result := $24;
    SDLK_LEFT      : Result := $25;
    SDLK_UP        : Result := $26;
    SDLK_RIGHT     : Result := $27;
    SDLK_DOWN      : Result := $28;
  else
    if (aSym >= SDLK_a) and (aSym <= SDLK_z) then
      Result := Word(Ord('A') + (aSym - SDLK_a))
    else
    if (aSym >= SDLK_0) and (aSym <= SDLK_0 + 9) then
      Result := Word(aSym)
    else
    if (aSym >= SDLK_F1) and (aSym <= SDLK_F12) then
      Result := Word($70 + (aSym - SDLK_F1));
  end;
end;

{ The window an event belongs to.  Every window-bound SDL event carries its
  windowID right after the timestamp, as SDL_WindowEvent does.  Read it from
  there: PasVulkan.SDL2 declares TSDL_MouseButtonEvent with windowID and
  which swapped, so event.button.windowID would give the mouse's id. }
function vgEventWindowID(const aEvent: TSDL_Event): TSDLUInt32;
begin
  Result := aEvent.window.windowID;
end;

{ TvgSDL2Window }

constructor TvgSDL2Window.Create(AOwner: TComponent);
begin
  inherited;
  fCaption   := 'Vulkan';
  fLeft      := Integer(SDL_WINDOWPOS_CENTERED);
  fTop       := Integer(SDL_WINDOWPOS_CENTERED);
  fWidth     := 800;
  fHeight    := 600;
  fResizable := True;
  fClearColor:= TAlphaColors.Black;
end;

destructor TvgSDL2Window.Destroy;
begin
  //the surface is made on the SDL window: stop the session before it goes
  DestroySDLWindow;

  if Assigned(fLinker) then
  begin
    fLinker.RemoveFreeNotification(Self);
    if fLinker.WindowIntf = IvgVulkanWindow(Self) then
      fLinker.WindowIntf := nil;
    fLinker := nil;
  end;

  inherited;
end;

class procedure TvgSDL2Window.AcquireSDL;
begin
  if fSDLUsers = 0 then
    if SDL_InitSubSystem(SDL_INIT_VIDEO) <> 0 then
      raise ESDL2WindowError.CreateFmt('SDL video could not start: %s', [string(UTF8String(SDL_GetError))]);
  Inc(fSDLUsers);
end;

class procedure TvgSDL2Window.ReleaseSDL;
begin
  if fSDLUsers <= 0 then exit;
  Dec(fSDLUsers);
  if fSDLUsers = 0 then
    SDL_QuitSubSystem(SDL_INIT_VIDEO);
end;

class function TvgSDL2Window.FindWindow(aWindowID: TSDLUInt32): TvgSDL2Window;
var
  W : TvgSDL2Window;
begin
  Result := nil;
  if not Assigned(fWindows) then exit;
  for W in fWindows do
    if W.fWindowID = aWindowID then
      Exit(W);
end;

procedure TvgSDL2Window.CreateSDLWindow;
var
  Flags : TSDLUInt32;
begin
  if Assigned(fSDLWindow) then exit;
  if csDesigning in ComponentState then
    raise ESDL2WindowError.Create('SDL windows are not created at design time.');

  AcquireSDL;
  try
    Flags := SDL_WINDOW_SHOWN or SDL_WINDOW_VULKAN;
    if fResizable then
      Flags := Flags or SDL_WINDOW_RESIZABLE;

    fSDLWindow := SDL_CreateWindow(PAnsiChar(UTF8String(fCaption)), fLeft, fTop, fWidth, fHeight, Flags);
    if not Assigned(fSDLWindow) then
      raise ESDL2WindowError.CreateFmt('SDL window could not be created: %s', [string(UTF8String(SDL_GetError))]);
  except
    ReleaseSDL;
    raise;
  end;

  fWindowID := SDL_GetWindowID(fSDLWindow);
  fButtons  := [];

  if not Assigned(fWindows) then
    fWindows := TList<TvgSDL2Window>.Create;
  fWindows.Add(Self);

  { Only WindowReady, unlike TvgWindowVCL.CreateHandle: no surface rebuild is
    flagged.  A new SDL window always comes with a session (re)start - it is
    created while the session builds its surface, and the session stops
    whenever it is destroyed - so there is no old surface to replace.
    Flagging one here, mid-enable, makes the next swap chain rebuild disable
    the surface, which disables the session through SetDisabled. }
  if Assigned(fLinker) then
    fLinker.WindowReady := True;
end;

procedure TvgSDL2Window.DestroySDLWindow;
begin
  if not Assigned(fSDLWindow) then exit;

  { The surface must go before the window it was made on.  Disabling this
    window's linker frees its surface and swap chain; other windows on the
    same device keep running.  (Not DisableParent, which would take down the
    whole device - or with ToRoot the session - and every window on it.) }
  if Assigned(fLinker) then
  begin
    if fLinker.Active then
      fLinker.Active := False;
    fLinker.WindowReady := False;
  end;
  fVulkanActive := False;

  if Assigned(fWindows) then
  begin
    fWindows.Remove(Self);
    if fWindows.Count = 0 then
      FreeAndNil(fWindows);
  end;

  SDL_DestroyWindow(fSDLWindow);
  fSDLWindow := nil;
  fWindowID  := 0;
  fButtons   := [];
  ReleaseSDL;
end;

class procedure TvgSDL2Window.ProcessEvents;
var
  E : TSDL_Event;
  W : TvgSDL2Window;
  I : Integer;
begin
  if fSDLUsers = 0 then exit;   //no SDL window: nothing to drain

  while SDL_PollEvent(@E) <> 0 do
    case E.type_ of
      SDL_WINDOWEVENT,
      SDL_MOUSEMOTION, SDL_MOUSEBUTTONDOWN, SDL_MOUSEBUTTONUP, SDL_MOUSEWHEEL,
      SDL_KEYDOWN:
        begin
          W := FindWindow(vgEventWindowID(E));
          if Assigned(W) then
            W.HandleEvent(E);
          if fSDLUsers = 0 then exit;   //the last window closed
        end;
    end;

  //repaints asked for without DoPaint
  if Assigned(fWindows) then
    for I := fWindows.Count - 1 downto 0 do
    begin
      W := fWindows[I];
      if W.fRepaintPending then
      begin
        W.fRepaintPending := False;
        W.vgWindowInvalidate(True);
      end;
    end;
end;

function TvgSDL2Window.ShiftState(aMouseState: TSDLUInt32): TShiftState;
var
  M : TSDLUInt32;
begin
  Result := [];
  M := SDL_GetModState;
  if (M and KMOD_SHIFT) <> 0 then Include(Result, ssShift);
  if (M and KMOD_CTRL)  <> 0 then Include(Result, ssCtrl);
  if (M and KMOD_ALT)   <> 0 then Include(Result, ssAlt);

  if (aMouseState and cSDLButtonLMask) <> 0 then Include(Result, ssLeft);
  if (aMouseState and cSDLButtonMMask) <> 0 then Include(Result, ssMiddle);
  if (aMouseState and cSDLButtonRMask) <> 0 then Include(Result, ssRight);
end;

procedure TvgSDL2Window.HandleEvent(const aEvent: TSDL_Event);
var
  Button   : TvgMouseButton;
  HasButton: Boolean;
  Held     : TSDLUInt32;
  Key      : Word;
  Delta    : Integer;
  CanClose : Boolean;
begin
  case aEvent.type_ of
    SDL_WINDOWEVENT:
      case aEvent.window.event of
        SDL_WINDOWEVENT_SIZE_CHANGED:
          begin
            fWidth  := aEvent.window.data1;
            fHeight := aEvent.window.data2;
            if Assigned(fLinker) and fLinker.Active then
            begin
              fLinker.FlagSwapChainRebuild;
              fLinker.TriggerWindowRepaint;
            end;
            if Assigned(fOnResize) then
              fOnResize(Self);
          end;

        SDL_WINDOWEVENT_EXPOSED:
          vgWindowInvalidate(True);

        SDL_WINDOWEVENT_CLOSE:
          begin
            CanClose := True;
            if Assigned(fOnClose) then
              fOnClose(Self, CanClose);
            if CanClose then
              DestroySDLWindow;
          end;
      end;

    SDL_MOUSEBUTTONDOWN, SDL_MOUSEBUTTONUP:
      begin
        HasButton := True;
        case aEvent.button.button of
          SDL_BUTTON_LEFT   : Button := vgmbLeft;
          SDL_BUTTON_MIDDLE : Button := vgmbMiddle;
          SDL_BUTTON_RIGHT  : Button := vgmbRight;
        else
          Button    := vgmbLeft;
          HasButton := False;
        end;
        if not HasButton then exit;

        if aEvent.type_ = SDL_MOUSEBUTTONDOWN then
          Include(fButtons, Button)
        else
          Exclude(fButtons, Button);

        Held := 0;
        if vgmbLeft   in fButtons then Held := Held or cSDLButtonLMask;
        if vgmbMiddle in fButtons then Held := Held or cSDLButtonMMask;
        if vgmbRight  in fButtons then Held := Held or cSDLButtonRMask;

        if Assigned(fLinker) then
          if aEvent.type_ = SDL_MOUSEBUTTONDOWN then
            fLinker.MouseDown(Button, ShiftState(Held), aEvent.button.x, aEvent.button.y)
          else
            fLinker.MouseUp(Button, ShiftState(Held), aEvent.button.x, aEvent.button.y);
      end;

    SDL_MOUSEMOTION:
      if Assigned(fLinker) then
        fLinker.MouseMove(ShiftState(aEvent.motion.state), aEvent.motion.x, aEvent.motion.y);

    SDL_MOUSEWHEEL:
      if Assigned(fLinker) and (aEvent.wheel.y <> 0) then
      begin
        Delta := aEvent.wheel.y * cWheelDelta;
        if aEvent.wheel.Direction = cSDLMouseWheelFlipped then
          Delta := -Delta;
        fLinker.MouseWheel(ShiftState(0), Delta);
      end;

    SDL_KEYDOWN:
      if Assigned(fLinker) then
      begin
        Key := vgKeyFromSDL(aEvent.key.keysym.sym);
        if Key <> 0 then
          fLinker.KeyDown(Key, ShiftState(0));
      end;
  end;
end;

function TvgSDL2Window.VulkanInstanceHandle: TVkInstance;
var
  Inst : TvgInstance;
begin
  Result := VK_NULL_HANDLE;
  if not Assigned(fLinker) or not Assigned(fLinker.ScreenDevice) then exit;

  Inst := fLinker.ScreenDevice.Instance;
  if not Assigned(Inst) and Assigned(fLinker.ScreenDevice.PhysicalDevice) then
    Inst := fLinker.ScreenDevice.PhysicalDevice.Instance;

  if Assigned(Inst) and Assigned(Inst.VulkanInstance) then
    Result := Inst.VulkanInstance.Handle;
end;

procedure TvgSDL2Window.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = fLinker) then
    fLinker := nil;
end;

function TvgSDL2Window.GetActive: Boolean;
begin
  Result := fVulkanActive;
end;

procedure TvgSDL2Window.SetActive(const Value: Boolean);
begin
  if fVulkanActive = Value then exit;
  if Value then
    SetEnabled
  else
    SetDisabled;
end;

function TvgSDL2Window.GetHandleAllocated: Boolean;
begin
  Result := Assigned(fSDLWindow);
end;

procedure TvgSDL2Window.SetCaption(const Value: string);
begin
  fCaption := Value;
  if Assigned(fSDLWindow) then
    SDL_SetWindowTitle(fSDLWindow, PAnsiChar(UTF8String(fCaption)));
end;

procedure TvgSDL2Window.SetWidth(const Value: Integer);
begin
  if (Value <= 0) or (Value = fWidth) then exit;
  fWidth := Value;
  if Assigned(fSDLWindow) then
    SDL_SetWindowSize(fSDLWindow, fWidth, fHeight);   //SIZE_CHANGED rebuilds the swap chain
end;

procedure TvgSDL2Window.SetHeight(const Value: Integer);
begin
  if (Value <= 0) or (Value = fHeight) then exit;
  fHeight := Value;
  if Assigned(fSDLWindow) then
    SDL_SetWindowSize(fSDLWindow, fWidth, fHeight);
end;

{ IvgVulkanWindow }

function TvgSDL2Window.GetLinker: TvgLinker;
begin
  Result := fLinker;
end;

procedure TvgSDL2Window.SetLinker(const Value: TvgLinker);
var
  OldLinker : TvgLinker;
begin
  if fLinker = Value then exit;

  if Assigned(fLinker) then
  begin
    OldLinker := fLinker;
    fLinker   := nil;
    OldLinker.RemoveFreeNotification(Self);
    //fLinker is already nil, so the linker does not call back.  Not while
    //the linker is being freed: its destructor called us and clears it.
    if not (csDestroying in OldLinker.ComponentState) and
       (OldLinker.WindowIntf = IvgVulkanWindow(Self)) then
      OldLinker.WindowIntf := nil;
  end;

  fLinker := Value;
  try
    if Assigned(fLinker) then
    begin
      if fLinker.WindowIntf <> IvgVulkanWindow(Self) then
        fLinker.WindowIntf := Self;

      //setting WindowIntf stopped the linker, so it makes a new surface anyway
      if Assigned(fSDLWindow) then
        fLinker.WindowReady := True;

      fLinker.FreeNotification(Self);
    end;
  except
    //leave nothing half linked, and let the caller see why
    OldLinker := fLinker;
    fLinker   := nil;
    if Assigned(OldLinker) and (OldLinker.WindowIntf = IvgVulkanWindow(Self)) then
      OldLinker.WindowIntf := nil;
    raise;
  end;
end;

procedure TvgSDL2Window.SetDisabled;
begin
  { Called by the linker's surface as it goes down - when the linker is
    disabled, or its surface rebuilt.  The linker is already doing the work,
    so only note it; the SDL window itself stays. }
  fVulkanActive := False;
end;

procedure TvgSDL2Window.SetDesigning;
begin
end;

procedure TvgSDL2Window.SetEnabled(aComp: TvgBaseComponent = nil);
begin
  fVulkanActive := False;
  if not Assigned(fLinker) then exit;

  //as TvgWindowVCL: start the session from the top if it is not running
  if Assigned(fLinker.ScreenDevice) and
     Assigned(fLinker.ScreenDevice.Instance) and
     not fLinker.ScreenDevice.Instance.Active then
  begin
    fLinker.ScreenDevice.Instance.Active := True;
    fVulkanActive := fLinker.Active;
    exit;
  end;

  //the session runs but this window's linker was stopped (window closed):
  //bring just the linker back, which creates the SDL window again
  if not fLinker.Active then
    fLinker.Active := True;

  fVulkanActive := fLinker.Active;
  if fVulkanActive then
    vgWindowInvalidate(True);
end;

procedure TvgSDL2Window.DisableParent(ToRoot: Boolean = False);
begin
  if Assigned(fLinker) and fLinker.Active then
    fLinker.DisableParent(ToRoot);
end;

procedure TvgSDL2Window.vgWindowSizeCallback(var WinWidth, WinHeight: TvkUint32);
var
  W, H : TSDLInt32;
begin
  W := 0;
  H := 0;
  if Assigned(fSDLWindow) then
    SDL_Vulkan_GetDrawableSize(fSDLWindow, @W, @H);   //pixels, as the swap chain wants

  if W < 0 then W := 0;
  if H < 0 then H := 0;
  WinWidth  := TvkUint32(W);
  WinHeight := TvkUint32(H);
end;

procedure TvgSDL2Window.vgWindowInvalidate(DoPaint: Boolean);
begin
  //SDL has no paint message: a repaint is a new frame from the linker
  if not DoPaint then
  begin
    fRepaintPending := True;   //run by ProcessEvents
    exit;
  end;

  if Assigned(fLinker) and fLinker.Active then
    fLinker.TriggerWindowRepaint;
end;

procedure TvgSDL2Window.vgWindowBackgroundColor(var aColor: TVkClearValue);
var
  C : TAlphaColorRec;
begin
  C.Color := fClearColor;
  aColor.color.float32[0] := C.R / 255;
  aColor.color.float32[1] := C.G / 255;
  aColor.color.float32[2] := C.B / 255;
  aColor.color.float32[3] := 1.0;
end;

function TvgSDL2Window.vgWindowGetSurface(var aSurface: TVkSurfaceKHR): Boolean;
var
  Inst : TVkInstance;
  S    : TVkSurfaceKHR;
begin
  { A new surface on every call.  The caller wraps it in a TpvVulkanSurface,
    which destroys the handle when the session shuts down, so a surface is
    never kept here and reused. }
  Result   := False;
  aSurface := VK_NULL_HANDLE;

  Inst := VulkanInstanceHandle;
  if Inst = VK_NULL_HANDLE then exit;

  CreateSDLWindow;

  S := VK_NULL_HANDLE;
  if not SDL_Vulkan_CreateSurface(fSDLWindow, Inst, @S) then
    raise ESDL2WindowError.CreateFmt('SDL could not create a Vulkan surface: %s', [string(UTF8String(SDL_GetError))]);

  aSurface := S;
  Result   := aSurface <> VK_NULL_HANDLE;
end;

function TvgSDL2Window.vgCrossHairON: Boolean;
begin
  Result := fCrossHairCursor;
end;

{ Platform callbacks: only used when vgWindowGetSurface returns False. }

{$if defined(Android)}
procedure TvgSDL2Window.SurfaceWinPlatformCallback(var aWindow: PVkAndroidANativeWindow);
begin
  aWindow := nil;
end;
{$ifend}

{$if defined(Wayland) and defined(Unix)}
procedure TvgSDL2Window.SurfaceWinPlatformCallback(var aDisplay: PVkWaylandDisplay; var aSurface: PVkWaylandSurface);
begin
  aDisplay := nil;
  aSurface := nil;
end;
{$ifend}

{$if defined(Win32) or defined(Win64)}
procedure TvgSDL2Window.SurfaceWinPlatformCallback(var aWinInstance: TVkHWND; var aModInstance: TVkHINSTANCE);
var
  Info : TSDL_SysWMinfo;
begin
  aWinInstance := 0;
  aModInstance := 0;

  CreateSDLWindow;

  FillChar(Info, SizeOf(Info), 0);
  SDL_VERSION(Info.version);
  if (SDL_GetWindowWMInfo(fSDLWindow, @Info) <> 0) and (Info.subsystem = SDL_SYSWM_WINDOWS) then
  begin
    aWinInstance := TVkHWND(Info.window);
    aModInstance := TVkHINSTANCE(Info.hinstance);
  end;
end;
{$ifend}

{$if defined(XCB) and defined(Unix)}
procedure TvgSDL2Window.SurfaceWinPlatformCallback(var aConnection: PVkXCBConnection; var aWindow: TVkXCBWindow);
begin
  aConnection := nil;
  aWindow     := 0;
end;
{$ifend}

{$if defined(XLIB) and defined(Unix)}
procedure TvgSDL2Window.SurfaceWinPlatformCallback(var aDisplay: PVkXLIBDisplay; var aWindow: TVkXLIBWindow);
begin
  aDisplay := nil;
  aWindow  := 0;
end;
{$ifend}

{$if defined(MoltenVK_IOS) and defined(Darwin)}
procedure TvgSDL2Window.SurfaceWinPlatformCallback(var aView: PVkVoid);
begin
  aView := nil;
end;
{$ifend}

{$if defined(MoltenVK_MacOS) and defined(Darwin)}
procedure TvgSDL2Window.SurfaceWinPlatformCallback(var aView: PVkVoid);
begin
  aView := nil;
end;
{$ifend}

initialization
  RegisterClass(TvgSDL2Window);

finalization
  //windows not freed by their owners (should not happen)
  while Assigned(TvgSDL2Window.fWindows) and (TvgSDL2Window.fWindows.Count > 0) do
    TvgSDL2Window.fWindows[0].DestroySDLWindow;

end.
