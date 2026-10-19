{ TvgWindowFMX

  Presents a Vulkan session in a FireMonkey form - the FMX counterpart of
  TvgWindowVCL.  Drop it on a form and connect it to a linker the same way:

      VulkanWindow1.VulkanLink := Linker1;   //or Linker1.WindowIntf := VulkanWindow1
      Instance1.Active := True;              //starts the session

  FMX controls are not native windows: the whole form is one window that FMX
  draws itself.  Vulkan needs a native window to present to, so this control
  owns one and keeps it over its own area.

  Windows: a child HWND of the form's window, moved and sized with the
  control (Resize, DoAbsoluteChanged, Paint) and hidden with it.  It takes
  the mouse, wheel and keys over its area and forwards them to the linker
  (and so to its tool manager), with the same capture and screen-edge wrap
  as TvgWindowVCL.  Keys the linker does not use go on to the form.

  Android: an android.view.SurfaceView, kept over the control by the form's
  TAndroidZOrderManager (as FMX's own native controls are) and placed above
  the form's own SurfaceView (setZOrderMediaOverlay).  Android makes and
  destroys the view's surface itself - when the view is attached, and each
  time the app goes to the background and back.  So:
  - the session can only start once the surface exists: start it from
    OnNativeReady (or once NativeReady is True), not from FormCreate;
  - when the surface goes, this window's linker is stopped (its surface and
    swap chain freed) and, if it was running, started again when the surface
    comes back.
  Touch: one finger is a left-button drag (orbit), two fingers pinch to
  zoom (as the mouse wheel).  Shaders cannot be compiled on the device:
  ship prebuilt .spv.

  iOS, macOS: not done yet.  The platform callbacks return nothing, so no
  surface is made.

  Limits that come with a native child window:
  - it is always drawn above the form's FMX controls (popups, menus and
    controls placed over it are hidden behind it);
  - it is not clipped by FMX parents (a TScrollBox, a TLayout with
    ClipChildren); keep it in an unclipped area;
  - forms with Transparency True cannot host it;
  - no Vulkan at design time: the designer shows a placeholder. }

unit Vulkan_WindowFMX;

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  System.UITypes,
{$IFDEF MSWINDOWS}
  Winapi.Windows,
  Winapi.Messages,
  Winapi.MultiMon,
{$ENDIF}
{$IFDEF ANDROID}
  System.Messaging,
  Androidapi.JNIBridge,
  Androidapi.JNI.GraphicsContentViewText,
  Androidapi.NativeWindow,
{$ENDIF}
  FMX.Types,
  FMX.Controls,
  FMX.Graphics,
  FMX.Forms,
  Vulkan,
  PasVulkan.Types,
  Vulkan_Components,
  Vulkan_Assert,
  Vulkan_Components_Lookups
{$IFDEF MSWINDOWS}
  , FMX.Platform.Win
{$ENDIF}
{$IFDEF ANDROID}
  , System.Math,
  System.Generics.Collections,
  Androidapi.JNI.JavaTypes,
  Androidapi.JNI.Widget,
  Androidapi.Helpers,
  Androidapi.NativeWindowJni,
  FMX.Platform.Android,
  FMX.Platform.UI.Android,
  FMX.ZOrder.Android
{$ENDIF}
  ;

type

  TvgWindowFMX = class(TControl, IvgVulkanWindow)
  private
    fLinker       : TvgLinker;
    fVulkanActive : Boolean;
    fClearColor   : TAlphaColor;
    fMouseCapture : Boolean;
    fOnNativeReady : TNotifyEvent;

{$IFDEF MSWINDOWS}
    fWnd          : HWND;
    fWndBounds    : TRect;          //last bounds given to fWnd, in form pixels
    fWndShown     : Boolean;

    // Captured-drag state, as TvgWindowVCL: while any button is held the
    // window owns the mouse; positions are read in screen space and wrap at
    // the monitor edge, fWrapOffset absorbing the jump.
    fCaptureButtons : set of TvgMouseButton;
    fWrapOffset     : TPoint;

    function  FormWnd: HWND;
    function  FormScale: Single;
    procedure CreateNativeWindow;
    procedure DestroyNativeWindow;
    procedure NativeWindowCreated;
    procedure NativeWindowDestroyed;
    procedure UpdateNativeBounds;

    function  CapturedClientPos: TPoint;
    procedure WrapCursorAtScreenEdge;
    procedure EndCapture;
    procedure CaptureLost;
    procedure DoNativeMouseDown(aButton: TvgMouseButton; aWParam: WPARAM; aLParam: LPARAM);
    procedure DoNativeMouseUp(aButton: TvgMouseButton; aWParam: WPARAM; aLParam: LPARAM);
    procedure DoNativeMouseMove(aWParam: WPARAM; aLParam: LPARAM);
    function  WndProc(aMsg: UINT; aWParam: WPARAM; aLParam: LPARAM): LRESULT;
{$ENDIF}

{$IFDEF ANDROID}
  var
    fLayout          : JViewGroup;      //what the z-order manager places
    fChildrenLayout  : JViewGroup;
    fSurfaceView     : JSurfaceView;
    fSurfaceCallback : JSurfaceHolder_Callback;
    fTouchListener   : JView_OnTouchListener;
    [Weak] fViewForm : TCommonCustomForm;   //the form fLayout is linked into
    fNativeWindow    : Androidapi.NativeWindow.PANativeWindow;  //while the surface exists
    fSurfaceWidth,
    fSurfaceHeight   : Integer;
    fResumeActive    : Boolean;         //restart the linker when the surface returns
    fRepaintQueued   : Boolean;

    // Touch: one finger drags with the left button, two pinch (wheel)
    fTouchDown       : Boolean;
    fPinching        : Boolean;
    fPinchDistance   : Single;
    fPinchRemainder  : Single;

    function  ViewForm: TCommonCustomForm;
    procedure CreateNativeView;
    procedure DestroyNativeView;
    procedure UpdateNativeBounds;
    procedure BeforeDestroyFormHandle(const Sender: TObject; const M: TMessage);

    procedure SurfaceCreated(const aHolder: JSurfaceHolder);
    procedure SurfaceChanged(aWidth, aHeight: Integer);
    procedure SurfaceDestroyed;
    function  Touch(const aEvent: JMotionEvent): Boolean;
{$ENDIF}

    procedure NativeReadyChanged;

    function  GetClearColor: TAlphaColor;
    procedure SetClearColor(const Value: TAlphaColor);
    function  GetLinker: TvgLinker;
    procedure SetLinker(const Value: TvgLinker);
    function  GetActive: Boolean;
    procedure SetActive(const Value: Boolean);
    function  GetNativeReady: Boolean;

  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;

    procedure Paint; override;
    procedure Resize; override;
    procedure DoAbsoluteChanged; override;
    procedure VisibleChanged; override;
    procedure AncestorVisibleChanged(const Visible: Boolean); override;
    procedure ParentChanged; override;

  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    // IvgVulkanWindow
    procedure SetDisabled;
    procedure SetDesigning; reintroduce;
    procedure SetEnabled(aComp: TvgBaseComponent = nil); reintroduce;
    procedure DisableParent(ToRoot: Boolean = False);

    procedure vgWindowSizeCallback(var WinWidth, WinHeight: TvkUint32);  //pixels
    procedure vgWindowInvalidate(DoPaint: Boolean);
    procedure vgWindowBackgroundColor(var aColor: TVkClearValue);
    function  vgWindowGetSurface(var aSurface: TVkSurfaceKHR): Boolean;
    function  vgCrossHairON: Boolean;

