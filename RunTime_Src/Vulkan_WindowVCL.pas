unit Vulkan_WindowVCL;

interface

//{$DEFINE DEBUGDESIGN}

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.Character,
  System.UITypes,
  WinApi.Windows,
//  vcl.Forms,
{$IFDEF DEBUGDESIGN}
  vcl.Dialogs,
{$ENDIF}
  VCL.Controls,
  WinAPI.Messages,
  Vulkan,
  PasVulkan.Types,
  PasVulkan.Framework,
  Vulkan_Components,
  Vulkan_Assert;
//  Dialogs;

Type

  TvgWindowVCL = class(TCustomControl, IvgVulkanWindow)
  private
  //  function GetSurface: TvgSurface;
  //  procedure SetSurface(const Value: TvgSurface);

//    procedure WMSize(var Message: TWMSize); message WM_SIZE;
//    procedure WMPaint(var Message: TWMPaint); message WM_PAINT;
  (*
    procedure WMCommand(var Message: TWMCommand); message WM_COMMAND;
    procedure WMNotify(var Message: TWMNotify); message WM_NOTIFY;
    procedure WMSysColorChange(var Message: TWMSysColorChange); message WM_SYSCOLORCHANGE;
    procedure WMHScroll(var Message: TWMHScroll); message WM_HSCROLL;
    procedure WMVScroll(var Message: TWMVScroll); message WM_VSCROLL;
    procedure WMCompareItem(var Message: TWMCompareItem); message WM_COMPAREITEM;
    procedure WMDeleteItem(var Message: TWMDeleteItem); message WM_DELETEITEM;
    procedure WMDrawItem(var Message: TWMDrawItem); message WM_DRAWITEM;
    procedure WMMeasureItem(var Message: TWMMeasureItem); message WM_MEASUREITEM;
    procedure WMEraseBkgnd(var Message: TWmEraseBkgnd); message WM_ERASEBKGND;
    procedure WMWindowPosChanged(var Message: TWMWindowPosChanged); message WM_WINDOWPOSCHANGED;
    procedure WMWindowPosChanging(var Message: TWMWindowPosChanging); message WM_WINDOWPOSCHANGING;
    *)
    procedure WMSize(var Message: TWMSize); message WM_SIZE;
    procedure WMMove(var Message: TWMMove); message WM_MOVE;
    (*
    procedure WMSetCursor(var Message: TWMSetCursor); message WM_SETCURSOR;
    procedure WMKeyDown(var Message: TWMKeyDown); message WM_KEYDOWN;
    procedure WMSysKeyDown(var Message: TWMSysKeyDown); message WM_SYSKEYDOWN;
    procedure WMKeyUp(var Message: TWMKeyUp); message WM_KEYUP;
    procedure WMSysKeyUp(var Message: TWMSysKeyUp); message WM_SYSKEYUP;
    procedure WMChar(var Message: TWMChar); message WM_CHAR;
    procedure WMSysCommand(var Message: TWMSysCommand); message WM_SYSCOMMAND;
    procedure WMCharToItem(var Message: TWMCharToItem); message WM_CHARTOITEM;
    procedure WMParentNotify(var Message: TWMParentNotify); message WM_PARENTNOTIFY;
    procedure WMVKeyToItem(var Message: TWMVKeyToItem); message WM_VKEYTOITEM;
  *)
    procedure WMDestroy(var Message: TWMDestroy); message WM_DESTROY;
  (*
    procedure WMMouseActivate(var Message: TWMMouseActivate); message WM_MOUSEACTIVATE;
    procedure WMNCCalcSize(var Message: TWMNCCalcSize); message WM_NCCALCSIZE;
    procedure WMNCDestroy(var Message: TWMNCDestroy); message WM_NCDESTROY;
    procedure WMNCHitTest(var Message: TWMNCHitTest); message WM_NCHITTEST;
    procedure WMNCPaint(var Message: TWMNCPaint); message WM_NCPAINT;
    procedure WMQueryNewPalette(var Message: TMessage); message WM_QUERYNEWPALETTE;
    procedure WMPaletteChanged(var Message: TMessage); message WM_PALETTECHANGED;
    procedure WMWinIniChange(var Message: TMessage); message WM_WININICHANGE;
    procedure WMFontChange(var Message: TMessage); message WM_FONTCHANGE;
    procedure WMTimeChange(var Message: TMessage); message WM_TIMECHANGE;
    procedure WMSetFocus(var Message: TWMSetFocus); message WM_SETFOCUS;
    procedure WMKillFocus(var Message: TWMKillFocus); message WM_KILLFOCUS;
    procedure WMIMEStartComp(var Message: TMessage); message WM_IME_STARTCOMPOSITION;
    procedure WMIMEEndComp(var Message: TMessage); message WM_IME_ENDCOMPOSITION;
    procedure WMContextMenu(var Message: TWMContextMenu); message WM_CONTEXTMENU;
    procedure WMGesture(var Message: TMessage); message WM_GESTURE;
    procedure WMGestureNotify(var Message: TWMGestureNotify); message WM_GESTURENOTIFY;
    procedure WMTabletQuerySystemGestureStatus(var Message: TMessage); message WM_TABLET_QUERYSYSTEMGESTURESTATUS;
    procedure CMChanged(var Message: TCMChanged); message CM_CHANGED;
    procedure CMChildKey(var Message: TCMChildKey); message CM_CHILDKEY;
    procedure CMDialogKey(var Message: TCMDialogKey); message CM_DIALOGKEY;
    procedure CMDialogChar(var Message: TCMDialogChar); message CM_DIALOGCHAR;
    procedure CMVisibleChanged(var Message: TMessage); message CM_VISIBLECHANGED;
    procedure CMEnabledChanged(var Message: TMessage); message CM_ENABLEDCHANGED;
    procedure CMColorChanged(var Message: TMessage); message CM_COLORCHANGED;
    procedure CMFontChanged(var Message: TMessage); message CM_FONTCHANGED;
    procedure CMBorderChanged(var Message: TMessage); message CM_BORDERCHANGED;
    procedure CMCursorChanged(var Message: TMessage); message CM_CURSORCHANGED;
    procedure CMCtl3DChanged(var Message: TMessage); message CM_CTL3DCHANGED;
    procedure CMParentCtl3DChanged(var Message: TMessage); message CM_PARENTCTL3DCHANGED;
    procedure CMParentDoubleBufferedChanged(var Message: TMessage); message CM_PARENTDOUBLEBUFFEREDCHANGED;
    procedure CMShowingChanged(var Message: TMessage); message CM_SHOWINGCHANGED;
    procedure CMShowHintChanged(var Message: TMessage); message CM_SHOWHINTCHANGED;
    procedure CMEnter(var Message: TCMEnter); message CM_ENTER;
    procedure CMExit(var Message: TCMExit); message CM_EXIT;
    procedure CMDesignHitTest(var Message: TCMDesignHitTest); message CM_DESIGNHITTEST;
    procedure CMSysColorChange(var Message: TMessage); message CM_SYSCOLORCHANGE;
    procedure CMSysFontChanged(var Message: TMessage); message CM_SYSFONTCHANGED;
    procedure CMWinIniChange(var Message: TWMWinIniChange); message CM_WININICHANGE;
    procedure CMFontChange(var Message: TMessage); message CM_FONTCHANGE;
    procedure CMTimeChange(var Message: TMessage); message CM_TIMECHANGE;
    procedure CMDrag(var Message: TCMDrag); message CM_DRAG;
    procedure CNKeyDown(var Message: TWMKeyDown); message CN_KEYDOWN;
    procedure CNKeyUp(var Message: TWMKeyUp); message CN_KEYUP;
    procedure CNChar(var Message: TWMChar); message CN_CHAR;
    procedure CNSysKeyDown(var Message: TWMKeyDown); message CN_SYSKEYDOWN;
    procedure CNSysChar(var Message: TWMChar); message CN_SYSCHAR;
    procedure CMRecreateWnd(var Message: TMessage); message CM_RECREATEWND;
    procedure CMInvalidate(var Message: TMessage); message CM_INVALIDATE;
    *)

       Procedure SetDisabled ;
       Procedure SetDesigning;
       Procedure SetEnabled(aComp:TvgBaseComponent=nil);     //if aComp Set then SetEnabled
       Procedure DisableParent(ToRoot:Boolean=False); Virtual;  //If ToRoot True then disable will continue up to Root (Instance)


    function GetClearColor: TColor;
    procedure SetClearColor(const Value: TColor);
    function GetLinker: TvgLinker;
    procedure SetLinker(const Value: TvgLinker);
    function GetActive: Boolean;
    procedure SetActive(const Value: Boolean);

  protected

    fVulkanActive : Boolean;
    fLinker       : TvgLinker;
    fWinReady     : Boolean;
    fClearColor   : TColor;

   procedure Notification(AComponent: TComponent; Operation: TOperation); override;

    procedure CreateParams(var Params: TCreateParams); override;

    procedure CreateHandle; override;
    procedure DestroyHandle; override;


  public
    constructor Create(AOwner: TComponent); Override;
    destructor Destroy; override;

