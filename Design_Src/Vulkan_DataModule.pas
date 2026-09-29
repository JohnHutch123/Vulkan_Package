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

  A TDataModule that holds one Vulkan session:

      TvgInstance -> TvgPhysicalDevice -> TvgScreenRenderDevice -> TvgLinker
                                                                     |
                                                   TvgWindowVCL (any form)

  The session components live on the data module like any other component
  (named, streamed in the .dfm, editable in the Object Inspector).  The
  module only keeps references to them, wires them together and switches the
  whole session on and off through the instance, which cascades down to the
  devices, the linker and its scene.

  This unit is RUNTIME code - it uses no design-time units - so that an
  application's data module can descend from it.  It is compiled into
  VulkanPkg_VCLR280; the IDE side (custom module, verbs, "New" wizard and the
  session editor) is in VulkanPkg_DataModuleReg and VulkanDataModuleEditFM.

  At design time use the data module's context menu (or the SessionActive
  property) to enable / disable the session.  At run time call EnableSession
  once the form holding Window has its handle, e.g. from the form's OnShow.

  A TvgVulkanDataModule needs a .dfm, as every TDataModule descendant does.
  To build one purely in code use CreateNew:

      DM := TvgVulkanDataModule.CreateNew(Self);
      DM.BuildSession;
      DM.Window := VulkanWindow1;
      DM.EnableSession;
}

unit Vulkan_DataModule;

interface

uses
  System.SysUtils,
  System.Classes,
  Vulkan_Components,
  Vulkan_WindowVCL;