{$if defined(Android)}
    procedure SurfaceWinPlatformCallback(var aWindow: PVkAndroidANativeWindow);
{$endif}
{$if defined(Wayland) and defined(Unix)}
    procedure SurfaceWinPlatformCallback(var aDisplay: PVkWaylandDisplay; var aSurface: PVkWaylandSurface);
{$endif}
{$if defined(Win32) or defined(Win64)}
    procedure SurfaceWinPlatformCallback(var aWinInstance: TVkHWND; var aModInstance: TVkHINSTANCE);
{$endif}
{$if defined(XCB) and defined(Unix)}
    procedure SurfaceWinPlatformCallback(var aConnection: PVkXCBConnection; var aWindow: TVkXCBWindow);
{$endif}
{$if defined(XLIB) and defined(Unix)}
    procedure SurfaceWinPlatformCallback(var aDisplay: PVkXLIBDisplay; var aWindow: TVkXLIBWindow);
{$endif}
{$if defined(MoltenVK_IOS) and defined(Darwin)}
    procedure SurfaceWinPlatformCallback(var aView: PVkVoid);
{$endif}
{$if defined(MoltenVK_MacOS) and defined(Darwin)}
    procedure SurfaceWinPlatformCallback(var aView: PVkVoid);
{$endif}

    // True once the native window exists (the counterpart of HandleAllocated)
    property NativeReady : Boolean read GetNativeReady;

  published
    property Active     : Boolean read GetActive write SetActive stored False;  //don't store this value
    property ClearColor : TAlphaColor read GetClearColor write SetClearColor default TAlphaColors.Black;
    property VulkanLink : TvgLinker read GetLinker write SetLinker;

    // When True a drag keeps the mouse until the last button is released
    property MouseCapture : Boolean read fMouseCapture write fMouseCapture default True;

    // The native window has just been made (NativeReady became True).  On
    // Android the surface appears some time after the form is shown, and
    // again after the app returns from the background: start the session
    // from here.
    property OnNativeReady : TNotifyEvent read fOnNativeReady write fOnNativeReady;

    property Align;
    property Anchors;
    property Cursor;
    property Height;
    property Margins;
    property Position;
    property Size;
    property Visible;
    property Width;
  end;

implementation

{$IFDEF MSWINDOWS}
const
  cWndClassName = 'TvgWindowFMX';

var
  gWndClassRegistered : Boolean = False;

function vgFMXWndProc(aWnd: HWND; aMsg: UINT; aWParam: WPARAM; aLParam: LPARAM): LRESULT; stdcall;
var
  W : TvgWindowFMX;
begin
  W := TvgWindowFMX(GetWindowLongPtr(aWnd, GWLP_USERDATA));
  if Assigned(W) and (W.fWnd = aWnd) then
  try
    Result := W.WndProc(aMsg, aWParam, aLParam);
  except
    //an exception must not leave a window procedure: the process would end
    Application.HandleException(W);
    Result := 0;
  end
  else
    Result := DefWindowProc(aWnd, aMsg, aWParam, aLParam);
end;

procedure RegisterWndClass;
var
  WC : TWndClassEx;
begin
  if gWndClassRegistered then exit;

  FillChar(WC, SizeOf(WC), 0);
  WC.cbSize        := SizeOf(WC);
  WC.style         := CS_VREDRAW or CS_HREDRAW or CS_DBLCLKS or CS_OWNDC;
  WC.lpfnWndProc   := @vgFMXWndProc;
  WC.hInstance     := HInstance;
  WC.hCursor       := LoadCursor(0, IDC_ARROW);
  WC.hbrBackground := 0;            //Vulkan paints every pixel: no erase
  WC.lpszClassName := cWndClassName;

  if Winapi.Windows.RegisterClassEx(WC) = 0 then
    RaiseLastOSError;
  gWndClassRegistered := True;
end;

function vgMouseShift(aWParam: WPARAM): TShiftState;
begin
  Result := [];
  if (aWParam and MK_SHIFT)   <> 0 then Include(Result, ssShift);
  if (aWParam and MK_CONTROL) <> 0 then Include(Result, ssCtrl);
  if GetKeyState(VK_MENU) < 0      then Include(Result, ssAlt);
  if (aWParam and MK_LBUTTON) <> 0 then Include(Result, ssLeft);
  if (aWParam and MK_MBUTTON) <> 0 then Include(Result, ssMiddle);
  if (aWParam and MK_RBUTTON) <> 0 then Include(Result, ssRight);
end;

function vgKeyShift: TShiftState;
begin
  Result := [];
  if GetKeyState(VK_SHIFT)   < 0 then Include(Result, ssShift);
  if GetKeyState(VK_CONTROL) < 0 then Include(Result, ssCtrl);
  if GetKeyState(VK_MENU)    < 0 then Include(Result, ssAlt);
end;

function vgLParamPoint(aLParam: LPARAM): TPoint;
begin
  //signed: positions left of or above the window are negative while captured
  Result.X := SmallInt(LoWord(aLParam));
  Result.Y := SmallInt(HiWord(aLParam));
end;
{$ENDIF}

{$IFDEF ANDROID}
const
  // Pinch distance, in pixels, that counts as one wheel notch
  cPinchPixelsPerNotch = 40;
  cWheelNotch          = 120;

