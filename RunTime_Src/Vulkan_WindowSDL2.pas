unit Vulkan_WindowSDL2;

interface
//{$i PasVulkan.inc}

//{$define PasVulkanUseSDL2}
//{$define PasVulkanUseSDL2WithVulkanSupport}
//{$define PasVulkanUseDynamicSDL2}


Uses
    System.SysUtils,
    System.Generics.Collections,   //MUST STAY HERE
    System.Generics.Defaults,
    System.Classes,                //MUST STAY HERE
    System.Character,
    System.Math,
    typinfo,
    Vulkan,
    PasVulkan.Types,
    PasVulkan.Math,
    PasVulkan.Framework,
    PasVulkan.SDL2,
    Vulkan_Components;

Type
  TvgSDL2Window = class(TvgBaseComponent,IvgVulkanWindow)
  private
    function GetActive: Boolean;
    procedure SetActive(const Value: Boolean);
    function GetSurface: TvgSurface;
    function GetLinker: TvgLinker;
//    procedure SetSurface(const Value: TvgSurface);
    procedure SetLinker(const Value: TvgLinker);
 //   function GetSurface: TvgSurface;
 //   procedure SetSurface(const Value: TvgSurface);

  Protected
       fSDLVersion                 : TSDL_Version;
       fSDLVersionWithVulkanSupport: boolean;

       fLinker        : TvgLinker;

       fSurfaceWindow : PSDL_Window;
       fVulkanSurface : TVkSurfaceKHR;

       Procedure SetDisabled ; Virtual;
       Procedure SetDesigning; Virtual;
       Procedure SetEnabled(aComp:TvgBaseComponent=nil);   Virtual;  //if aComp Set then SetEnabled
 //      Procedure EnableParent; Virtual;
       Procedure DisableParent(ToRoot:Boolean=False); Virtual;  //If ToRoot True then disable will continue up to Root (Instance)

       procedure DefineProperties(Filer: TFiler); override;
       Procedure Loaded ; Override;
       procedure Notification(AComponent: TComponent; Operation: TOperation); override;

  Public
    constructor Create(AOwner: TComponent); Override;
    destructor Destroy; override;

    Procedure vgWindowSizeCallback(var WinWidth, WinHeight : TpvUInt32);  //pixels
    Procedure vgWindowInvalidate( DoPaint:Boolean);
    Procedure vgWindowBackgroundColor(Var aColor:TVkClearValue);
    Function  vgWindowGetSurface(var aSurface :TVkSurfaceKHR):Boolean;

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


  Published
    Property Active :Boolean read GetActive write SetActive;
    Property Linker : TvgLinker read GetLinker write SetLinker;

  end;

implementation

{ TvgSDL2Window }

constructor TvgSDL2Window.Create(AOwner: TComponent);
begin
  inherited;

  SDL_GetVersion(fSDLVersion);

  fSDLVersionWithVulkanSupport:=(fSDLVersion.Major>=3) or
                               ((fSDLVersion.Major=2) and
                                (((fSDLVersion.Minor=0) and (fSDLVersion.Patch>=6)) or
                                 (fSDLVersion.Minor>=1)
                                )
                               );


end;

procedure TvgSDL2Window.DefineProperties(Filer: TFiler);
begin
  inherited;

end;

destructor TvgSDL2Window.Destroy;
begin
  If fActive then
    SetDisabled;
  inherited;
end;

procedure TvgSDL2Window.DisableParent(ToRoot: Boolean);
begin
  If assigned(fLinker) and fLinker.Active then
     fLinker.disableParent;

end;

function TvgSDL2Window.GetActive: Boolean;
begin
  Result:=fActive;
end;

function TvgSDL2Window.GetSurface: TvgSurface;
begin
  Result:=nil;
  If assigned(fLinker) and assigned(fLinker.Surface) then
    Result:=fLinker.Surface;
end;

function TvgSDL2Window.GetLinker: TvgLinker;
begin
  Result:=fLinker;
end;

procedure TvgSDL2Window.Loaded;
begin
  inherited;

end;

procedure TvgSDL2Window.Notification(AComponent: TComponent;  Operation: TOperation);
begin
  inherited Notification(aComponent, Operation);

  Case Operation of
     opInsert : Begin

                  If (aComponent is TvgLinker) and Not assigned(fLinker)  then
                    SetLinker(TvgLinker(aComponent));

                End;

     opRemove : Begin

                  If (aComponent is TvgLinker) and (TvgLinker(aComponent)=fLinker)  then
                      fLinker := nil;
                end;
  end;
end;

procedure TvgSDL2Window.SetActive(const Value: Boolean);
begin
  If fActive = Value then exit;
  fActive:=Value;
  If fActive then
     SetEnabled
  else
     SetDisabled;
end;

procedure TvgSDL2Window.SetDesigning;
begin
  inherited;

end;

procedure TvgSDL2Window.SetDisabled;
begin
  If  fSurfaceWindow=nil then exit;

  SDL_DestroyWindow(fSurfaceWindow);
  fSurfaceWindow:=nil;

end;