type
  EvgVulkanSessionError = class(Exception);

  { Creates one session component.  aIndex is the position of the part in the
    chain (0 = instance .. 3 = linker) - the designer uses it to lay the new
    components out left to right. }
  TvgSessionComponentFactory = reference to function(aClass: TComponentClass; aIndex: Integer): TComponent;

  TvgVulkanDataModule = class(TDataModule)
  private
    fInstance          : TvgInstance;
    fPhysicalDevice    : TvgPhysicalDevice;
    fScreenDevice      : TvgScreenRenderDevice;
    fLinker            : TvgLinker;
    fWindow            : TvgWindowVCL;

    fOnSessionEnabled  : TNotifyEvent;
    fOnSessionDisabled : TNotifyEvent;

    procedure SetInstance(const Value: TvgInstance);
    procedure SetPhysicalDevice(const Value: TvgPhysicalDevice);
    procedure SetScreenDevice(const Value: TvgScreenRenderDevice);
    procedure SetLinker(const Value: TvgLinker);
    procedure SetWindow(const Value: TvgWindowVCL);

    function  GetSessionActive: Boolean;
    procedure SetSessionActive(const Value: Boolean);

    procedure ReferenceChanged(aOld, aNew: TComponent);
    function  MakeUniqueName(const aBase: string): string;

  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;

  public
    destructor Destroy; override;

    { Creates whichever of Instance, PhysicalDevice, ScreenDevice and Linker is
      missing, then wires the chain.  Without a factory the components are
      created in code, owned by this module. }
    procedure BuildSession; overload;
    procedure BuildSession(const aFactory: TvgSessionComponentFactory); overload;

    { Links the assigned parts together:
        PhysicalDevice.Instance, ScreenDevice.PhysicalDevice,
        Linker.ScreenDevice and Window.VulkanLink.
      A running session is disabled first. }
    procedure ConnectSession;

    { Empty when the session can be enabled, otherwise why it can't. }
    function  SessionProblem: string;
    function  CanEnableSession: Boolean;

    { Raises EvgVulkanSessionError when the session can't be started; nothing
      is left half enabled. }
    procedure EnableSession;
    procedure DisableSession;

  published
    property Instance       : TvgInstance            read fInstance       write SetInstance;
    property PhysicalDevice : TvgPhysicalDevice      read fPhysicalDevice write SetPhysicalDevice;
    property ScreenDevice   : TvgScreenRenderDevice  read fScreenDevice   write SetScreenDevice;
    property Linker         : TvgLinker              read fLinker         write SetLinker;

    { The VCL window the linker presents to.  Usually on another form. }
    property Window         : TvgWindowVCL           read fWindow         write SetWindow;

    { Switches the whole session on/off.  Never stored: a session always
      starts disabled and is enabled in code (or from the designer). }
    property SessionActive  : Boolean read GetSessionActive write SetSessionActive stored False;

    property OnSessionEnabled  : TNotifyEvent read fOnSessionEnabled  write fOnSessionEnabled;
    property OnSessionDisabled : TNotifyEvent read fOnSessionDisabled write fOnSessionDisabled;
  end;

resourcestring
  vgSesNoInstance       = 'No Vulkan Instance assigned to the session.';
  vgSesNoPhysicalDevice = 'No Physical Device assigned to the session.';
  vgSesNoScreenDevice   = 'No Screen Render Device assigned to the session.';
  vgSesNoWindow         = 'The Linker has no window.  Assign the session''s Window (a TvgWindowVCL).';
  vgSesNoWindowHandle   = 'The session''s Window has no window handle yet.  Enable the session once its form is showing.';
  vgSesFailed           = 'The Vulkan session failed to start.' + sLineBreak +
                          'Check the Vulkan error log for the reason.';

implementation

const
  cPartNames : array[0..3] of string = ('vgInstance', 'vgPhysicalDevice', 'vgScreenDevice', 'vgLinker');

{ TvgVulkanDataModule }

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

procedure TvgVulkanDataModule.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;

  If Operation <> opRemove then exit;

  If AComponent = fInstance       then fInstance       := nil;
  If AComponent = fPhysicalDevice then fPhysicalDevice := nil;
  If AComponent = fScreenDevice   then fScreenDevice   := nil;
  If AComponent = fLinker         then fLinker         := nil;
  If AComponent = fWindow         then fWindow         := nil;
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

procedure TvgVulkanDataModule.SetWindow(const Value: TvgWindowVCL);
  Var Old : TComponent;
begin
  If fWindow = Value then exit;
  DisableSession;
  Old     := fWindow;
  fWindow := Value;
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

    If not assigned(Result) then
      raise EvgVulkanSessionError.CreateFmt('Unable to create %s', [aClass.ClassName]);
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

  If assigned(fWindow) and assigned(fLinker) and
     (fWindow.VulkanLink <> fLinker) then
    fWindow.VulkanLink := fLinker;
end;

function TvgVulkanDataModule.SessionProblem: string;
begin
  Result := '';

  If not assigned(fInstance) then
    Exit(vgSesNoInstance);

  If not assigned(fPhysicalDevice) then
    Exit(vgSesNoPhysicalDevice);

  If not assigned(fScreenDevice) then
    Exit(vgSesNoScreenDevice);

  //the linker renders to a window: without one its surface can't be made
  If assigned(fLinker) then
  Begin
    If not assigned(fWindow) and not assigned(fLinker.WindowIntf) then
      Exit(vgSesNoWindow);

    If assigned(fWindow) and not assigned(fWindow.Parent) and
       not fWindow.HandleAllocated then
      Exit(vgSesNoWindowHandle);
  End;
end;

function TvgVulkanDataModule.CanEnableSession: Boolean;
begin
  Result := SessionProblem = '';
end;

function TvgVulkanDataModule.GetSessionActive: Boolean;
begin
  Result := assigned(fInstance) and fInstance.Active;

  If Result and assigned(fLinker) then
    Result := fLinker.Active;
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
    raise EvgVulkanSessionError.Create(Problem);

  ConnectSession;

  If assigned(fWindow) and not fWindow.HandleAllocated then
    fWindow.HandleNeeded;

  Try
    //cascades: instance -> physical device -> screen device -> linker(s) -> scene
    fInstance.Active := True;
  Except
    DisableSession;
    raise;
  End;

  If not GetSessionActive then
  Begin
    DisableSession;
    raise EvgVulkanSessionError.Create(vgSesFailed);
  End;

  If assigned(fWindow) then
    fWindow.Invalidate;

  If assigned(fOnSessionEnabled) and not (csDesigning in ComponentState) then
    fOnSessionEnabled(Self);
end;

procedure TvgVulkanDataModule.DisableSession;
  Var WasActive : Boolean;
begin
  If not assigned(fInstance) then exit;
  If fInstance.State = vgcsInactive then exit;

  WasActive := GetSessionActive;

  //the instance disables everything below it, top down
  fInstance.Active := False;

  If assigned(fWindow) and fWindow.HandleAllocated then
    fWindow.Invalidate;

  If WasActive and assigned(fOnSessionDisabled) and not (csDesigning in ComponentState) then
    fOnSessionDisabled(Self);
end;

initialization
  //TvgScreenRenderDevice is not on the palette, so register all the session
  //classes for streaming a data module's .dfm at run time.
  RegisterClasses([TvgInstance, TvgPhysicalDevice, TvgScreenRenderDevice, TvgLinker]);

end.