type
  // Java callbacks.  They arrive on the Android UI thread, which is the
  // thread FMX runs on, so they may call the window directly.
  TvgSurfaceCallback = class(TJavaLocal, JSurfaceHolder_Callback)
  private
    [Weak] fOwner : TvgWindowFMX;
  public
    constructor Create(aOwner: TvgWindowFMX);
    procedure surfaceChanged(holder: JSurfaceHolder; format: Integer; width: Integer; height: Integer); cdecl;
    procedure surfaceCreated(holder: JSurfaceHolder); cdecl;
    procedure surfaceDestroyed(holder: JSurfaceHolder); cdecl;
  end;

  TvgTouchListener = class(TJavaLocal, JView_OnTouchListener)
  private
    [Weak] fOwner : TvgWindowFMX;
  public
    constructor Create(aOwner: TvgWindowFMX);
    function onTouch(v: JView; event: JMotionEvent): Boolean; cdecl;
  end;

var
  // Windows still alive, so a queued repaint can tell its window has gone
  gLiveWindows : TList<TvgWindowFMX> = nil;

constructor TvgSurfaceCallback.Create(aOwner: TvgWindowFMX);
begin
  inherited Create;
  fOwner := aOwner;
end;

procedure TvgSurfaceCallback.surfaceChanged(holder: JSurfaceHolder; format, width, height: Integer);
begin
  if Assigned(fOwner) then
  try
    fOwner.SurfaceChanged(width, height);
  except
    Application.HandleException(fOwner);
  end;
end;

procedure TvgSurfaceCallback.surfaceCreated(holder: JSurfaceHolder);
begin
  if Assigned(fOwner) then
  try
    fOwner.SurfaceCreated(holder);
  except
    Application.HandleException(fOwner);
  end;
end;

procedure TvgSurfaceCallback.surfaceDestroyed(holder: JSurfaceHolder);
begin
  //Android frees the surface as soon as this returns: everything made on it
  //must be gone by then
  if Assigned(fOwner) then
  try
    fOwner.SurfaceDestroyed;
  except
    Application.HandleException(fOwner);
  end;
end;

constructor TvgTouchListener.Create(aOwner: TvgWindowFMX);
begin
  inherited Create;
  fOwner := aOwner;
end;

function TvgTouchListener.onTouch(v: JView; event: JMotionEvent): Boolean;
begin
  Result := False;
  if Assigned(fOwner) then
  try
    Result := fOwner.Touch(event);
  except
    Application.HandleException(fOwner);
  end;
end;

function vgPinchDistance(const aEvent: JMotionEvent): Single;
begin
  Result := Hypot(aEvent.getX(1) - aEvent.getX(0), aEvent.getY(1) - aEvent.getY(0));
end;
{$ENDIF}

{ TvgWindowFMX }

constructor TvgWindowFMX.Create(AOwner: TComponent);
begin
  inherited;
  fClearColor   := TAlphaColors.Black;
  fMouseCapture := True;
  CanFocus      := True;
  HitTest       := True;
  Width         := 200;
  Height        := 150;

{$IFDEF ANDROID}
  if not Assigned(gLiveWindows) then
    gLiveWindows := TList<TvgWindowFMX>.Create;
  gLiveWindows.Add(Self);
  TMessageManager.DefaultManager.SubscribeToMessage(TBeforeDestroyFormHandle, BeforeDestroyFormHandle);
{$ENDIF}
end;

destructor TvgWindowFMX.Destroy;
begin
{$IFDEF MSWINDOWS}
  DestroyNativeWindow;
{$ENDIF}
{$IFDEF ANDROID}
  TMessageManager.DefaultManager.Unsubscribe(TBeforeDestroyFormHandle, BeforeDestroyFormHandle);
  DestroyNativeView;
  if Assigned(gLiveWindows) then
  begin
    gLiveWindows.Remove(Self);
    if gLiveWindows.Count = 0 then
      FreeAndNil(gLiveWindows);
  end;
{$ENDIF}

  if Assigned(fLinker) then
  begin
    fLinker.WindowIntf := nil;
    fLinker            := nil;
  end;

  inherited;
end;

{$IFDEF MSWINDOWS}

function TvgWindowFMX.FormWnd: HWND;
begin
  Result := 0;
  if not Assigned(Root) or not (Root.GetObject is TCommonCustomForm) then exit;
  if not Assigned(TCommonCustomForm(Root.GetObject).Handle) then exit;
  Result := FormToHWND(TCommonCustomForm(Root.GetObject));
end;

function TvgWindowFMX.FormScale: Single;
begin
  Result := 1;
  if Assigned(Root) and (Root.GetObject is TCommonCustomForm) and
     Assigned(TCommonCustomForm(Root.GetObject).Handle) then
    Result := TCommonCustomForm(Root.GetObject).Handle.Scale;
  if Result <= 0 then
    Result := 1;
end;

procedure TvgWindowFMX.CreateNativeWindow;
var
  Parent : HWND;
begin
  if fWnd <> 0 then
  begin
    //the form recreated its window: ours went with the old one
    if IsWindow(fWnd) then exit;
    NativeWindowDestroyed;
  end;
  if csDesigning in ComponentState then exit;

  Parent := FormWnd;
  if Parent = 0 then exit;    //not on a form yet, or its window not made yet

  RegisterWndClass;

  fWndBounds := TRect.Empty;
  fWndShown  := False;
  fWnd := CreateWindowEx(0, cWndClassName, '',
                         WS_CHILD or WS_CLIPCHILDREN or WS_CLIPSIBLINGS or WS_TABSTOP,
                         0, 0, 1, 1, Parent, 0, HInstance, nil);
  if fWnd = 0 then
    RaiseLastOSError;

  SetWindowLongPtr(fWnd, GWLP_USERDATA, LONG_PTR(Self));
  UpdateNativeBounds;
  NativeWindowCreated;
end;

procedure TvgWindowFMX.DestroyNativeWindow;
var
  W : HWND;
begin
  if fWnd = 0 then exit;
  W := fWnd;
  if IsWindow(W) then
    DestroyWindow(W)          //WM_DESTROY runs NativeWindowDestroyed
  else
    NativeWindowDestroyed;
end;

procedure TvgWindowFMX.NativeWindowCreated;
begin
  //as TvgWindowVCL.CreateHandle
  if Assigned(fLinker) then
  begin
    fLinker.WindowReady        := True;
    fLinker.NeedSurfaceRebuild := True;
    fLinker.FlagSwapChainRebuild;
  end;
  NativeReadyChanged;
end;