{$if defined(Android)}
    Procedure SurfaceWinPlatformCallback(Var aWindow:PVkAndroidANativeWindow);
{$ifend}
{$if defined(Wayland) and defined(Unix)}
    Procedure SurfaceWinPlatformCallback(var aDisplay:PVkWaylandDisplay;var aSurface:PVkWaylandSurface );
{$ifend}
{$if defined(Win32) or defined(Win64)}
    Procedure SurfaceWinPlatformCallback(var aWinInstance : TVkHWND;Var aModInstance : TVkHINSTANCE);
{$ifend}
{$if defined(XCB) and defined(Unix)}
    Procedure SurfaceWinPlatformCallback(Var aConnection:PVkXCBConnection; Var aWindow:TVkXCBWindow);
{$ifend}
{$if defined(XLIB) and defined(Unix)}
    Procedure SurfaceWinPlatformCallback(Var aDisplay:PVkXLIBDisplay; Var aWindow:TVkXLIBWindow);
{$ifend}
{$if defined(MoltenVK_IOS) and defined(Darwin)}
    Procedure SurfaceWinPlatformCallback(Var aView:PVkVoid );
{$ifend}
{$if defined(MoltenVK_MacOS) and defined(Darwin)}
    Procedure SurfaceWinPlatformCallback(Var aView:PVkVoid );
{$ifend}

    Procedure Paint ; Override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;


    Procedure vgWindowSizeCallback(var WinWidth, WinHeight : TpvUInt32);  //pixels
    Procedure vgWindowInvalidate( DoPaint:Boolean);
    Procedure vgWindowBackgroundColor(Var aColor:TVkClearValue);
    Function  vgWindowGetSurface(var aSurface :TVkSurfaceKHR):Boolean;


  published
    Property Active     : Boolean read GetActive write SetActive stored false;  //don't store this value
    Property Align ;
    Property Color;
    Property ClearColor : TColor read GetClearColor Write SetClearColor;
    Property VulkanLink : TvgLinker read GetLinker write SetLinker ;
  end;