procedure TvgSDL2Window.SetEnabled(aComp:TvgBaseComponent=nil);
begin
  //inherited;
  If  fSurfaceWindow<>nil then exit;

  fSurfaceWindow := SDL_CreateWindow(pansichar('Test') ,100,100,260,200, SDL_WINDOW_SHOWN or SDL_WINDOW_VULKAN);

end;
(*
procedure TvgSDL2Window.SetSurface(const Value: TvgSurface);
begin
  If fSurface=Value then exit;
  SetDisabled;
  fSurface:=Value;
  If assigned(fSurface) then
     fSurface.WindowIntf:=Self;
end;
*)
procedure TvgSDL2Window.SetLinker(const Value: TvgLinker);
begin
  If fLinker=Value then exit;
  SetDisabled;
  fLinker:=Value;
  If assigned(fLinker) and assigned(fLinker.Surface) then
     fLinker.Surface.WindowIntf:=Self;
end;

procedure TvgSDL2Window.vgWindowBackgroundColor(var aColor: TVkClearValue);
begin
  aColor.color.float32[0]:=0;
  aColor.color.float32[1]:=0;
  aColor.color.float32[2]:=0;
  aColor.color.float32[3]:=1;
end;

function TvgSDL2Window.vgWindowGetSurface(var aSurface: TVkSurfaceKHR): Boolean;
begin
  Result:=False;
  aSurface :=0;

  If not assigned(fLinker) then exit;
  If not assigned(fLinker.Device.Instance) then exit;
  If not assigned(fLinker.Device.Instance.VulkanInstance) then exit;

  If (fVulkanSurface=0) then
    SDL_Vulkan_CreateSurface(fSurfaceWindow, fLinker.Device.Instance.VulkanInstance.Handle, @fVulkanSurface) ;

  If (fVulkanSurface<>0)  then
  Begin
    Result:=  True;
    aSurface:= fVulkanSurface;
  end;
end;

procedure TvgSDL2Window.vgWindowInvalidate(DoPaint: Boolean);
begin

end;

procedure TvgSDL2Window.vgWindowSizeCallback(var WinWidth, WinHeight: TpvUInt32);
  Var W,H:TSDLInt32;
begin
  W:=0;
  H:=0;
  If assigned(fSurfaceWindow) then
    SDL_Vulkan_GetDrawableSize(fSurfaceWindow,@W,@H);

  WinWidth := W;
  WinHeight:= H;
end;

{$if defined(Android)}
Procedure TvgSDL2Window.SurfaceWinPlatformCallback(Var aWindow:PVkAndroidANativeWindow);
    Begin
      aWindow:=0;
    end;
{$ifend}
{$if defined(Wayland) and defined(Unix)}
Procedure TvgSDL2Window.SurfaceWinPlatformCallback(var aDisplay:PVkWaylandDisplay;var aSurface:PVkWaylandSurface );
    Begin
      aDisplay:=0;
      aSurface:=0;
    end;
{$ifend}
{$if defined(Win32) or defined(Win64)}
Procedure TvgSDL2Window.SurfaceWinPlatformCallback(var aWinInstance : TVkHWND;Var aModInstance : TVkHINSTANCE);
    var SDL_SysWMinfo:TSDL_SysWMinfo;
    Begin
       If not fActive then
          Active:=True;

       SDL_VERSION(SDL_SysWMinfo.version);
       if (SDL_GetWindowWMInfo(fSurfaceWindow,@SDL_SysWMinfo)<>0) and (SDL_SysWMinfo.subsystem=SDL_SYSWM_WINDOWS) then
       begin
         aWinInstance := SDL_SysWMinfo.Window;
         aModInstance := SDL_SysWMinfo.hinstance;
       end else
       Begin
         aWinInstance := 0;
         aModInstance := 0;
       end;
    end;
{$ifend}
{$if defined(XCB) and defined(Unix)}
Procedure TvgSDL2Window.SurfaceWinPlatformCallback(Var aConnection:PVkXCBConnection; Var aWindow:TVkXCBWindow);
    Begin
      aConnection:=0;
      aWindow:=0;
    end;
{$ifend}
{$if defined(XLIB) and defined(Unix)}
Procedure TvgSDL2Window.SurfaceWinPlatformCallback(Var aDisplay:PVkXLIBDisplay; Var aWindow:TVkXLIBWindow);
    Begin
      aDisplay:=0;
      aWindow:=0;
    end;
{$ifend}
{$if defined(MoltenVK_IOS) and defined(Darwin)}
Procedure TvgSDL2Window.SurfaceWinPlatformCallback(Var aView:PVkVoid );
    Begin
      aView:=0;
    end;
{$ifend}
{$if defined(MoltenVK_MacOS) and defined(Darwin)}
Procedure TvgSDL2Window.SurfaceWinPlatformCallback(Var aView:PVkVoid );
    Begin
      aView:=0;
    end;
{$ifend}

Initialization

  SDL_Init(SDL_INIT_VIDEO or SDL_INIT_EVENTS);

Finalization

  SDL_Quit;

end.