procedure TvgWindowFMX.NativeWindowDestroyed;
begin
  //as TvgWindowVCL.WMDestroy: the surface made on the window is no longer
  //valid, so the session stops.  The link stays: the next Paint makes a new
  //window and reconnects it.
  if Assigned(fLinker) then
  begin
    if fLinker.Active then
      DisableParent(True);
    fLinker.WindowReady        := False;
    fLinker.NeedSurfaceRebuild := False;
  end;

  if fWnd <> 0 then
    SetWindowLongPtr(fWnd, GWLP_USERDATA, 0);
  fWnd            := 0;
  fWndShown       := False;
  fCaptureButtons := [];
  fWrapOffset     := Point(0, 0);
end;

procedure TvgWindowFMX.UpdateNativeBounds;
var
  R     : TRectF;
  S     : Single;
  P     : TRect;
  Show  : Boolean;
begin
  if (fWnd = 0) or not IsWindow(fWnd) then exit;

  if FormWnd = 0 then
  begin
    //between parents: keep the window where it is, out of sight
    if fWndShown then
      ShowWindow(fWnd, SW_HIDE);
    fWndShown := False;
    exit;
  end;

  S := FormScale;
  R := AbsoluteRect;            //form client area, logical units
  P := Rect(Round(R.Left * S), Round(R.Top * S), Round(R.Right * S), Round(R.Bottom * S));
  if P.Width  < 1 then P.Right  := P.Left + 1;
  if P.Height < 1 then P.Bottom := P.Top + 1;

  if P <> fWndBounds then
  begin
    fWndBounds := P;
    SetWindowPos(fWnd, HWND_TOP, P.Left, P.Top, P.Width, P.Height,
                 SWP_NOACTIVATE or SWP_NOOWNERZORDER);
  end;

  Show := ParentedVisible and (FormWnd <> 0);
  if Show <> fWndShown then
  begin
    fWndShown := Show;
    if Show then
      ShowWindow(fWnd, SW_SHOWNA)
    else
      ShowWindow(fWnd, SW_HIDE);
  end;
end;

function TvgWindowFMX.CapturedClientPos: TPoint;
begin
  GetCursorPos(Result);
  ScreenToClient(fWnd, Result);
  Inc(Result.X, fWrapOffset.X);
  Inc(Result.Y, fWrapOffset.Y);
end;

procedure TvgWindowFMX.WrapCursorAtScreenEdge;
// As TvgWindowVCL: at an outer edge of the monitor move the cursor to the
// opposite edge and record the jump, so a drag (orbit) is unbounded.
const
  EDGE   = 1;
  MARGIN = 8;
var
  Pt, NewPt : TPoint;
  Mon       : HMONITOR;
  MI        : TMonitorInfo;
  R         : TRect;

  function NoMonitorAt(aX, aY: Integer): Boolean;
  begin
    Result := MonitorFromPoint(Point(aX, aY), MONITOR_DEFAULTTONULL) = 0;
  end;

begin
  GetCursorPos(Pt);
  Mon := MonitorFromPoint(Pt, MONITOR_DEFAULTTONEAREST);
  MI.cbSize := SizeOf(MI);
  if not GetMonitorInfo(Mon, @MI) then exit;
  R := MI.rcMonitor;

  NewPt := Pt;

  if (Pt.X <= R.Left + EDGE) and NoMonitorAt(R.Left - 1, Pt.Y) then
    NewPt.X := R.Right - 1 - MARGIN
  else
  if (Pt.X >= R.Right - 1 - EDGE) and NoMonitorAt(R.Right, Pt.Y) then
    NewPt.X := R.Left + MARGIN;

  if (Pt.Y <= R.Top + EDGE) and NoMonitorAt(Pt.X, R.Top - 1) then
    NewPt.Y := R.Bottom - 1 - MARGIN
  else
  if (Pt.Y >= R.Bottom - 1 - EDGE) and NoMonitorAt(Pt.X, R.Bottom) then
    NewPt.Y := R.Top + MARGIN;

  if (NewPt.X = Pt.X) and (NewPt.Y = Pt.Y) then exit;

  SetCursorPos(NewPt.X, NewPt.Y);
  GetCursorPos(NewPt);

  Inc(fWrapOffset.X, Pt.X - NewPt.X);
  Inc(fWrapOffset.Y, Pt.Y - NewPt.Y);
end;

procedure TvgWindowFMX.EndCapture;
begin
  fCaptureButtons := [];
  fWrapOffset     := Point(0, 0);
  if GetCapture = fWnd then
    ReleaseCapture;
end;

procedure TvgWindowFMX.CaptureLost;
// Capture taken away mid-drag (Alt+Tab, a modal dialog ...).  No button-up
// will arrive, so release the held buttons here.
var
  B : TvgMouseButton;
  P : TPoint;
begin
  if fCaptureButtons = [] then exit;

  P := CapturedClientPos;
  if Assigned(fLinker) then
    for B in fCaptureButtons do
      fLinker.MouseUp(B, [], P.X, P.Y);

  fCaptureButtons := [];
  fWrapOffset     := Point(0, 0);
end;

procedure TvgWindowFMX.DoNativeMouseDown(aButton: TvgMouseButton; aWParam: WPARAM; aLParam: LPARAM);
var
  P : TPoint;
begin
  //a click gives the window focus, so the keys that follow go to its tools
  if GetFocus <> fWnd then
    Winapi.Windows.SetFocus(fWnd);

  if not Assigned(fLinker) then exit;

  P := vgLParamPoint(aLParam);
  if fMouseCapture then
  begin
    if fCaptureButtons = [] then
    begin
      fWrapOffset := Point(0, 0);
      SetCapture(fWnd);
    end
    else
      P := CapturedClientPos;   //extra button during a drag
    Include(fCaptureButtons, aButton);
  end;

  fLinker.MouseDown(aButton, vgMouseShift(aWParam), P.X, P.Y);
end;

procedure TvgWindowFMX.DoNativeMouseUp(aButton: TvgMouseButton; aWParam: WPARAM; aLParam: LPARAM);
var
  P : TPoint;
begin
  if fCaptureButtons <> [] then
    P := CapturedClientPos
  else
    P := vgLParamPoint(aLParam);

  if Assigned(fLinker) then
    fLinker.MouseUp(aButton, vgMouseShift(aWParam), P.X, P.Y);

  Exclude(fCaptureButtons, aButton);
  if fCaptureButtons = [] then
    EndCapture;
end;

procedure TvgWindowFMX.DoNativeMouseMove(aWParam: WPARAM; aLParam: LPARAM);
var
  P : TPoint;
