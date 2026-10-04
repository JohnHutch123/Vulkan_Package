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
    - SessionActive reads False and SessionActive := True fails cleanly
      (the fake window can make no surface) rather than half enabling;
      := False is harmless;
    - freeing the window clears Window and WindowIntf. }

uses
  System.SysUtils,
  System.Classes,
  Vulkan,
  Vulkan_Components_Lookups,
  Vulkan_Components,
  Vulkan_DataModule;

type
  TFakeWindow = class(TComponent, IvgVulkanWindow)
  private
    fLinker : TvgLinker;
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

function TFakeWindow.GetLinker: TvgLinker;
begin
  Result := fLinker;
end;

procedure TFakeWindow.SetLinker(const Value: TvgLinker);
begin
  If fLinker = Value then exit;
  fLinker := Value;
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
begin
  DM := TvgVulkanDataModule.CreateNew(nil);
  W1 := TFakeWindow.Create(nil);
  W2 := TFakeWindow.Create(nil);
  Plain := TComponent.Create(nil);
  try
    Writeln('Window property');
    DM.Window := W1;
    Check('Window set', DM.Window = W1, True);
    Check('WindowIntf set', assigned(DM.WindowIntf), True);

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
    Check('linker knows the window', assigned(DM.Linker) and (DM.Linker.WindowIntf = IvgVulkanWindow(W1)), True);
    Check('vgSessionInstance(window) = Instance', vgSessionInstance(W1) = DM.Instance, True);
    Check('vgLinkerWindow = window', vgLinkerWindow(DM.Linker) = W1, True);

    Writeln('AddLinker');
    L2 := DM.AddLinker(W2);
    Check('second window linked', W2.GetLinker = L2, True);
    Check('second linker is not the primary', L2 <> DM.Linker, True);

    Writeln('SessionActive');
    Check('SessionActive False', DM.SessionActive, False);
    Check('a fake window passes SessionProblem (not a VCL control)', DM.SessionProblem = '', True);
    Raised := False;
    Try
      DM.SessionActive := True;
    Except
      on Exception do Raised := True;
    End;
    Check('enable with a surface-less window fails', Raised, True);
    Check('still not active after failed enable', DM.SessionActive, False);
    DM.SessionActive := False;
    Check('disable when inactive is harmless', DM.SessionActive, False);

    Writeln('Freeing the window');
    FreeAndNil(W1);
    Check('Window cleared', DM.Window = nil, True);
    Check('WindowIntf cleared', assigned(DM.WindowIntf), False);
  finally
    DM.Free;
    W2.Free;
    Plain.Free;
    W1.Free;
  end;

  if Failures = 0 then
    Writeln('DataModuleWindowTest: all checks passed')
  else
  begin
    Writeln('DataModuleWindowTest: ', Failures, ' FAILED');
    Halt(1);
  end;
end.