procedure Windows_RunShaderBuildBatchFile(aPathFile:String; WaitForFinish:Boolean = True);

implementation

procedure Windows_RunShaderBuildBatchFile(aPathFile:String; WaitForFinish:Boolean = True);
//include file name and path
var
  sCmd: string;
  si: TStartupInfo;
  pi: TProcessInformation;
begin
  If aPathFile='' then exit;
  If NOT fileExists(aPathFile) then exit;

  sCmd := 'cmd.exe /c "' + aPathFile + '"';

  FillChar(si, SizeOf(si), 0);
  si.cb          := SizeOf(si);
  si.dwFlags     := STARTF_USESHOWWINDOW;
  si.wShowWindow := SW_MAXIMIZE;

  CreateProcess(nil, PChar(sCmd), nil, nil, False, 0, nil, nil, si, pi);

  If WaitForFinish then
     WaitForSingleObject(pi.hProcess, INFINITE);
end;



 (*
type
  TC4BorderColors = (bcNone, bcLeft, bcRight, bcBineural, bcStatus, bcBlack, bcWhite);

function getC4BorderColor(value : TC4BorderColors) : TColor;
begin
  case value of
    bcLeft : result := RGB(47, 101, 168);
    bcRight : result := RGB(215, 49, 40);
    bcBineural : result := RGB(40, 40, 40);
    bcStatus : result := RGB(86, 86, 86);
    bcBlack : result := clBlack;
    bcWhite : result := clWhite;
  else
    result := clBlack;
  end;
end;

Procedure DrawScrollFace(ScrollEdit: TC4CustomScrollEdit; BackgroundColor, buttonColor, ArrowColor : TColor);
var
  C: TControlCanvas;
  R, RLeft, RRight: TRect;
  X : integer;
begin
  C := TControlCanvas.Create;
  try
    C.Control := ScrollEdit;
    with ScrollEdit do begin
      R := ClientRect;
      If ScrollEdit.BorderColor <> bcNone then Begin
        C.Brush.Color := GetC4BorderColor(borderColor);
        C.FrameRect(R);
      end
      else begin
        C.Brush.Color := GetC4BorderColor(borderColor);
        C.FrameRect(R);
      end;
      RLeft := R;
      RLeft.Right := RLeft.Left + 17; //FSmallSpinBWidth;
      InflateRect(RLeft, 0, -1);
      Inc(RLeft.Left);
      C.Brush.Color := BackgroundColor;
      C.FillRect(RLeft);
      InflateRect(RLeft, -1, -1);
      C.Brush.Color := buttonColor;
      C.FillRect(RLeft);
      // Vandret pil tegnes
      C.Pen.Color := ArrowColor;
      X := R.Left + 7;
      C.Moveto(X + 0, R.Top + 9);
      C.LineTo(X + 0, R.Top + 10);
      C.Moveto(X + 1, R.Top + 8);
      C.LineTo(X + 1, R.Top + 11);
      C.Moveto(X + 2, R.Top + 7);
      C.LineTo(X + 2, R.Top + 12);
      C.Moveto(X + 3, R.Top + 6);
      C.LineTo(X + 3, R.Top + 13);
      RRight := R;
      RRight.Left := RRight.Right - 17;
      InflateRect(RRight, 0, -1);
      Dec(RRight.Right);
      C.Brush.Color := BackgroundColor;
      C.FillRect(RRight);
      InflateRect(RRight, -1, -1);
     C.Brush.Color := buttonColor;
      C.FillRect(RRight);
      // Vandret pil tegnes
      X := R.Right - 11;
      C.Moveto(X + 3, R.Top + 9);
      C.LineTo(X + 3, R.Top + 10);
      C.Moveto(X + 2, R.Top + 8);
      C.LineTo(X + 2, R.Top + 11);
      C.Moveto(X + 1, R.Top + 7);
      C.LineTo(X + 1, R.Top + 12);
      C.Moveto(X + 0, R.Top + 6);
      C.LineTo(X + 0, R.Top + 13);
    end; // with
  finally
  end;
end;

*)
{ TvgSurfaceVCL }