begin
  if not Assigned(fLinker) then exit;

  if fCaptureButtons <> [] then
  begin
    P := CapturedClientPos;
    fLinker.MouseMove(vgMouseShift(aWParam), P.X, P.Y);
    WrapCursorAtScreenEdge;
  end
  else
  begin
    P := vgLParamPoint(aLParam);
    fLinker.MouseMove(vgMouseShift(aWParam), P.X, P.Y);
  end;
end;

function TvgWindowFMX.WndProc(aMsg: UINT; aWParam: WPARAM; aLParam: LPARAM): LRESULT;
var
  PS    : TPaintStruct;
  Key   : Word;
  W     : HWND;
  C     : TAlphaColorRec;
  Brush : HBRUSH;
begin
  Result := 0;
  case aMsg of
    WM_PAINT:
      begin
        BeginPaint(fWnd, PS);
        if not (Assigned(fLinker) and fLinker.Active) then
        begin
          //no session presenting: show the clear colour, not stale pixels
          C.Color := fClearColor;
          Brush   := CreateSolidBrush(RGB(C.R, C.G, C.B));
          FillRect(PS.hdc, PS.rcPaint, Brush);
          DeleteObject(Brush);
        end;
        EndPaint(fWnd, PS);
        if Assigned(fLinker) and fLinker.Active then
          fLinker.TriggerWindowRepaint;
      end;

    WM_ERASEBKGND:
      Result := 1;

    WM_SIZE:
      begin
        if Assigned(fLinker) and fLinker.Active then
          fLinker.FlagSwapChainRebuild;
        Result := DefWindowProc(fWnd, aMsg, aWParam, aLParam);
      end;

    WM_SETCURSOR:
      if (LoWord(aLParam) = HTCLIENT) and (Cursor = crNone) then
      begin
        Winapi.Windows.SetCursor(0);
        Result := 1;
      end
      else
        Result := DefWindowProc(fWnd, aMsg, aWParam, aLParam);

    WM_MOUSEACTIVATE:
      Result := MA_ACTIVATE;

    WM_LBUTTONDOWN, WM_LBUTTONDBLCLK : DoNativeMouseDown(vgmbLeft,   aWParam, aLParam);
    WM_MBUTTONDOWN, WM_MBUTTONDBLCLK : DoNativeMouseDown(vgmbMiddle, aWParam, aLParam);
    WM_RBUTTONDOWN, WM_RBUTTONDBLCLK : DoNativeMouseDown(vgmbRight,  aWParam, aLParam);
    WM_LBUTTONUP : DoNativeMouseUp(vgmbLeft,   aWParam, aLParam);
    WM_MBUTTONUP : DoNativeMouseUp(vgmbMiddle, aWParam, aLParam);
    WM_RBUTTONUP : DoNativeMouseUp(vgmbRight,  aWParam, aLParam);
    WM_MOUSEMOVE : DoNativeMouseMove(aWParam, aLParam);

    WM_MOUSEWHEEL:
      if Assigned(fLinker) then
        fLinker.MouseWheel(vgMouseShift(LoWord(aWParam)), SmallInt(HiWord(aWParam)));

    WM_CAPTURECHANGED:
      if HWND(aLParam) <> fWnd then
        CaptureLost;

    WM_GETDLGCODE:
      Result := DLGC_WANTARROWS or DLGC_WANTALLKEYS or DLGC_WANTCHARS;

    WM_KEYDOWN:
      begin
        //Windows virtual-key codes are the VGK_* codes the tool manager expects
        Key := Word(aWParam);
        if Assigned(fLinker) and fLinker.KeyDown(Key, vgKeyShift) then
          exit;     //used: the form does not see it
        W := FormWnd;
        if W <> 0 then
          Result := SendMessage(W, aMsg, aWParam, aLParam);
      end;

    WM_KEYUP, WM_CHAR, WM_SYSKEYDOWN, WM_SYSKEYUP, WM_SYSCHAR:
      begin
        //the form's shortcuts and focused-control keys still work
        W := FormWnd;
        if W <> 0 then
          Result := SendMessage(W, aMsg, aWParam, aLParam)
        else
          Result := DefWindowProc(fWnd, aMsg, aWParam, aLParam);
      end;

    WM_DESTROY:
      begin
        W := fWnd;               //NativeWindowDestroyed clears fWnd
        NativeWindowDestroyed;
        Result := DefWindowProc(W, aMsg, aWParam, aLParam);
      end;
  else
    Result := DefWindowProc(fWnd, aMsg, aWParam, aLParam);
  end;
end;

{$ENDIF}

{$IFDEF ANDROID}

function TvgWindowFMX.ViewForm: TCommonCustomForm;
begin
  Result := nil;
  if Assigned(Root) and (Root.GetObject is TCommonCustomForm) then
    Result := TCommonCustomForm(Root.GetObject);
end;

procedure TvgWindowFMX.CreateNativeView;
var
  F      : TCommonCustomForm;
  Params : JRelativeLayout_LayoutParams;
begin
  if Assigned(fSurfaceView) then exit;
  if csDesigning in ComponentState then exit;

  F := ViewForm;
  if not Assigned(F) or not Assigned(F.Handle) then exit;   //no form, or its view not made yet

  //as TAndroidNativeView: a layout holding the view, which the form's
  //z-order manager places over the control
  fLayout := TJRelativeLayout.JavaClass.init(TAndroidHelper.Context);

  fSurfaceView := TJSurfaceView.JavaClass.init(TAndroidHelper.Activity);
  //the form draws on a SurfaceView too; this puts ours above it
  fSurfaceView.setZOrderMediaOverlay(True);

  fSurfaceCallback := TvgSurfaceCallback.Create(Self);
  fSurfaceView.getHolder.addCallback(fSurfaceCallback);
  fTouchListener := TvgTouchListener.Create(Self);
  fSurfaceView.setOnTouchListener(fTouchListener);

  Params := TJRelativeLayout_LayoutParams.JavaClass.init(TJViewGroup_LayoutParams.JavaClass.MATCH_PARENT,
                                                         TJViewGroup_LayoutParams.JavaClass.MATCH_PARENT);
  fLayout.addView(fSurfaceView, Params);

  fChildrenLayout := TJRelativeLayout.JavaClass.init(TAndroidHelper.Context);
  fChildrenLayout.setFocusable(False);
  Params := TJRelativeLayout_LayoutParams.JavaClass.init(TJViewGroup_LayoutParams.JavaClass.MATCH_PARENT,
                                                         TJViewGroup_LayoutParams.JavaClass.MATCH_PARENT);
  fLayout.addView(fChildrenLayout, Params);

  fViewForm := F;
  WindowHandleToPlatform(F.Handle).ZOrderManager.AddOrSetLink(Self, fLayout, fChildrenLayout);
  UpdateNativeBounds;
  //the surface follows, in SurfaceCreated, once Android has laid the view out
