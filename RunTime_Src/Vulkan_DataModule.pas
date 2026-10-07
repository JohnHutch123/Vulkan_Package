(******************************************************************************
 *                                 DVVulkan                                   *
 ******************************************************************************
 *                                zlib license                                *
 *============================================================================*
 *                                                                            *
 * Copyright (C) 2021 Datavis (www.datavis.com.au) johnh@datavis.com.au       *
 *                                                                            *
 * This software is provided 'as-is', without any express or implied          *
 * warranty. In no event will the authors be held liable for any damages      *
 * arising from the use of this software.                                     *
 *                                                                            *
 * Permission is granted to anyone to use this software for any purpose,      *
 * including commercial applications, and to alter it and redistribute it     *
 * freely, subject to the following restrictions:                             *
 *                                                                            *
 * 1. The origin of this software must not be misrepresented; you must not    *
 *    claim that you wrote the original software. If you use this software    *
 *    in a product, an acknowledgement in the product documentation would be  *
 *    appreciated but is not required.                                        *
 * 2. Altered source versions must be plainly marked as such, and must not be *
 *    misrepresented as being the original software.                          *
 * 3. This notice may not be removed or altered from any source distribution. *
 *                                                                            *
 ******************************************************************************)

{ TvgVulkanDataModule

  A TDataModule that holds a Vulkan session, the way a data module holds a
  database connection and its datasets:

      TvgInstance
        +- TvgPhysicalDevice
             +- TvgScreenRenderDevice
                  +- TvgLinker  ->  TvgWindowVCL (any form)
                  +- TvgLinker  ->  TvgWindowVCL (a second window)
                  +- ...

  The session components are ordinary components: drop them from the palette
  (or use Build / Add Linker) and connect them in the Object Inspector:

      PhysicalDevice.Instance, ScreenDevice.PhysicalDevice,
      Linker.ScreenDevice, VulkanWindow.VulkanLink

  as a dataset's Connection is set.  Every window/linker pair connected under
  the instance is part of the session.  Setting Active on any of them at
  design time starts the whole session to test it (see VulkanPkg_DataModuleReg),
  much like setting a query's Active opens its connection.

  The published Instance / PhysicalDevice / ScreenDevice / Linker / Window
  are the module's primary chain: what Build creates and what Add Linker
  attaches to.  Enabling and checking the session always covers everything
  connected under Instance, not just the primary linker.

  This unit is RUNTIME code - it uses no design-time units - so an
  application's data module can descend from it.  It is compiled into
  VulkanPkg_VCLR280; the IDE side is in VulkanPkg_DataModuleReg and
  VulkanDataModuleEditFM.

  At run time call EnableSession once the forms holding the windows have
  their handles, e.g. from the main form's OnShow.

  Scene: Scene and Renderer hang off the primary Linker.  Both are part of
  the session - SessionProblem reports either one missing.  BuildSession
  creates the Scene and, when a renderer class is registered (see
  vgRegisterRenderEngine; Vulkan_Renderer_Single registers 'Single'), a
  Renderer of RendererType - blank takes the first registered.  Otherwise
  drop a renderer such as TvgRenderEngine_Single and assign Renderer.  LoadScene reads
  SceneFileName with a registered scene loader - SceneLoaderType names one
  (e.g. 'glTF'), or leave it blank to pick by file extension - or with the
  SceneLoader component if one is assigned.  LoadSceneOnEnable loads the file
  every time the session is enabled, at design time too, so the scene can be
  seen in the designer.  Loaders register in Vulkan_SceneLoaders.

  ToolManager (a TvgToolManager, or a descendant such as PRO's
  TvgEditToolManager) turns the window's mouse and keys into camera moves,
  picking and selection.  It is connected to the primary Linker, Scene and
  Renderer; ZoomAllOnLoad frames each loaded scene with it.  A second window
  wants its own tool manager on its own linker - set that linker's
  ToolManager (or the tool manager's Linker) in the Object Inspector.

  A TvgVulkanDataModule descendant needs a .dfm, as every TDataModule
  descendant does.  To build one purely in code use Create (on the base
  class, it calls CreateNew) or CreateNew:

      DM := TvgVulkanDataModule.Create(Self);
      DM.BuildSession;                       //+ Renderer and Scene
      DM.Window := VulkanWindow1;
      DM.AddLinker(VulkanWindow2);
      DM.BuildToolManager;
      DM.EnableSession;
      DM.LoadScene('C:\Models\Box.glb');     //loader picked by extension

  Failures (a session that can't start, a part that can't be made, a
  Window that is not a window) are reported with CustomAssert
  (Vulkan_Assert): logged, and raised as EvgVulkanAssertException at design
  time and in DEBUG builds.  In a release build the call logs the reason
  and returns with nothing changed - check CanEnableSession / SessionActive
  rather than relying on an exception.
}

unit Vulkan_DataModule;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vulkan_Assert,
  Vulkan_Components,
  Vulkan_Components_Lookups,
  Vulkan_Components_Scene_Renderer,
  Vulkan_SceneLoaders;

type
  EvgVulkanSessionError = class(Exception);

  { Creates one session component.  aIndex is its layout slot: 0 = instance,
    1 = physical device, 2 = screen device, 3.. = linkers, cSceneSlot =
    scene.  The designer uses it to place new components; code may ignore it. }
  TvgSessionComponentFactory = reference to function(aClass: TComponentClass; aIndex: Integer): TComponent;

const
  cSceneSlot       = 100;   //layout slot a factory gets for the scene
  cToolManagerSlot = 101;   //... and for the tool manager
  cRendererSlot    = 102;   //... and for the renderer

type
  TvgVulkanDataModule = class(TDataModule)
  private
    fInstance          : TvgInstance;
    fPhysicalDevice    : TvgPhysicalDevice;
    fScreenDevice      : TvgScreenRenderDevice;
    fLinker            : TvgLinker;

    fWindow            : TComponent;   //primary window; always supports IvgVulkanWindow
    fWindowIntf        : IvgVulkanWindow;

    fScene             : TvgScene;
    fRenderer          : TvgRenderEngine;
    fRendererType      : string;
    fSceneLoader       : TvgSceneLoaderStorer;
    fSceneLoaderType   : string;
    fSceneFileName     : string;
    fLoadSceneOnEnable : Boolean;
    fToolManager       : TvgToolManager;
    fZoomAllOnLoad     : Boolean;

    fOnSessionEnabled  : TNotifyEvent;
    fOnSessionDisabled : TNotifyEvent;

    procedure SetInstance(const Value: TvgInstance);
    procedure SetPhysicalDevice(const Value: TvgPhysicalDevice);
    procedure SetScreenDevice(const Value: TvgScreenRenderDevice);
    procedure SetLinker(const Value: TvgLinker);
    procedure SetWindow(const Value: TComponent);
    procedure SetScene(const Value: TvgScene);
    procedure SetRenderer(const Value: TvgRenderEngine);
    procedure SetSceneLoader(const Value: TvgSceneLoaderStorer);
    procedure SetToolManager(const Value: TvgToolManager);

    function  GetSessionActive: Boolean;
    procedure SetSessionActive(const Value: Boolean);

    procedure ReferenceChanged(aOld, aNew: TComponent);
    function  MakeUniqueName(const aBase: string): string;

  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;

  public
    { The base class has no .dfm, so Create on TvgVulkanDataModule itself
      falls back to CreateNew instead of raising EResNotFound.  Descendants
      with a .dfm stream it as usual. }
    constructor Create(AOwner: TComponent); override;
    constructor CreateNew(AOwner: TComponent; Dummy: Integer = 0); override;
    destructor Destroy; override;

    { Design time: gives each unassigned reference (Scene, ToolManager,
      Renderer, SceneLoader, Instance, devices, Linker) the first component of
      that kind this module owns, then links them.  The designer calls it after
      a component is dropped on the module: Notification runs inside the new
      component's constructor, too early to link it. }
    procedure AdoptComponents;

    { Creates whichever of Instance, PhysicalDevice, ScreenDevice, Linker,
      Renderer and Scene is missing, then wires the primary chain.  The
      Renderer is a registered class (RendererType); with none registered it
      is left for you to drop and assign.  Without a factory the components
      are created in code, owned by this module. }
    procedure BuildSession; overload;
    procedure BuildSession(const aFactory: TvgSessionComponentFactory); overload;

    { Adds another linker on ScreenDevice, optionally presenting to aWindow -
      one linker per window.  The first one added also becomes Linker. }
    function  AddLinker(const aWindow: IvgVulkanWindow = nil): TvgLinker; overload;
    function  AddLinker(const aWindow: IvgVulkanWindow; const aFactory: TvgSessionComponentFactory): TvgLinker; overload;

    { Links the primary chain together:
        PhysicalDevice.Instance, ScreenDevice.PhysicalDevice,
        Linker.ScreenDevice and Window.VulkanLink.
      A running session is disabled first. }
    procedure ConnectSession;

    { Creates Scene if missing and connects it (see ConnectScene). }
    procedure BuildScene; overload;
    procedure BuildScene(const aFactory: TvgSessionComponentFactory); overload;

    { Creates Renderer if missing, of the registered class RendererType
      names (blank: the first registered), and connects it.  Leaves it
      unassigned when no renderer is registered; asserts when RendererType
      names one that isn't. }
    procedure BuildRenderer; overload;
    procedure BuildRenderer(const aFactory: TvgSessionComponentFactory); overload;

    { Creates ToolManager if missing (camera orbit mode) and connects it. }
    procedure BuildToolManager; overload;
    procedure BuildToolManager(const aFactory: TvgSessionComponentFactory); overload;

    { Renderer.Linker, Scene.Linker and Renderer.Scene to the primary Linker,
      a default camera for an empty scene, and ToolManager to the Linker,
      Scene and Renderer.  Called by ConnectSession. }
    procedure ConnectScene;

    { Loads aFileName (SceneFileName when blank) into Scene with SceneLoader,
      or a loader of SceneLoaderType, or one chosen by the file's extension.
      Raises EvgSceneLoaderError with the reason when it can't. }
    procedure LoadScene(const aFileName: string = '');
    procedure ClearScene;

    { Every component connected under Instance: devices, linkers, windows,
      renderers and scenes. }
    procedure GetSessionComponents(aList: TList<TComponent>);
    function  SessionLinkers: TArray<TvgLinker>;

    { Empty when the session can be enabled, otherwise why it can't. }
    function  SessionProblem: string;
    function  CanEnableSession: Boolean;

    { CustomAsserts with SessionProblem (or the part that failed) when the
      session can't be started; nothing is left half enabled. }
    procedure EnableSession;
    procedure DisableSession;

    property  WindowIntf    : IvgVulkanWindow read fWindowIntf;


  published
    property Instance       : TvgInstance            read fInstance       write SetInstance;
    property PhysicalDevice : TvgPhysicalDevice      read fPhysicalDevice write SetPhysicalDevice;
    property ScreenDevice   : TvgScreenRenderDevice  read fScreenDevice   write SetScreenDevice;
    property Linker         : TvgLinker              read fLinker         write SetLinker;

    { The primary linker's window: any component implementing IvgVulkanWindow
      (TvgWindowVCL, TvgSDL2Window...), usually on another form.  A TComponent
      because interface properties are not streamed; SetWindow rejects a
      component that is not a window.  WindowIntf is the interface view. }
    property Window         : TComponent             read fWindow         write SetWindow;

    { Switches the whole session on/off.  Never stored: a session always
      starts disabled and is enabled in code (or from the designer). }
    property SessionActive  : Boolean read GetSessionActive write SetSessionActive stored False;

    { The primary linker's renderer and scene. }
    property Renderer       : TvgRenderEngine        read fRenderer       write SetRenderer;
    property Scene          : TvgScene               read fScene          write SetScene;

    { The registered renderer BuildSession / BuildRenderer create, e.g.
      'Single'.  Blank: the first one registered. }
    property RendererType   : string read fRendererType write fRendererType;

    { Optional loader component (with its own settings); without one a loader
      of SceneLoaderType - or picked by extension - is made for each load. }
    property SceneLoader    : TvgSceneLoaderStorer   read fSceneLoader    write SetSceneLoader;

    { A registered loader name, e.g. 'glTF'.  Blank: by file extension. }
    property SceneLoaderType : string read fSceneLoaderType write fSceneLoaderType;
    property SceneFileName   : string read fSceneFileName   write fSceneFileName;

    { Load SceneFileName each time the session is enabled (design time too). }
    property LoadSceneOnEnable : Boolean read fLoadSceneOnEnable write fLoadSceneOnEnable default False;

    { Mouse/keyboard tools for the primary window: camera, picking, selection. }
    property ToolManager    : TvgToolManager         read fToolManager    write SetToolManager;

    { After LoadScene, move the camera so the whole scene is in view. }
    property ZoomAllOnLoad  : Boolean read fZoomAllOnLoad write fZoomAllOnLoad default True;

    property OnSessionEnabled  : TNotifyEvent read fOnSessionEnabled  write fOnSessionEnabled;
    property OnSessionDisabled : TNotifyEvent read fOnSessionDisabled write fOnSessionDisabled;
  end;

{ Session helpers.  They work on any instance's tree, wherever its components
  live, so the designer can test a session from any of its components. }

{ The instance at the top of aComp's chain: aComp itself for an instance, up
  through devices, linkers (ScreenDevice) and windows (VulkanLink).  nil when
  aComp is not connected to one. }
function  vgSessionInstance(aComp: TComponent): TvgInstance;

{ The component a linker presents to (a VCL or SDL2 window), or nil. }
function  vgLinkerWindow(aLinker: TvgLinker): TComponent;

function  vgSessionLinkers(aInstance: TvgInstance): TArray<TvgLinker>;
procedure vgCollectSession(aInstance: TvgInstance; aList: TList<TComponent>);

function  vgSessionProblem(aInstance: TvgInstance): string;
function  vgSessionActive(aInstance: TvgInstance): Boolean;
procedure vgEnableSession(aInstance: TvgInstance);
procedure vgDisableSession(aInstance: TvgInstance);

resourcestring
  vgSesNoInstance       = 'No Vulkan Instance assigned to the session.';
  vgSesNoVulkan         = 'Vulkan is not installed on this computer (no Vulkan loader found).';
  vgSesNoPhysicalDevice = 'No Physical Device is connected to the Instance.';
  vgSesNoScreenDevice   = 'No Screen Render Device assigned to the session.';
  vgSesNoRenderer       = 'No Renderer assigned to the session.  Drop a renderer (e.g. TvgRenderEngine_Single) and set Renderer.';
  vgSesNoScene          = 'No Scene assigned to the session.  Use Add Scene (or Build) to create one.';
  vgSesNoRendererType   = 'No renderer is registered as ''%s''.';
  vgSesCantCreate       = 'Unable to create a %s.';
  vgSesLinkerNoWindow   = 'Linker %s has no window.  Set the window''s Linker to it.';
  vgSesNotAWindow       = '%s is not a Vulkan window (it does not implement IvgVulkanWindow).';
  vgSesNoWindowHandle   = 'Window %s has no window handle yet.  Enable the session once its form is showing.';
  vgSesFailed           = 'The Vulkan session failed to start.' + sLineBreak +
                          'Check the Vulkan error log for the reason.';
  vgSesLinkersFailed    = 'The Vulkan session failed to start: %s did not enable.' + sLineBreak +
                          'Check the Vulkan error log for the reason.';

implementation

const
  cPartNames : array[0..3] of string = ('vgInstance', 'vgPhysicalDevice', 'vgScreenDevice', 'vgLinker');

{ Session helpers }

function vgSessionInstance(aComp: TComponent): TvgInstance;
  Var Intf : IvgVulkanWindow;
begin
  Result := nil;

  If aComp is TvgInstance then
    Result := TvgInstance(aComp)
  else
  If aComp is TvgPhysicalDevice then
    Result := TvgPhysicalDevice(aComp).Instance
  else
  If aComp is TvgLogicalDevice then
  Begin
    Result := TvgLogicalDevice(aComp).Instance;
    If not assigned(Result) and assigned(TvgLogicalDevice(aComp).PhysicalDevice) then
      Result := TvgLogicalDevice(aComp).PhysicalDevice.Instance;
  End
  else
  If aComp is TvgLinker then
    Result := vgSessionInstance(TvgLinker(aComp).ScreenDevice)
  else
  If Supports(aComp, IvgVulkanWindow, Intf) then
    Result := vgSessionInstance(Intf.GetLinker);
end;

function vgLinkerWindow(aLinker: TvgLinker): TComponent;
  Var Intf : IvgVulkanWindow;
      O    : TObject;
begin
  Result := nil;
  If not assigned(aLinker) then exit;

  Intf := aLinker.WindowIntf;
  If not assigned(Intf) then exit;

  O := Intf as TObject;
  If O is TComponent then
    Result := TComponent(O);
end;

function vgSessionLinkers(aInstance: TvgInstance): TArray<TvgLinker>;
  Var List : TList<TvgLinker>;
      I, J : Integer;
      PD   : TvgPhysicalDevice;
      SD   : TvgScreenRenderDevice;
      L    : TvgLinker;
begin
  Result := nil;
  If not assigned(aInstance) then exit;

  List := TList<TvgLinker>.Create;
  Try
    For I := 0 to aInstance.DevicesCount - 1 do
    Begin
      PD := aInstance.Devices[I];
      If not assigned(PD) or not (PD.LogicalDevice is TvgScreenRenderDevice) then continue;
      SD := TvgScreenRenderDevice(PD.LogicalDevice);

      J := 0;
      L := SD.Linker[J];     //nil past the end
      While assigned(L) do
      Begin
        If List.IndexOf(L) = -1 then
          List.Add(L);
        Inc(J);
        L := SD.Linker[J];
      End;
    End;

    Result := List.ToArray;
  Finally
    List.Free;
  End;
end;

procedure vgCollectSession(aInstance: TvgInstance; aList: TList<TComponent>);

  Procedure Add(aComp: TComponent);
  Begin
    If assigned(aComp) and (aList.IndexOf(aComp) = -1) then
      aList.Add(aComp);
  End;

  Var I : Integer;
      PD: TvgPhysicalDevice;
      L : TvgLinker;
begin
  If not assigned(aInstance) or not assigned(aList) then exit;

  Add(aInstance);

  For I := 0 to aInstance.DevicesCount - 1 do
  Begin
    PD := aInstance.Devices[I];
    Add(PD);
    If assigned(PD) then
      Add(PD.LogicalDevice);
  End;

  For L in vgSessionLinkers(aInstance) do
  Begin
    Add(L);
    Add(vgLinkerWindow(L));
    Add(L.Renderer);
    Add(L.ToolManager);
    If L.Renderer is TvgRenderEngine then
      Add(TvgRenderEngine(L.Renderer).Scene);
  End;
end;

function vgSessionProblem(aInstance: TvgInstance): string;
  Var L : TvgLinker;
      W : TComponent;
begin
  Result := '';

  If not assigned(aInstance) then
    Exit(vgSesNoInstance);

  If aInstance.VulkanStatus <> VC_VULKAN_OK then
    Exit(vgSesNoVulkan);

  If aInstance.DevicesCount = 0 then
    Exit(vgSesNoPhysicalDevice);

  //every linker renders to a window: without one its surface can't be made
  For L in vgSessionLinkers(aInstance) do
  Begin
    W := vgLinkerWindow(L);
    If not assigned(W) then
      Exit(Format(vgSesLinkerNoWindow, [L.Name]));

    If (W is TWinControl) and not assigned(TWinControl(W).Parent) and
       not TWinControl(W).HandleAllocated then
      Exit(Format(vgSesNoWindowHandle, [W.Name]));
  End;
end;

function vgSessionActive(aInstance: TvgInstance): Boolean;
  Var L : TvgLinker;
begin
  Result := assigned(aInstance) and aInstance.Active;
  If not Result then exit;

  For L in vgSessionLinkers(aInstance) do
    If not L.Active then
      Exit(False);
end;

procedure InvalidateWindows(aInstance: TvgInstance);
  Var L : TvgLinker;
      W : TComponent;
begin
  For L in vgSessionLinkers(aInstance) do
  Begin
    W := vgLinkerWindow(L);
    If (W is TWinControl) and TWinControl(W).HandleAllocated then
      TWinControl(W).Invalidate;
  End;
end;

procedure vgDisableSession(aInstance: TvgInstance);
begin
  If not assigned(aInstance) then exit;
  If aInstance.State = vgcsInactive then exit;

  //the instance disables everything below it, top down
  aInstance.Active := False;

  InvalidateWindows(aInstance);
end;

procedure vgEnableSession(aInstance: TvgInstance);
  Var Problem : string;
      Failed  : string;
      L       : TvgLinker;
      W       : TComponent;
begin
  If vgSessionActive(aInstance) then exit;

  Problem := vgSessionProblem(aInstance);
  If Problem <> '' then
  Begin
    CustomAssert(False, Problem, aInstance);
    exit;
  End;

  For L in vgSessionLinkers(aInstance) do
  Begin
    W := vgLinkerWindow(L);
    If (W is TWinControl) and not TWinControl(W).HandleAllocated then
      TWinControl(W).HandleNeeded;
  End;

  //running but with a linker added since: restart so it comes up too
  If aInstance.State <> vgcsInactive then
    aInstance.Active := False;

  Try
    //cascades: instance -> physical devices -> screen device -> linkers -> scene
    aInstance.Active := True;
  Except
    vgDisableSession(aInstance);
    raise;
  End;

  If not vgSessionActive(aInstance) then
  Begin
    Failed := '';
    For L in vgSessionLinkers(aInstance) do
      If not L.Active then
      Begin
        If Failed <> '' then Failed := Failed + ', ';
        Failed := Failed + L.Name;
      End;

    vgDisableSession(aInstance);

    If Failed <> '' then
      CustomAssert(False, Format(vgSesLinkersFailed, [Failed]), aInstance)
    else
      CustomAssert(False, vgSesFailed, aInstance);
    exit;
  End;

  InvalidateWindows(aInstance);
end;

{ TvgVulkanDataModule }

constructor TvgVulkanDataModule.Create(AOwner: TComponent);
begin
  if ClassType = TvgVulkanDataModule then
    CreateNew(AOwner)
  else
    inherited Create(AOwner);
end;

constructor TvgVulkanDataModule.CreateNew(AOwner: TComponent; Dummy: Integer = 0);
begin
  //Create and the designer both come through here, before the .dfm is read
  fZoomAllOnLoad := True;
  inherited;
end;

destructor TvgVulkanDataModule.Destroy;
begin
  //every TvgBaseComponent must be inactive when it is freed
  Try
    DisableSession;
  Except
    //never raise out of a destructor
  End;

  inherited;
end;

procedure TvgVulkanDataModule.AdoptComponents;
  Var I : Integer;
      C : TComponent;
begin
  If (csLoading in ComponentState) or (csDestroying in ComponentState) then exit;

  //each setter rewires the session (ConnectSession), so a slot is only filled
  //when empty, and the module's own parts are never replaced
  For I := 0 to ComponentCount - 1 do
  Begin
    C := Components[I];

    If (C is TvgInstance)           and not assigned(fInstance)       then Instance       := TvgInstance(C)
    else
    If (C is TvgPhysicalDevice)     and not assigned(fPhysicalDevice) then PhysicalDevice := TvgPhysicalDevice(C)
    else
    If (C is TvgScreenRenderDevice) and not assigned(fScreenDevice)   then ScreenDevice   := TvgScreenRenderDevice(C)
    else
    If (C is TvgLinker)             and not assigned(fLinker)         then Linker         := TvgLinker(C)
    else
    If (C is TvgScene)              and not assigned(fScene)          then Scene          := TvgScene(C)
    else
    If (C is TvgRenderEngine)       and not assigned(fRenderer)       then Renderer       := TvgRenderEngine(C)
    else
    If (C is TvgSceneLoaderStorer)  and not assigned(fSceneLoader)    then SceneLoader    := TvgSceneLoaderStorer(C)
    else
    If (C is TvgToolManager)        and not assigned(fToolManager)    then ToolManager    := TvgToolManager(C);
  End;

  //a slot that was already filled still needs the new part linked to it
  ConnectSession;
end;

procedure TvgVulkanDataModule.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;


  If Operation <> opRemove then exit;

  If AComponent = fInstance       then fInstance       := nil;
  If AComponent = fPhysicalDevice then fPhysicalDevice := nil;
  If AComponent = fScreenDevice   then fScreenDevice   := nil;
  If AComponent = fLinker         then fLinker         := nil;
  If AComponent = fWindow         then Begin fWindow := nil; fWindowIntf := nil; End;
  If AComponent = fScene          then fScene          := nil;
  If AComponent = fRenderer       then fRenderer       := nil;
  If AComponent = fSceneLoader    then fSceneLoader    := nil;
  If AComponent = fToolManager    then fToolManager    := nil;


end;

procedure TvgVulkanDataModule.ReferenceChanged(aOld, aNew: TComponent);
begin
  If assigned(aOld) and (aOld.Owner <> Self) then
    aOld.RemoveFreeNotification(Self);

  If assigned(aNew) then
    aNew.FreeNotification(Self);   //the window normally lives on another form

  //links are stored on the components themselves: only rewire on a live edit
  If not (csLoading in ComponentState) then
    ConnectSession;
end;

procedure TvgVulkanDataModule.SetInstance(const Value: TvgInstance);
  Var Old : TComponent;
begin
  If fInstance = Value then exit;
  DisableSession;
  Old       := fInstance;
  fInstance := Value;
  ReferenceChanged(Old, Value);
end;

procedure TvgVulkanDataModule.SetPhysicalDevice(const Value: TvgPhysicalDevice);
  Var Old : TComponent;
begin
  If fPhysicalDevice = Value then exit;
  DisableSession;
  Old             := fPhysicalDevice;
  fPhysicalDevice := Value;
  ReferenceChanged(Old, Value);
end;

procedure TvgVulkanDataModule.SetScreenDevice(const Value: TvgScreenRenderDevice);
  Var Old : TComponent;
begin
  If fScreenDevice = Value then exit;
  DisableSession;
  Old           := fScreenDevice;
  fScreenDevice := Value;
  ReferenceChanged(Old, Value);
end;

procedure TvgVulkanDataModule.SetLinker(const Value: TvgLinker);
  Var Old : TComponent;
begin
  If fLinker = Value then exit;
  DisableSession;
  Old     := fLinker;
  fLinker := Value;
  ReferenceChanged(Old, Value);
end;

procedure TvgVulkanDataModule.SetWindow(const Value: TComponent);
  Var Old  : TComponent;
      Intf : IvgVulkanWindow;
begin
  If fWindow = Value then exit;

  Intf := nil;
  If assigned(Value) and not Supports(Value, IvgVulkanWindow, Intf) then
  Begin
    CustomAssert(False, Format(vgSesNotAWindow, [Value.Name]), Self);
    exit;
  End;

  DisableSession;
  Old         := fWindow;
  fWindow     := Value;
  fWindowIntf := Intf;
  ReferenceChanged(Old, Value);
end;

procedure TvgVulkanDataModule.SetScene(const Value: TvgScene);
  Var Old : TComponent;
begin
  If fScene = Value then exit;
  DisableSession;
  Old    := fScene;
  fScene := Value;
  ReferenceChanged(Old, Value);
end;

procedure TvgVulkanDataModule.SetRenderer(const Value: TvgRenderEngine);
  Var Old : TComponent;
begin
  If fRenderer = Value then exit;
  DisableSession;
  Old       := fRenderer;
  fRenderer := Value;
  ReferenceChanged(Old, Value);
end;

procedure TvgVulkanDataModule.SetSceneLoader(const Value: TvgSceneLoaderStorer);
begin
  If fSceneLoader = Value then exit;

  If assigned(fSceneLoader) and (fSceneLoader.Owner <> Self) then
    fSceneLoader.RemoveFreeNotification(Self);

  fSceneLoader := Value;

  If assigned(fSceneLoader) then
    fSceneLoader.FreeNotification(Self);
end;

procedure TvgVulkanDataModule.SetToolManager(const Value: TvgToolManager);
  Var Old : TComponent;
begin
  If fToolManager = Value then exit;
  DisableSession;
  Old          := fToolManager;
  fToolManager := Value;
  ReferenceChanged(Old, Value);
end;

function TvgVulkanDataModule.MakeUniqueName(const aBase: string): string;
  Var I : Integer;
begin
  I := 1;
  Repeat
    Result := aBase + IntToStr(I);
    Inc(I);
  Until FindComponent(Result) = nil;
end;

procedure TvgVulkanDataModule.BuildSession;
begin
  BuildSession(nil);
end;

procedure TvgVulkanDataModule.BuildSession(const aFactory: TvgSessionComponentFactory);

  Function MakePart(aClass: TComponentClass; aIndex: Integer): TComponent;
  Begin
    If assigned(aFactory) then
      Result := aFactory(aClass, aIndex)
    else
    Begin
      Result      := aClass.Create(Self);
      Result.Name := MakeUniqueName(cPartNames[aIndex]);
    End;

    CustomAssert(assigned(Result), Format(vgSesCantCreate, [aClass.ClassName]), Self);
  End;

begin
  DisableSession;

  If not assigned(fInstance) then
    Instance := TvgInstance(MakePart(TvgInstance, 0));

  If not assigned(fPhysicalDevice) then
    PhysicalDevice := TvgPhysicalDevice(MakePart(TvgPhysicalDevice, 1));

  If not assigned(fScreenDevice) then
    ScreenDevice := TvgScreenRenderDevice(MakePart(TvgScreenRenderDevice, 2));

  If not assigned(fLinker) then
    Linker := TvgLinker(MakePart(TvgLinker, 3));

  ConnectSession;

  //the rest of what SessionProblem asks for
  BuildRenderer(aFactory);
  BuildScene(aFactory);
end;

function TvgVulkanDataModule.AddLinker(const aWindow: IvgVulkanWindow): TvgLinker;
begin
  Result := AddLinker(aWindow, nil);
end;

function TvgVulkanDataModule.AddLinker(const aWindow: IvgVulkanWindow; const aFactory: TvgSessionComponentFactory): TvgLinker;
begin
  Result := nil;
  If not assigned(fScreenDevice) then
  Begin
    CustomAssert(False, vgSesNoScreenDevice, Self);
    exit;
  End;

  DisableSession;

  If assigned(aFactory) then
    Result := TvgLinker(aFactory(TvgLinker, 3 + Length(SessionLinkers)))
  else
  Begin
    Result      := TvgLinker.Create(Self);
    Result.Name := MakeUniqueName(cPartNames[3]);
  End;

  If not assigned(Result) then
  Begin
    CustomAssert(False, Format(vgSesCantCreate, [TvgLinker.ClassName]), Self);
    exit;
  End;

  If Result.ScreenDevice <> fScreenDevice then
    Result.ScreenDevice := fScreenDevice;

  If assigned(aWindow) and (aWindow.GetLinker <> Result) then
    aWindow.SetLinker(Result);

  If not assigned(fLinker) then
    Linker := Result;
end;

procedure TvgVulkanDataModule.ConnectSession;
begin
  DisableSession;

  //order is important: each link picks up the one above it
  If assigned(fPhysicalDevice) and assigned(fInstance) and
     (fPhysicalDevice.Instance <> fInstance) then
    fPhysicalDevice.Instance := fInstance;

  If assigned(fScreenDevice) and assigned(fPhysicalDevice) and
     (fScreenDevice.PhysicalDevice <> fPhysicalDevice) then
    fScreenDevice.PhysicalDevice := fPhysicalDevice;

  If assigned(fLinker) and assigned(fScreenDevice) and
     (fLinker.ScreenDevice <> fScreenDevice) then
    fLinker.ScreenDevice := fScreenDevice;

  If assigned(fWindowIntf) and assigned(fLinker) and
     (fWindowIntf.GetLinker <> fLinker) then
    fWindowIntf.SetLinker(fLinker);

  ConnectScene;
end;

procedure TvgVulkanDataModule.ConnectScene;
begin
  DisableSession;

  If assigned(fRenderer) and assigned(fLinker) and (fRenderer.Linker <> fLinker) then
    fRenderer.Linker := fLinker;

  If assigned(fScene) and assigned(fLinker) and (fScene.Linker <> fLinker) then
    fScene.Linker := fLinker;

  If assigned(fRenderer) and assigned(fScene) and (fRenderer.Scene <> fScene) then
    fRenderer.Scene := fScene;

  //adds one only when the scene has none
  If assigned(fScene) and assigned(fScene.Cameras) then
    fScene.Cameras.AddBaseCamera('Default');

  If assigned(fToolManager) then
  Begin
    //setting the tool manager's Linker also sets Linker.ToolManager
    If assigned(fLinker) and (fToolManager.Linker <> fLinker) then
      fToolManager.Linker := fLinker;

    If assigned(fScene) and (fToolManager.Scene <> fScene) then
      fToolManager.Scene := fScene;

    If assigned(fRenderer) and (fToolManager.Renderer <> fRenderer) then
      fToolManager.Renderer := fRenderer;
  End;
end;

procedure TvgVulkanDataModule.BuildToolManager;
begin
  BuildToolManager(nil);
end;

procedure TvgVulkanDataModule.BuildToolManager(const aFactory: TvgSessionComponentFactory);
  Var C : TComponent;
begin
  If assigned(fToolManager) then
  Begin
    ConnectScene;
    exit;
  End;

  If assigned(aFactory) then
    C := aFactory(TvgToolManager, cToolManagerSlot)
  else
  Begin
    C      := TvgToolManager.Create(Self);
    C.Name := MakeUniqueName('vgToolManager');
  End;

  If not (C is TvgToolManager) then
  Begin
    CustomAssert(False, Format(vgSesCantCreate, [TvgToolManager.ClassName]), Self);
    exit;
  End;

  //view the scene: left drag orbits, as in the SimpleTest sample
  TvgToolManager(C).ToolMode   := TMM_CAMERA;
  TvgToolManager(C).ActionMode := TAM_CAMERA_ORBIT;

  ToolManager := TvgToolManager(C);   //connects it
end;

procedure TvgVulkanDataModule.BuildScene;
begin
  BuildScene(nil);
end;

procedure TvgVulkanDataModule.BuildScene(const aFactory: TvgSessionComponentFactory);
  Var C : TComponent;
begin
  If not assigned(fScene) then
  Begin
    If assigned(aFactory) then
      C := aFactory(TvgScene, cSceneSlot)
    else
    Begin
      C      := TvgScene.Create(Self);
      C.Name := MakeUniqueName('vgScene');
    End;

    If not (C is TvgScene) then
    Begin
      CustomAssert(False, Format(vgSesCantCreate, [TvgScene.ClassName]), Self);
      exit;
    End;

    Scene := TvgScene(C);   //connects it
  End else
    ConnectScene;
end;

procedure TvgVulkanDataModule.BuildRenderer;
begin
  BuildRenderer(nil);
end;

procedure TvgVulkanDataModule.BuildRenderer(const aFactory: TvgSessionComponentFactory);
  Var RC : TvgRenderEngineClass;
      C  : TComponent;
begin
  If assigned(fRenderer) then
  Begin
    ConnectScene;
    exit;
  End;

  RC := vgFindRenderEngine(fRendererType);
  If not assigned(RC) then
  Begin
    //none registered: left to be dropped (SessionProblem says so); a name
    //that isn't registered is a mistake
    CustomAssert(fRendererType = '', Format(vgSesNoRendererType, [fRendererType]), Self);
    exit;
  End;

  If assigned(aFactory) then
    C := aFactory(RC, cRendererSlot)
  else
  Begin
    C      := RC.Create(Self);
    C.Name := MakeUniqueName('vgRenderer');
  End;

  If not (C is TvgRenderEngine) then
  Begin
    CustomAssert(False, Format(vgSesCantCreate, [RC.ClassName]), Self);
    exit;
  End;

  Renderer := TvgRenderEngine(C);   //connects it
end;

procedure TvgVulkanDataModule.LoadScene(const aFileName: string = '');
  Var FileName : string;
begin
  FileName := aFileName;
  If FileName = '' then
    FileName := fSceneFileName;

  vgLoadSceneFile(fScene, FileName, fSceneLoader, fSceneLoaderType);

  //False (nothing moved) when the viewport or the data's bounds aren't known yet
  If fZoomAllOnLoad and assigned(fToolManager) then
    fToolManager.ZoomAll;
end;

procedure TvgVulkanDataModule.ClearScene;
begin
  If assigned(fScene) then
    fScene.ClearScene;
end;

procedure TvgVulkanDataModule.GetSessionComponents(aList: TList<TComponent>);
begin
  vgCollectSession(fInstance, aList);
end;

function TvgVulkanDataModule.SessionLinkers: TArray<TvgLinker>;
begin
  Result := vgSessionLinkers(fInstance);
end;

function TvgVulkanDataModule.SessionProblem: string;
begin
  If not assigned(fInstance) then
    Exit(vgSesNoInstance);

  If not assigned(fPhysicalDevice) then
    Exit(vgSesNoPhysicalDevice);

  If not assigned(fScreenDevice) then
    Exit(vgSesNoScreenDevice);

  Result := vgSessionProblem(fInstance);
  If Result <> '' then exit;

  If not assigned(fRenderer) then
    Exit(vgSesNoRenderer);

  If not assigned(fScene) then
    Exit(vgSesNoScene);
end;

function TvgVulkanDataModule.CanEnableSession: Boolean;
begin
  Result := SessionProblem = '';
end;

function TvgVulkanDataModule.GetSessionActive: Boolean;
begin
  Result := vgSessionActive(fInstance);
end;

procedure TvgVulkanDataModule.SetSessionActive(const Value: Boolean);
begin
  If Value then
    EnableSession
  else
    DisableSession;
end;

procedure TvgVulkanDataModule.EnableSession;
  Var Problem : string;
begin
  If GetSessionActive then exit;

  Problem := SessionProblem;
  If Problem <> '' then
  Begin
    CustomAssert(False, Problem, Self);
    exit;
  End;

  ConnectSession;
  vgEnableSession(fInstance);

  //vgEnableSession asserted the reason; a release build carries on to here
  If not GetSessionActive then exit;

  //the session stays up if the file can't be read: the error says why, and
  //OnSessionEnabled still fires, as the session is enabled
  Try
    If fLoadSceneOnEnable and (fSceneFileName <> '') and assigned(fScene) then
      LoadScene;
  Finally
    If assigned(fOnSessionEnabled) and not (csDesigning in ComponentState) then
      fOnSessionEnabled(Self);
  End;
end;

procedure TvgVulkanDataModule.DisableSession;
  Var WasActive : Boolean;
begin
  If not assigned(fInstance) then exit;
  If fInstance.State = vgcsInactive then exit;

  WasActive := GetSessionActive;

  vgDisableSession(fInstance);

  If WasActive and assigned(fOnSessionDisabled) and not (csDesigning in ComponentState) then
    fOnSessionDisabled(Self);
end;

initialization
  //TvgScreenRenderDevice is not on the run time palette, so register all the
  //session classes for streaming a data module's .dfm at run time.
  RegisterClasses([TvgInstance, TvgPhysicalDevice, TvgScreenRenderDevice, TvgLinker, TvgScene, TvgToolManager]);

end.