constructor TvgWindowVCL.Create(AOwner: TComponent);

begin
  inherited;

  fClearColor :=   0;  //black
end;

procedure TvgWindowVCL.CreateHandle;
begin
  inherited;   //important;

  fWinReady := True;

  If assigned(fLinker) then
  Begin
    fLinker.WindowReady        :=True;
    fLinker.NeedSurfaceRebuild := True;
    fLinker.FlagSwapChainRebuild;
  End;


end;

procedure TvgWindowVCL.CreateParams(var Params: TCreateParams);
begin
  inherited;

   Params.Style  :=WS_CHILD or
                   WS_CLIPCHILDREN or
                   WS_CLIPSIBLINGS or
                   WS_GROUP or
                   WS_TABSTOP;

   Params.ExStyle:=WS_EX_APPWINDOW or
                   WS_EX_WINDOWEDGE;

   Params.WindowClass.style:=CS_VREDRAW +
                             CS_HREDRAW +
                             CS_DBLCLKS +
                             CS_OWNDC;


end;

destructor TvgWindowVCL.Destroy;
begin

  If assigned(fLinker) then
  Begin
    fLinker.WindowIntf := Nil;
    fLinker            := nil;
  End;

  fWinReady := False;

  inherited;
end;

procedure TvgWindowVCL.DestroyHandle;
begin

  If assigned(fLinker) then
  Begin
    fLinker.WindowReady        :=False;
    fLinker.NeedSurfaceRebuild := False;
  End;

  inherited;