end;

procedure TvgWindowFMX.DestroyNativeView;
begin
  if not Assigned(fSurfaceView) then exit;

  //removing the view destroys its surface (SurfaceDestroyed); make sure the
  //session is off it even if Android does not call back
  SurfaceDestroyed;

  if Assigned(fViewForm) and Assigned(fViewForm.Handle) then
    WindowHandleToPlatform(fViewForm.Handle).ZOrderManager.RemoveLink(Self);
  fViewForm := nil;

  fSurfaceView.setOnTouchListener(nil);
  fSurfaceView.getHolder.removeCallback(fSurfaceCallback);
  fSurfaceView     := nil;
  fSurfaceCallback := nil;
  fTouchListener   := nil;
  fChildrenLayout  := nil;
  fLayout          := nil;
  fResumeActive    := False;
end;

procedure TvgWindowFMX.UpdateNativeBounds;
begin
  if not Assigned(fLayout) then exit;

  //as TAndroidNativeView.UpdateVisible
  if not Visible or not ParentedVisible or (ViewForm <> fViewForm) then
    fLayout.setVisibility(TJView.JavaClass.GONE)
  else if Assigned(fViewForm) and Assigned(fViewForm.Handle) then
    WindowHandleToPlatform(fViewForm.Handle).ZOrderManager.UpdateOrderAndBounds(Self);
end;

procedure TvgWindowFMX.BeforeDestroyFormHandle(const Sender: TObject; const M: TMessage);
begin
  //the form's views are going: ours with them.  Paint makes new ones on the
  //form's next view.
  if (M is TBeforeDestroyFormHandle) and (TBeforeDestroyFormHandle(M).Value = fViewForm) then
    DestroyNativeView;
end;

procedure TvgWindowFMX.SurfaceCreated(const aHolder: JSurfaceHolder);
var
  S : JSurface;
begin
  if Assigned(fNativeWindow) then exit;

  S := aHolder.getSurface;
  if not Assigned(S) then exit;
  fNativeWindow := ANativeWindow_fromSurface(TJNIResolver.GetJNIEnv, (S as ILocalObject).GetObjectID);
  if not Assigned(fNativeWindow) then exit;

  fSurfaceWidth  := ANativeWindow_getWidth(fNativeWindow);
  fSurfaceHeight := ANativeWindow_getHeight(fNativeWindow);

  if Assigned(fLinker) then
  begin
    fLinker.WindowReady        := True;
    fLinker.NeedSurfaceRebuild := True;
    fLinker.FlagSwapChainRebuild;

    //back from the background: the linker was running on the old surface
    if fResumeActive then
    begin
      fResumeActive := False;
      if Assigned(fLinker.ScreenDevice) and Assigned(fLinker.ScreenDevice.Instance) and
         fLinker.ScreenDevice.Instance.Active and not fLinker.Active then
        fLinker.Active := True;
    end;
  end;

  NativeReadyChanged;
end;

procedure TvgWindowFMX.SurfaceChanged(aWidth, aHeight: Integer);
begin
  fSurfaceWidth  := aWidth;
  fSurfaceHeight := aHeight;
  if Assigned(fLinker) and fLinker.Active then
  begin
    fLinker.FlagSwapChainRebuild;
    fLinker.TriggerWindowRepaint;
  end;
end;

procedure TvgWindowFMX.SurfaceDestroyed;
begin
  if not Assigned(fNativeWindow) then exit;

  //as TvgSDL2Window.DestroySDLWindow: stopping this window's linker frees
  //its surface and swap chain; the instance and device keep running, so it
  //can start again on the next surface
  if Assigned(fLinker) then
  begin
    if fLinker.Active then
    begin
      fResumeActive := True;
      fLinker.Active := False;
    end;
    fLinker.WindowReady        := False;
    fLinker.NeedSurfaceRebuild := False;
  end;
  fVulkanActive := False;

  ANativeWindow_release(fNativeWindow);
  fNativeWindow := nil;
  fTouchDown    := False;
  fPinching     := False;
end;

function TvgWindowFMX.Touch(const aEvent: JMotionEvent): Boolean;
var
  Action : Integer;
  D      : Single;
  Notches: Integer;
begin
  Result := True;   //the view takes every touch on it
  if not Assigned(fLinker) then exit;

  Action := aEvent.getActionMasked;

  if Action = TJMotionEvent.JavaClass.ACTION_DOWN then
  begin
    fTouchDown := True;
    fPinching  := False;
    fLinker.MouseMove([], Round(aEvent.getX), Round(aEvent.getY));
    fLinker.MouseDown(vgmbLeft, [ssLeft], Round(aEvent.getX), Round(aEvent.getY));
  end
  else if Action = TJMotionEvent.JavaClass.ACTION_POINTER_DOWN then
  begin
    //a second finger: end the drag, start pinching
    if fTouchDown then
      fLinker.MouseUp(vgmbLeft, [], Round(aEvent.getX(0)), Round(aEvent.getY(0)));
    fTouchDown := False;
    if aEvent.getPointerCount >= 2 then
    begin
      fPinching       := True;
      fPinchDistance  := vgPinchDistance(aEvent);
      fPinchRemainder := 0;
    end;
  end
  else if Action = TJMotionEvent.JavaClass.ACTION_MOVE then
  begin
    if fPinching and (aEvent.getPointerCount >= 2) then
    begin
      D := vgPinchDistance(aEvent);
      fPinchRemainder := fPinchRemainder + (D - fPinchDistance);
      fPinchDistance  := D;
      Notches := Trunc(fPinchRemainder / cPinchPixelsPerNotch);
      if Notches <> 0 then
      begin
        fPinchRemainder := fPinchRemainder - Notches * cPinchPixelsPerNotch;
        fLinker.MouseWheel([], Notches * cWheelNotch);   //spread fingers: wheel forward
      end;
    end
    else if fTouchDown then
      fLinker.MouseMove([ssLeft], Round(aEvent.getX), Round(aEvent.getY));
  end
  else if Action = TJMotionEvent.JavaClass.ACTION_POINTER_UP then
    fPinching := False      //the drag does not resume with the finger left
  else if (Action = TJMotionEvent.JavaClass.ACTION_UP) or
          (Action = TJMotionEvent.JavaClass.ACTION_CANCEL) then
  begin
    if fTouchDown then
      fLinker.MouseUp(vgmbLeft, [], Round(aEvent.getX), Round(aEvent.getY));
    fTouchDown := False;
    fPinching  := False;
  end;
