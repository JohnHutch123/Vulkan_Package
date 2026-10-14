program FMXWindowTest;

{ TvgWindowFMX on a FireMonkey form (Windows).  Builds a session in code -
  instance, device, linker, single renderer, scene and tool manager - links
  it to a TvgWindowFMX filling the form, and loads Samples\OBJ Files\
  TeaPot.obj (or the file given on the command line), framed by ZoomAll.
  Left drag orbits, as in the VCL test.

  The window sits in a TLayout under a toolbar, so moving and resizing the
  native window with its FMX parent is exercised too: resize the form, and
  use the toolbar's buttons to hide/show it and move it between layouts. }

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  System.UITypes,
  System.IOUtils,
  FMX.Types,
  FMX.Forms,
  FMX.Controls,
  FMX.StdCtrls,
  FMX.Layouts,
  PasVulkan.Math.Double,
  Vulkan_Components_Lookups,
  Vulkan_Components,
  Vulkan_Renderer_Single,
  Vulkan_Components_Scene_Renderer,
  Vulkan_Components_Camera,
  Vulkan_SceneLoaders,
  Vulkan_Loader_OBJ,
  Vulkan_WindowFMX in '..\..\RunTime_Src\Vulkan_WindowFMX.pas';

type
  TTestForm = class(TForm)
  private
    fBar         : TToolBar;
    fStatus      : TLabel;
    fLeft        : TLayout;
    fRight       : TLayout;
    fWindow      : TvgWindowFMX;

    fInstance    : TvgInstance;
    fPhysical    : TvgPhysicalDevice;
    fScreen      : TvgScreenRenderDevice;
    fLinker      : TvgLinker;
    fRenderer    : TvgRenderEngine_Single;
    fScene       : TvgScene;
    fToolManager : TvgToolManager;
    fStarted     : Boolean;
    fAutoTimer   : TTimer;
    fWantStart   : Boolean;

    procedure AutoTimer(Sender: TObject);
    procedure WindowNativeReady(Sender: TObject);
    function  AddButton(const aText: string; aClick: TNotifyEvent): TButton;
    procedure StartClick(Sender: TObject);
    procedure HideClick(Sender: TObject);
    procedure MoveClick(Sender: TObject);
    procedure BuildSession;
    procedure LoadModel(const aFileName: string);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  public
    constructor Create(AOwner: TComponent); override;
  end;

constructor TTestForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Caption := 'TvgWindowFMX test';
  Width   := 1000;
  Height  := 700;
  OnClose := FormClose;

  fBar        := TToolBar.Create(Self);
  fBar.Parent := Self;

  AddButton('Start', StartClick);
  AddButton('Hide/Show', HideClick);
  AddButton('Move', MoveClick);

  fStatus          := TLabel.Create(Self);
  fStatus.Parent   := fBar;
  fStatus.Align    := TAlignLayout.Client;
  fStatus.Margins.Left := 8;
  fStatus.Text     := 'Press Start';

  fLeft        := TLayout.Create(Self);
  fLeft.Parent := Self;
  fLeft.Align  := TAlignLayout.Left;
  fLeft.Width  := 250;

  fRight        := TLayout.Create(Self);
  fRight.Parent := Self;
  fRight.Align  := TAlignLayout.Client;
  fRight.Margins.Rect := TRectF.Create(8, 8, 8, 8);

  fWindow            := TvgWindowFMX.Create(Self);
  fWindow.Parent     := fRight;
  fWindow.Align      := TAlignLayout.Client;
  fWindow.ClearColor := TAlphaColors.Navy;
  fWindow.OnNativeReady := WindowNativeReady;

{$IFDEF ANDROID}
  //deployed to assets\internal: the app's documents folder
  ShaderFolderPath := IncludeTrailingPathDelimiter(TPath.Combine(TPath.GetDocumentsPath, 'VulkanShaders'));
{$ENDIF}

  // /auto presses Start once the form is up (for unattended checks)
  if FindCmdLineSwitch('auto', ['/'], True) then
  begin
    fAutoTimer          := TTimer.Create(Self);
    fAutoTimer.Interval := 500;
    fAutoTimer.OnTimer  := AutoTimer;
  end;
end;

procedure TTestForm.AutoTimer(Sender: TObject);
begin
  fAutoTimer.Enabled := False;
  StartClick(nil);
end;

procedure TTestForm.WindowNativeReady(Sender: TObject);
begin
  //Android makes the surface some time after the form shows: a Start pressed
  //before then, or (on a phone) none at all, starts here
{$IFDEF ANDROID}
  fWantStart := True;
{$ENDIF}
  if fWantStart then
    StartClick(nil);
end;

function TTestForm.AddButton(const aText: string; aClick: TNotifyEvent): TButton;
begin
  Result         := TButton.Create(Self);
  Result.Parent  := fBar;
  Result.Align   := TAlignLayout.Left;
  Result.Width   := 90;
  Result.Text    := aText;
  Result.OnClick := aClick;
end;

procedure TTestForm.BuildSession;
begin
  fInstance := TvgInstance.Create(Self);
  fInstance.MemAllocation      := VG_VULKAN_MANAGE;
  fInstance.APIVersion         := VG_API_VERSION_1_3;
  fInstance.DescriptorIndexing := True;

  fPhysical := TvgPhysicalDevice.Create(Self);
  fPhysical.Instance := fInstance;

  fScreen := TvgScreenRenderDevice.Create(Self);
  fScreen.PhysicalDevice     := fPhysical;
  fScreen.DynamicRenderingON := True;

  fLinker := TvgLinker.Create(Self);
  fLinker.ScreenDevice := fScreen;
  fLinker.RenderTarget := RT_SCREEN;

  fRenderer := TvgRenderEngine_Single.Create(Self);
  fRenderer.Linker        := fLinker;
  fRenderer.SelectMode    := smStorageBuffer;
  fRenderer.RenderingMode := rmDynamic;

  fWindow.VulkanLink := fLinker;

  fRenderer.RenderPass.BuildStructure;

  fScene        := TvgScene.Create(Self);
  fScene.Linker := fLinker;
  fRenderer.Scene := fScene;
  fScene.ConnectRenderEngine(fRenderer);

  fToolManager := TvgToolManager.Create(Self);
  fToolManager.Linker     := fLinker;
  fToolManager.Scene      := fScene;
  fToolManager.Renderer   := fRenderer;
  fToolManager.ActionMode := TAM_CAMERA_ORBIT;

  fInstance.Active := True;
end;

procedure TTestForm.LoadModel(const aFileName: string);
var
  Warnings : TArray<string>;
  Camera   : TvgCamera;
  BMin,
  BMax     : TpvVector3D;
  Aspect   : Double;
begin
  vgLoadSceneFile(fScene, aFileName, Warnings);

  Camera := fScene.Cameras.GetActiveCamera;
  if not Assigned(Camera) then
  begin
    Camera := TvgCamera.Create;
    fScene.Cameras.AddCamera('Main', Camera);
  end;

  if fScene.GetDataBounds(BMin, BMax) then
  begin
    Aspect := 1;
    if fWindow.Height > 0 then
      Aspect := fWindow.Width / fWindow.Height;
    Camera.ZoomAll(BMin, BMax, Aspect);
  end;
end;

procedure TTestForm.StartClick(Sender: TObject);
var
  F : string;
{$IFNDEF ANDROID}
  I : Integer;
{$ENDIF}
begin
  if fStarted then exit;

  //no surface yet (Android lays the view out first): start when it comes
  if not fWindow.NativeReady then
  begin
    fWantStart   := True;
    fStatus.Text := 'Waiting for the native surface...';
{$IFDEF MSWINDOWS}
    fWindow.Repaint;     //Paint makes the window
{$ENDIF}
    exit;
  end;
  fStarted := True;

{$IFDEF ANDROID}
  F := TPath.Combine(TPath.GetDocumentsPath, 'TeaPot.obj');   //deployed to assets\internal
{$ELSE}
  F := '';
  for I := 1 to ParamCount do
    if not ParamStr(I).StartsWith('/') then
      F := ParamStr(I);
  if F = '' then
    F :=TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\OBJ Files\TeaPot.obj'));
{$ENDIF}

  try
    BuildSession;
    if fRenderer.ActiveRenderingMode = rmDynamic then
      fStatus.Text := 'Active: Dynamic rendering'
    else
      fStatus.Text := 'Active: Standard render pass';

    if FileExists(F) then
    begin
      LoadModel(F);
      fStatus.Text := fStatus.Text + ' - ' + ExtractFileName(F) + ' (drag to orbit)';
    end
    else
      fStatus.Text := fStatus.Text + ' - model not found: ' + F;

    fWindow.vgWindowInvalidate(True);
  except
    on E: Exception do
      fStatus.Text := 'Failed: ' + E.ClassName + ': ' + E.Message;
  end;
end;

procedure TTestForm.HideClick(Sender: TObject);
begin
  fWindow.Visible := not fWindow.Visible;
  if fWindow.Visible then
    fStatus.Text := 'Shown'
  else
    fStatus.Text := 'Hidden';
end;

procedure TTestForm.MoveClick(Sender: TObject);
begin
  if fWindow.Parent = fRight then
  begin
    fWindow.Parent := fLeft;
    fStatus.Text   := 'Moved to the left layout';
  end
  else
  begin
    fWindow.Parent := fRight;
    fStatus.Text   := 'Moved to the right layout';
  end;
end;

procedure TTestForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  //stop the session while the window still exists
  if Assigned(fScene) then
    fScene.ClearScene;
  if Assigned(fInstance) and fInstance.Active then
    fInstance.Active := False;
end;

var
  TestForm : TTestForm;

begin
  ReportMemoryLeaksOnShutdown := False;
  Application.Initialize;
  Application.CreateForm(TTestForm, TestForm);
  Application.Run;
end.