end;

procedure TvgWindowVCL.DisableParent(ToRoot:Boolean=False);
begin
  If assigned(fLinker) and fLinker.Active then
     fLinker.disableParent(ToRoot);
end;

function TvgWindowVCL.GetActive: Boolean;
begin
   Result:= fVulkanActive;
end;

function TvgWindowVCL.GetClearColor: TColor;
begin
  Result:= fClearColor;
end;

function TvgWindowVCL.GetLinker: TvgLinker;
begin
  Result := fLinker;
end;

procedure TvgWindowVCL.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited;

  If not assigned(fLinker) then exit;

  fLinker.MouseMove(Shift, X, Y);

end;

procedure TvgWindowVCL.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(aComponent, Operation);

  CustomAssert(assigned(aComponent),'aComponent not assigned',self);

  Case Operation of
     opInsert : Begin

                  If (aComponent is TvgLinker) and Not assigned(fLinker)  then
                  Begin
                    SetLinker(TvgLinker(aComponent));
                  end;
                End;

     opRemove : Begin

                  If (aComponent is TvgLinker) and assigned(fLinker) and (TvgLinker(aComponent)=fLinker)  then
                  Begin
                      fLinker := nil;
                    //  ShowMessage('Remove Notification to Window from WinLink');
                  End;
                end;
  end;
end;

procedure TvgWindowVCL.Paint;
  var B: Boolean;
begin
    //canvas MAY BE available to draw AFTER Vulkan
    //NVIDEA yes
    //INTEL NO

  If assigned(fLinker) and (fLinker.Active) then
  Begin
     B:= True;
     fLinker.TriggerWindowRepaint ;
  end else
     B:= False;

  If B  then
  Begin
   //Canvas.TextOut(50,50,'Enabled');

  End else
  Begin
    Canvas.Pen.Width:=2;
    Canvas.Rectangle(2,2,Width-2,Height-2) ;
  End;
 (*

 // Canvas.Pen.Color:=clRed;
  Canvas.Pen.Width:=1;
  Canvas.MoveTo(0,0);
  Canvas.LineTo(100,100);
  *)
end;

procedure TvgWindowVCL.SetActive(const Value: Boolean);
begin

  If fVulkanActive=Value then exit;
  fVulkanActive := False;
  If not HandleAllocated then exit;

  fVulkanActive := Value;

  If fVulkanActive then
    SetEnabled
  else
    SetDisabled;

end;

procedure TvgWindowVCL.SetClearColor(const Value: TColor);
begin
  fClearColor := Value;
end;

procedure TvgWindowVCL.SetDesigning;
begin

end;

procedure TvgWindowVCL.SetDisabled;
begin
  fVulkanActive := False;

  If assigned(fLinker) and fLinker.Active and NOT fLinker.StateChanging then
  Begin
    fLinker.DisableParent(False);
    EXit;
  End;
//  vgWindowInvalidate(True);
end;

procedure TvgWindowVCL.SetEnabled(aComp:TvgBaseComponent=nil);
begin
  fVulkanActive:=False;
  If not assigned(fLinker) then exit;
  If not fLinker.Active then
  Begin
     fLinker.Active:=True;
  End;

  fVulkanActive := True;
  vgWindowInvalidate(True);
end;

procedure TvgWindowVCL.SetLinker(const Value: TvgLinker);
begin
  If fLinker=Value then exit;
  If assigned( fLinker) then
  Begin
     fLinker.RemoveFreeNotification(self);
     fLinker:=Nil;
  End;

  fLinker := Value;
 Try
  If assigned(fLinker) then
  Begin

     If (fLinker.WindowIntf<>IvgVulkanWindow(self))  then
         fLinker.WindowIntf := Self;

     If fLinker.Active then
     Begin
       fLinker.WindowReady        := True;
       fLinker.NeedSurfaceRebuild := True;
       fLinker.FlagSwapChainRebuild;
     end;

     fLinker.FreeNotification(self);
  End;
 Except
   On E:Exception do
      fLinker:=nil;
 End;