end;

{$ENDIF}

procedure TvgWindowFMX.NativeReadyChanged;
begin
  if NativeReady and Assigned(fOnNativeReady) then
    fOnNativeReady(Self);
end;

function TvgWindowFMX.GetNativeReady: Boolean;
begin
{$IF defined(MSWINDOWS)}
  Result := (fWnd <> 0) and IsWindow(fWnd);
{$ELSEIF defined(ANDROID)}
  Result := Assigned(fNativeWindow);
{$ELSE}
  Result := False;
{$ENDIF}
end;

procedure TvgWindowFMX.Paint;
var
  R : TRectF;
begin
  inherited;

{$IFDEF MSWINDOWS}
  //the form is drawing: make sure our window exists and is in place
  if not (csDesigning in ComponentState) then
  begin
    CreateNativeWindow;
    UpdateNativeBounds;
  end;
{$ENDIF}
{$IFDEF ANDROID}
  //the form is drawing: make sure our view exists and is in place
  if not (csDesigning in ComponentState) then
  begin
    CreateNativeView;
    UpdateNativeBounds;
  end;
{$ENDIF}

  if (csDesigning in ComponentState) or not NativeReady then
  begin
    //placeholder: the designer, or no native window on this platform yet
    R := LocalRect;
    Canvas.Fill.Color := fClearColor;
    Canvas.FillRect(R, 0, 0, AllCorners, AbsoluteOpacity);
    R.Inflate(-1, -1);
    Canvas.Stroke.Kind      := TBrushKind.Solid;
    Canvas.Stroke.Color     := TAlphaColors.Gray;
    Canvas.Stroke.Thickness := 2;
    Canvas.DrawRect(R, 0, 0, AllCorners, AbsoluteOpacity);
    Canvas.Fill.Color := TAlphaColors.Silver;
    Canvas.FillText(LocalRect, 'Vulkan', False, AbsoluteOpacity, [],
                    TTextAlign.Center, TTextAlign.Center);
  end;
end;

procedure TvgWindowFMX.Resize;
begin
  inherited;
{$IF defined(MSWINDOWS) or defined(ANDROID)}
  UpdateNativeBounds;     //WM_SIZE / surfaceChanged flag the swap chain rebuild
{$ENDIF}
end;

procedure TvgWindowFMX.DoAbsoluteChanged;
begin
  inherited;
{$IF defined(MSWINDOWS) or defined(ANDROID)}
  UpdateNativeBounds;
{$ENDIF}
end;

procedure TvgWindowFMX.VisibleChanged;
begin
  inherited;
{$IF defined(MSWINDOWS) or defined(ANDROID)}
  UpdateNativeBounds;
{$ENDIF}
end;

procedure TvgWindowFMX.AncestorVisibleChanged(const Visible: Boolean);
begin
  inherited;
{$IF defined(MSWINDOWS) or defined(ANDROID)}
  UpdateNativeBounds;
{$ENDIF}
end;

procedure TvgWindowFMX.ParentChanged;
begin
  inherited;
{$IFDEF MSWINDOWS}
  //moved to another form: the window has to belong to the new one.  A
  //change of parent passes through no parent at all (FormWnd 0): keep the
  //window and its session then, just hidden until the control is placed.
  if (fWnd <> 0) and (FormWnd <> 0) and (Winapi.Windows.GetParent(fWnd) <> FormWnd) then
    DestroyNativeWindow
  else
    UpdateNativeBounds;
{$ENDIF}
{$IFDEF ANDROID}
  //the same, with the view linked into the form's z-order manager
  if Assigned(fSurfaceView) and (ViewForm <> nil) and (ViewForm <> fViewForm) then
    DestroyNativeView
  else
    UpdateNativeBounds;
{$ENDIF}
end;

procedure TvgWindowFMX.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);

  CustomAssert(Assigned(AComponent), 'aComponent not assigned', Self);

  case Operation of
    opInsert:
      begin
        if not vgLinkable(AComponent) then exit;

        //designer convenience, as TvgWindowVCL: a linker dropped on the
        //form joins an unlinked window
        if (AComponent is TvgLinker) and not Assigned(fLinker) and
           (csDesigning in ComponentState) and
           not (csLoading in ComponentState) and
           not (Assigned(Owner) and (csLoading in Owner.ComponentState)) then
          SetLinker(TvgLinker(AComponent));
      end;

    opRemove:
      if (AComponent is TvgLinker) and (TvgLinker(AComponent) = fLinker) then
        fLinker := nil;
  end;
end;

function TvgWindowFMX.GetActive: Boolean;
begin
  Result := Assigned(fLinker) and fLinker.Active;
end;

procedure TvgWindowFMX.SetActive(const Value: Boolean);
begin
  if GetActive = Value then exit;
  fVulkanActive := False;

{$IFDEF MSWINDOWS}
  if Value then
    CreateNativeWindow;
{$ENDIF}
{$IFDEF ANDROID}
  if Value then
    CreateNativeView;     //the surface itself follows later (OnNativeReady)
{$ENDIF}
  if not NativeReady then exit;

  fVulkanActive := Value;
  if fVulkanActive then
    SetEnabled
  else
    SetDisabled;
end;

function TvgWindowFMX.GetClearColor: TAlphaColor;
begin
  Result := fClearColor;
end;

procedure TvgWindowFMX.SetClearColor(const Value: TAlphaColor);
begin
  if fClearColor = Value then exit;
  fClearColor := Value;

  //live: the render pass and background-dependent stores follow it
  if Assigned(fLinker) then
    fLinker.BackgroundColorChanged;
  Repaint;
end;

function TvgWindowFMX.GetLinker: TvgLinker;
begin
  Result := fLinker;
end;

procedure TvgWindowFMX.SetLinker(const Value: TvgLinker);
var
  OldLinker : TvgLinker;
