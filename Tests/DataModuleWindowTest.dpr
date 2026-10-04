program DataModuleWindowTest;

{$APPTYPE CONSOLE}

{ TvgVulkanDataModule.Window is any component implementing IvgVulkanWindow, so
  the data module no longer needs Vulkan_WindowVCL (or the VCL window class).
  This checks, with a fake window and no Vulkan device:

    - Window accepts a window and exposes it as WindowIntf, and rejects a
      component that is not one, leaving the old window in place;
    - ConnectSession/BuildSession hand the primary linker to the window, and
      vgSessionInstance finds the instance from the window;
    - AddLinker takes the window as an interface;
    - SessionActive reads False and := False is harmless (enabling needs a
      real surface, so it is left to the sample app);
    - freeing the window clears Window and WindowIntf. }

uses
  System.SysUtils,
  System.Classes,
  Vulkan,
  Vulkan_Components_Lookups,
  Vulkan_Components,
  Vulkan_Components_Scene_Renderer,
  Vulkan_DataModule;

type

  TFakeWindow = class(TComponent, IvgVulkanWindow)
  private
    fLinker : TvgLinker;
  public
    destructor Destroy; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
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
    procedure SurfaceWinPlatformCallback(var aWinInstance: TVkHWND; var aModInstance: TVkHINSTANCE);
  end;

destructor TFakeWindow.Destroy;
begin
  //as TvgWindowVCL does: the linker must not keep a freed window
  If assigned(fLinker) then
  Begin
    fLinker.WindowIntf := nil;
    fLinker            := nil;
  End;
  inherited;
end;

procedure TFakeWindow.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  If (Operation = opRemove) and (AComponent = fLinker) then fLinker := nil;
end;


function TFakeWindow.GetLinker: TvgLinker;
begin
  Result := fLinker;
end;

procedure TFakeWindow.SetLinker(const Value: TvgLinker);
begin
  If fLinker = Value then exit;
  fLinker := Value;
  If assigned(fLinker) then fLinker.FreeNotification(Self);
  If assigned(fLinker) and (fLinker.WindowIntf <> IvgVulkanWindow(Self)) then
    fLinker.WindowIntf := Self;
end;

procedure TFakeWindow.SetDisabled; begin end;
procedure TFakeWindow.SetDesigning; begin end;
procedure TFakeWindow.SetEnabled(aComp: TvgBaseComponent); begin end;
procedure TFakeWindow.DisableParent(ToRoot: Boolean); begin end;
procedure TFakeWindow.vgWindowSizeCallback(var WinWidth, WinHeight: TvkUint32); begin end;
procedure TFakeWindow.vgWindowInvalidate(DoPaint: Boolean); begin end;
procedure TFakeWindow.vgWindowBackgroundColor(var aColor: TVkClearValue); begin end;
function  TFakeWindow.vgWindowGetSurface(var aSurface: TVkSurfaceKHR): Boolean; begin Result := False; end;
function  TFakeWindow.vgCrossHairON: Boolean; begin Result := False; end;
procedure TFakeWindow.SurfaceWinPlatformCallback(var aWinInstance: TVkHWND; var aModInstance: TVkHINSTANCE); begin end;

// Interface values are compared in their own frames: a temporary left in the
// main body would be released after the window it points at was freed.
function HasWindowIntf(aDM: TvgVulkanDataModule): Boolean;
begin
  Result := assigned(aDM.WindowIntf);
end;

function LinkerHas(aLinker: TvgLinker; aWin: TFakeWindow): Boolean;
begin
  Result := assigned(aLinker) and (aLinker.WindowIntf = IvgVulkanWindow(aWin));
end;

var
  Failures : Integer = 0;

procedure Check(const Name: string; Got, Expect: Boolean);
begin
  if Got = Expect then
    Writeln(Format('  ok   %-58s %s', [Name, BoolToStr(Got, True)]))
  else
  begin
    Writeln(Format('  FAIL %-58s got %s expected %s',
      [Name, BoolToStr(Got, True), BoolToStr(Expect, True)]));
    Inc(Failures);
  end;
end;

var
  DM       : TvgVulkanDataModule;
  W1, W2   : TFakeWindow;
  Plain    : TComponent;
  Raised   : Boolean;
  L2       : TvgLinker;
  Scene    : TvgScene;
  Tools    : TvgToolManager;
  DM2      : TvgVulkanDataModule;
  Inst     : TvgInstance;
  PD       : TvgPhysicalDevice;
  SD       : TvgScreenRenderDevice;
  Lk       : TvgLinker;
  S2       : TvgScene;
  TM2      : TvgToolManager;