end;

procedure TvgWindowVCL.vgWindowSizeCallback(var WinWidth, WinHeight: TpvUInt32);
begin
   WinWidth  := Width  ;
   WinHeight := Height ;
end;

procedure TvgWindowVCL.vgWindowBackgroundColor(var aColor: TVkClearValue);
  Var C     : TColor;
      R,G,B : TVkFloat;
begin
  C:= fClearColor;
  R:= GetRValue(C);
  G:= GetGValue(C);
  B:= GetBValue(C);

  aColor.color.float32[0]:=R;
  aColor.color.float32[1]:=G;
  aColor.color.float32[2]:=B;
  aColor.color.float32[3]:=1.0;

end;

function TvgWindowVCL.vgWindowGetSurface(var aSurface: TVkSurfaceKHR): Boolean;
begin
  Result:=False;
end;

procedure TvgWindowVCL.vgWindowInvalidate( DoPaint:Boolean);
begin

  Invalidate;
  If DoPaint then
    Update;

end;

procedure TvgWindowVCL.WMDestroy(var Message: TWMDestroy);
begin

  If assigned(fLinker) then
  Begin
    If fLinker.Active then
       Self.DisableParent(True);
    fLinker.WindowIntf:=nil;
    fLinker           := nil;
  End;

end;

procedure TvgWindowVCL.WMMove(var Message: TWMMove);
begin
  If (csDesigning in self.ComponentState) then
  Begin
     DisableParent(True);
{$IFDEF DEBUGDESIGN}
     ShowMessage('Window Moved in Design State');
{$ENDIF}
  end;
end;

procedure TvgWindowVCL.WMSize(var Message: TWMSize);
begin
  Inherited;

  If (csDesigning in self.ComponentState) then
  Begin
     DisableParent(True);
{$IFDEF DEBUGDESIGN}
     ShowMessage('Window resized in Design State');
{$ENDIF}
  end else
  If assigned(fLinker) and fLinker.Active then
    fLinker.FlagSwapChainRebuild;

end;

{$if defined(Android)}
Procedure TvgWindowVCL.SurfaceWinPlatformCallback(Var aWindow:PVkAndroidANativeWindow);
    Begin
      aWindow:=0;
    end;
{$ifend}
{$if defined(Wayland) and defined(Unix)}
Procedure TvgWindowVCL.SurfaceWinPlatformCallback(var aDisplay:PVkWaylandDisplay;var aSurface:PVkWaylandSurface );
    Begin
      aDisplay:=0;
      aSurface:=0;
    end;
{$ifend}
{$if defined(Win32) or defined(Win64)}
Procedure TvgWindowVCL.SurfaceWinPlatformCallback(var aWinInstance : TVkHWND;Var aModInstance : TVkHINSTANCE);
    Begin
      aWinInstance:= Handle;   //calls handleneeded
      aModInstance:= HInstance;
    end;
{$ifend}
{$if defined(XCB) and defined(Unix)}
Procedure TvgWindowVCL.SurfaceWinPlatformCallback(Var aConnection:PVkXCBConnection; Var aWindow:TVkXCBWindow);
    Begin
      aConnection:=0;
      aWindow:=0;
    end;
{$ifend}
{$if defined(XLIB) and defined(Unix)}
Procedure TvgWindowVCL.SurfaceWinPlatformCallback(Var aDisplay:PVkXLIBDisplay; Var aWindow:TVkXLIBWindow);
    Begin
      aDisplay:=0;
      aWindow:=0;
    end;
{$ifend}
{$if defined(MoltenVK_IOS) and defined(Darwin)}
Procedure TvgWindowVCL.SurfaceWinPlatformCallback(Var aView:PVkVoid );
    Begin
      aView:=0;
    end;
{$ifend}
{$if defined(MoltenVK_MacOS) and defined(Darwin)}
Procedure TvgWindowVCL.SurfaceWinPlatformCallback(Var aView:PVkVoid );
    Begin
      aView:=0;
    end;
{$ifend}


end.