begin
  if fLinker = Value then exit;

  if Assigned(fLinker) then
  begin
    OldLinker := fLinker;
    fLinker   := nil;
    OldLinker.RemoveFreeNotification(Self);
    //as TvgWindowVCL.SetLinker
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

      if NativeReady then
        fLinker.WindowReady := True;

      if fLinker.Active then
      begin
        fLinker.NeedSurfaceRebuild := True;
        fLinker.FlagSwapChainRebuild;
      end;

      fLinker.FreeNotification(Self);
    end;
  except
    OldLinker := fLinker;
    fLinker   := nil;
    if Assigned(OldLinker) and (OldLinker.WindowIntf = IvgVulkanWindow(Self)) then
      OldLinker.WindowIntf := nil;
    raise;
  end;
end;

procedure TvgWindowFMX.SetDisabled;
begin
  fVulkanActive := False;

  if Assigned(fLinker) and fLinker.Active and not fLinker.StateChanging then
    fLinker.DisableParent(False);
end;

procedure TvgWindowFMX.SetDesigning;
begin
end;

procedure TvgWindowFMX.SetEnabled(aComp: TvgBaseComponent = nil);
begin
  fVulkanActive := False;
  if not Assigned(fLinker) then exit;

  if Assigned(fLinker.ScreenDevice) and
     Assigned(fLinker.ScreenDevice.Instance) and
     not fLinker.ScreenDevice.Instance.Active then
  begin
    fLinker.ScreenDevice.Instance.Active := True;
    exit;
  end;

  fVulkanActive := True;
  vgWindowInvalidate(True);
end;

procedure TvgWindowFMX.DisableParent(ToRoot: Boolean = False);
begin
  if Assigned(fLinker) and fLinker.Active then
    fLinker.DisableParent(ToRoot);
end;

procedure TvgWindowFMX.vgWindowSizeCallback(var WinWidth, WinHeight: TvkUint32);
{$IFDEF MSWINDOWS}
var
  R : TRect;
{$ENDIF}
begin
  WinWidth  := 0;
  WinHeight := 0;
{$IFDEF MSWINDOWS}
  if NativeReady and GetClientRect(fWnd, R) then
  begin
    WinWidth  := R.Width;     //pixels, as the swap chain wants
    WinHeight := R.Height;
  end;
{$ENDIF}
{$IFDEF ANDROID}
  if NativeReady then
  begin
    WinWidth  := Max(fSurfaceWidth, 0);    //pixels, from surfaceChanged
    WinHeight := Max(fSurfaceHeight, 0);
  end;
{$ENDIF}
end;

procedure TvgWindowFMX.vgWindowInvalidate(DoPaint: Boolean);
begin
{$IFDEF MSWINDOWS}
  if not NativeReady then exit;
  Winapi.Windows.InvalidateRect(fWnd, nil, False);
  if DoPaint then
    UpdateWindow(fWnd);
{$ENDIF}
{$IFDEF ANDROID}
  //no paint message: a repaint is a new frame from the linker
  if not NativeReady then exit;
  if DoPaint then
  begin
    if Assigned(fLinker) and fLinker.Active then
      fLinker.TriggerWindowRepaint;
    exit;
  end;

  //later, once, as an invalidated VCL window would
  if fRepaintQueued then exit;
  fRepaintQueued := True;
  TThread.ForceQueue(nil,
    procedure
    begin
      if not Assigned(gLiveWindows) or not gLiveWindows.Contains(Self) then exit;  //freed meanwhile
      fRepaintQueued := False;
      if NativeReady and Assigned(fLinker) and fLinker.Active then
        fLinker.TriggerWindowRepaint;
    end);
{$ENDIF}
end;

procedure TvgWindowFMX.vgWindowBackgroundColor(var aColor: TVkClearValue);
var
  C : TAlphaColorRec;
begin
  C.Color := fClearColor;
  aColor.color.float32[0] := C.R / 255;
  aColor.color.float32[1] := C.G / 255;
  aColor.color.float32[2] := C.B / 255;
  aColor.color.float32[3] := 1.0;
end;

function TvgWindowFMX.vgWindowGetSurface(var aSurface: TVkSurfaceKHR): Boolean;
begin
  //the linker makes the surface from the platform callback
  Result := False;
end;

function TvgWindowFMX.vgCrossHairON: Boolean;
begin
  Result := (Cursor = crNone);
end;

{ Platform callbacks }

{$if defined(Android)}
procedure TvgWindowFMX.SurfaceWinPlatformCallback(var aWindow: PVkAndroidANativeWindow);
begin
  //nil until Android has made the view's surface (OnNativeReady)
  aWindow := PVkAndroidANativeWindow(fNativeWindow);
end;
{$endif}

{$if defined(Wayland) and defined(Unix)}
procedure TvgWindowFMX.SurfaceWinPlatformCallback(var aDisplay: PVkWaylandDisplay; var aSurface: PVkWaylandSurface);
begin
  aDisplay := nil;
  aSurface := nil;
end;
{$endif}

{$if defined(Win32) or defined(Win64)}
procedure TvgWindowFMX.SurfaceWinPlatformCallback(var aWinInstance: TVkHWND; var aModInstance: TVkHINSTANCE);
begin
  CreateNativeWindow;
  if NativeReady then
  begin
    aWinInstance := fWnd;
    aModInstance := HInstance;
  end
  else
  begin
    aWinInstance := 0;
    aModInstance := 0;
  end;
end;
{$endif}

{$if defined(XCB) and defined(Unix)}
procedure TvgWindowFMX.SurfaceWinPlatformCallback(var aConnection: PVkXCBConnection; var aWindow: TVkXCBWindow);
begin
  aConnection := nil;
  aWindow     := 0;
end;
{$endif}

{$if defined(XLIB) and defined(Unix)}
procedure TvgWindowFMX.SurfaceWinPlatformCallback(var aDisplay: PVkXLIBDisplay; var aWindow: TVkXLIBWindow);
begin
  aDisplay := nil;
  aWindow  := 0;
end;
{$endif}

{$if defined(MoltenVK_IOS) and defined(Darwin)}
procedure TvgWindowFMX.SurfaceWinPlatformCallback(var aView: PVkVoid);
begin
  aView := nil;       //not done yet
end;
{$endif}

{$if defined(MoltenVK_MacOS) and defined(Darwin)}
procedure TvgWindowFMX.SurfaceWinPlatformCallback(var aView: PVkVoid);
begin
  aView := nil;       //not done yet
end;
{$endif}

initialization
  RegisterFmxClasses([TvgWindowFMX]);

{$IFDEF MSWINDOWS}
finalization
  if gWndClassRegistered then
    Winapi.Windows.UnregisterClass(cWndClassName, HInstance);
{$ENDIF}
end.