begin
  DM := TvgVulkanDataModule.CreateNew(nil);
  W1 := TFakeWindow.Create(nil);
  W2 := TFakeWindow.Create(nil);
  Plain := TComponent.Create(nil);
  try
    Writeln('Window property');
    DM.Window := W1;
    Check('Window set', DM.Window = W1, True);
    Check('WindowIntf set', HasWindowIntf(DM), True);

    Raised := False;
    Try
      DM.Window := Plain;
    Except
      on EvgVulkanSessionError do Raised := True;
    End;
    Check('non-window rejected', Raised, True);
    Check('old window kept after rejection', DM.Window = W1, True);

    Writeln('BuildSession');
    DM.BuildSession;
    Check('window got the primary linker', W1.GetLinker = DM.Linker, True);
    Check('linker knows the window', LinkerHas(DM.Linker, W1), True);
    Check('vgSessionInstance(window) = Instance', vgSessionInstance(W1) = DM.Instance, True);
    Check('vgLinkerWindow = window', vgLinkerWindow(DM.Linker) = W1, True);

    Writeln('AddLinker');
    L2 := DM.AddLinker(W2);
    Check('second window linked', W2.GetLinker = L2, True);
    Check('second linker is not the primary', L2 <> DM.Linker, True);

    Writeln('SessionActive');
    Check('SessionActive False', DM.SessionActive, False);
    Check('a fake window passes SessionProblem (not a VCL control)', DM.SessionProblem = '', True);
    DM.SessionActive := False;
    Check('disable when inactive is harmless', DM.SessionActive, False);

    Writeln('Dropping parts on the module');
    Scene := TvgScene.Create(DM);
    Tools := TvgToolManager.Create(DM);
    Check('nothing linked inside the constructors', DM.Scene = nil, True);
    DM.AdoptComponents;     //what the designer does after the drop
    Check('Scene adopted', (DM.Scene = Scene), True);
    Check('ToolManager adopted', (DM.ToolManager = Tools), True);
    Check('Scene.Linker set', Scene.Linker = DM.Linker, True);
    Check('ToolManager.Linker set', Tools.Linker = DM.Linker, True);
    Check('ToolManager.Scene set', Tools.Scene = Scene, True);
    Check('Linker.ToolManager set', DM.Linker.ToolManager = Tools, True);

    Writeln('Freeing the window');
    FreeAndNil(W1);
    Check('Window cleared', DM.Window = nil, True);
    Check('WindowIntf cleared', HasWindowIntf(DM), False);
  finally

    DM.Free;
    W2.Free;
    Plain.Free;
    W1.Free;
  end;


  Writeln('Dropping the whole chain on an empty module');
  DM2  := TvgVulkanDataModule.CreateNew(nil);
  try
    Inst := TvgInstance.Create(DM2);
    PD   := TvgPhysicalDevice.Create(DM2);
    SD   := TvgScreenRenderDevice.Create(DM2);
    Lk   := TvgLinker.Create(DM2);
    S2   := TvgScene.Create(DM2);
    TM2  := TvgToolManager.Create(DM2);
    DM2.AdoptComponents;
    Check('Instance adopted',       DM2.Instance = Inst, True);
    Check('PhysicalDevice adopted', DM2.PhysicalDevice = PD, True);
    Check('ScreenDevice adopted',   DM2.ScreenDevice = SD, True);
    Check('Linker adopted',         DM2.Linker = Lk, True);
    Check('PD.Instance linked',     PD.Instance = Inst, True);
    Check('SD.PhysicalDevice linked', SD.PhysicalDevice = PD, True);
    Check('Linker.ScreenDevice linked', Lk.ScreenDevice = SD, True);
    Check('Scene.Linker linked',    S2.Linker = Lk, True);
    Check('ToolManager linked to Linker and Scene', (TM2.Linker = Lk) and (TM2.Scene = S2), True);

    //a second scene/tool manager does not displace the first
    TvgScene.Create(DM2);
    TvgToolManager.Create(DM2);
    DM2.AdoptComponents;
    Check('first Scene kept',       DM2.Scene = S2, True);
    Check('first ToolManager kept', DM2.ToolManager = TM2, True);

    //removal: Notification clears the references
    FreeAndNil(S2);
    FreeAndNil(TM2);
    Check('Scene cleared on free',       DM2.Scene = nil, True);
    Check('ToolManager cleared on free', DM2.ToolManager = nil, True);
  finally
    DM2.Free;
  end;
  if Failures = 0 then
    Writeln('DataModuleWindowTest: all checks passed')
  else
  begin
    Writeln('DataModuleWindowTest: ', Failures, ' FAILED');
    Halt(1);
  end;
end.
