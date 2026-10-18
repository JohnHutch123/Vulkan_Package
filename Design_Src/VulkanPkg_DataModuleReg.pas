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

{ IDE registration for TvgVulkanDataModule.

    * Custom module - the designer shows the module's published session
      properties (Instance, PhysicalDevice, ScreenDevice, Linker, Window,
      SessionActive) in the Object Inspector, and its context menu (right
      click on the module's background) gets:
          Edit Vulkan Session...
          Build Vulkan Session
          Enable / Disable Vulkan Session
          Add Linker (another window)
          Add Scene
          Add Tool Manager
          Arrange Session Icons
          Load Scene File...
    * Active property editor on every session component (instance, devices,
      linkers, TvgWindowVCL): setting Active to True at design time starts the
      whole session the component is connected to - every device, linker and
      window under its instance - the way setting a dataset's Active opens its
      connection.  If it can't start, the reason is shown and nothing is left
      half enabled.  Setting it False shuts that component down as before.
    * File > New > Other > Delphi Files > "Vulkan Session Data Module" creates
      a new unit whose data module descends from TvgVulkanDataModule.
    * The session components (TvgScreenRenderDevice, TvgScene,
      TvgToolManager ...) go on the palette from VulkanPkg_Designers, so
      each class is registered once.

  Scenes: Add Scene creates a TvgScene connected to the primary linker and
  renderer; Load Scene... picks a file and loads it with a registered scene
  loader (by SceneLoaderType, or by extension).  SceneLoaderType drops down
  the registered loaders; SceneFileName has a file-open button.  Any
  TvgScene also gets "Load Scene File..." / "Clear Scene" on its menu.
  Loaders register themselves in Vulkan_SceneLoaders.

  Extra windows: drop another TvgLinker (or use Add Linker), set its
  ScreenDevice, and set the second TvgWindowVCL's VulkanLink to it - all
  from the Object Inspector's drop downs, across forms.  The editor and the
  Active test cover every linker connected under the instance.

  Design time only: in the core design package with VulkanPkg_Designers
  (VulkanPkgDxxx, e.g. VulkanPkgD290 for Delphi 12), which requires the VCL
  runtime package for Vulkan_DataModule. }

unit VulkanPkg_DataModuleReg;

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.TypInfo,
  System.Types,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Dialogs,
  Vcl.Forms,
  DesignIntf,
  DesignEditors,
  VCLEditors,
  DMForm,
  ToolsAPI,
  Vulkan_Assert,
  Vulkan_Components,
  Vulkan_Components_Scene_Renderer,
  Vulkan_SceneLoaders,
//  Vulkan_WindowVCL,
  Vulkan_DataModule,
  VulkanDataModuleEditFM;

type
  { IOTARepositoryWizard.GetGlyph returns Cardinal up to Delphi 11 and THandle
    from Delphi 12 on (they differ on Win64). }
  {$IF CompilerVersion >= 36}
  TvgWizardGlyph = THandle;
  {$ELSE}
  TvgWizardGlyph = Cardinal;
  {$IFEND}

  { A component dropped on a TvgVulkanDataModule is linked into its session
    (Scene.Linker, ToolManager.Scene ...).  Done here, once the designer has
    finished creating it: the module's Notification runs inside the new
    component's constructor, when nothing can be linked to it yet. }
  TvgModuleDropNotification = class(TInterfacedObject, IDesignNotification)
  public
    procedure ItemDeleted(const ADesigner: IDesigner; AItem: TPersistent);
    procedure ItemInserted(const ADesigner: IDesigner; AItem: TPersistent);
    procedure ItemsModified(const ADesigner: IDesigner);
    procedure SelectionChanged(const ADesigner: IDesigner; const ASelection: IDesignerSelections);
    procedure DesignerOpened(const ADesigner: IDesigner; AResurrecting: Boolean);
    procedure DesignerClosed(const ADesigner: IDesigner; ADestroying: Boolean);
  end;

  { Active on a session component: True tests the whole session.  Shown as
    a check box (TBooleanProperty); a click on it goes through SetValue,
    where TBooleanProperty would set the bare property. }
  TvgSessionActiveProperty = class(TBooleanProperty, ICustomPropertyMessage)
  public
    procedure SetValue(const Value: string); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer;
      InNameRect: Boolean; const ItemRect: TRect; var Handled: Boolean);
  end;

  { SceneLoaderType: the registered scene loaders. }
  TvgSceneLoaderTypeProperty = class(TStringProperty)
  public
    function  GetAttributes: TPropertyAttributes; override;
    procedure GetValues(Proc: TGetStrProc); override;
  end;

  { RendererType: the registered renderers. }
  TvgRendererTypeProperty = class(TStringProperty)
  public
    function  GetAttributes: TPropertyAttributes; override;
    procedure GetValues(Proc: TGetStrProc); override;
  end;

  { A component reference whose drop-down also lists the matching components
    on every other module open in the IDE - e.g. a data module's linker for
    a window's VulkanLink - as Module.Component.  Picking one from a module
    this one does not use yet adds that module's unit to its uses clause
    (IDesigner.MakeComponentLinkable); the standard drop-down only lists the
    modules already used.  Used for every TvgLinker property. }
  TvgCrossModuleProperty = class(TComponentProperty)
  protected
    function  Accepts(aComp: TComponent): Boolean; virtual;
  public
    procedure GetValues(Proc: TGetStrProc); override;
    procedure SetValue(const Value: string); override;
  end;

  { TvgVulkanDataModule.Window: a window (IvgVulkanWindow) on any open form. }
  TvgWindowRefProperty = class(TvgCrossModuleProperty)
  protected
    function  Accepts(aComp: TComponent): Boolean; override;
  end;

  { SceneFileName: file-open dialog filtered to the registered formats. }
  TvgSceneFileNameProperty = class(TStringProperty)
  public
    function  GetAttributes: TPropertyAttributes; override;
    procedure Edit; override;
  end;

  { Load / clear any TvgScene from its context menu. }
  TvgSceneEditor = class(TComponentEditor)
  public
    function  GetVerbCount: Integer; override;
    function  GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
  end;

  TvgVulkanDataModuleCustomModule = class(TDataModuleCustomModule)
  public
    function  GetVerbCount: Integer; override;
    function  GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
  end;

  { File > New wizard }
  TvgVulkanDataModuleWizard = class(TNotifierObject, IOTAWizard, IOTARepositoryWizard,
                                    IOTARepositoryWizard60, IOTARepositoryWizard80, IOTAFormWizard)
  public
    //IOTAWizard
    function  GetIDString: string;
    function  GetName: string;
    function  GetState: TWizardState;
    procedure Execute;
    //IOTARepositoryWizard
    function  GetAuthor: string;
    function  GetComment: string;
    function  GetPage: string;
    function  GetGlyph: TvgWizardGlyph;
    //IOTARepositoryWizard60
    function  GetDesigner: string;
    //IOTARepositoryWizard80
    function  GetGalleryCategory: IOTAGalleryCategory;
    function  GetPersonality: string;
  end;

  TvgVulkanDataModuleCreator = class(TInterfacedObject, IOTACreator, IOTAModuleCreator)
  public
    //IOTACreator
    function  GetCreatorType: string;
    function  GetExisting: Boolean;
    function  GetFileSystem: string;
    function  GetOwner: IOTAModule;
    function  GetUnnamed: Boolean;
    //IOTAModuleCreator
    function  GetAncestorName: string;
    function  GetImplFileName: string;
    function  GetIntfFileName: string;
    function  GetFormName: string;
    function  GetMainForm: Boolean;
    function  GetShowForm: Boolean;
    function  GetShowSource: Boolean;
    function  NewFormFile(const FormIdent, AncestorIdent: string): IOTAFile;
    function  NewImplSource(const ModuleIdent, FormIdent, AncestorIdent: string): IOTAFile;
    function  NewIntfSource(const ModuleIdent, FormIdent, AncestorIdent: string): IOTAFile;
    procedure FormCreated(const FormEditor: IOTAFormEditor);
  end;

  TvgSourceFile = class(TInterfacedObject, IOTAFile)
  private
    fSource : string;
  public
    constructor Create(const aSource: string);
    function GetSource: string;
    function GetAge: TDateTime;
  end;

{ Creates the missing session components through the designer, so they are
  named, selectable and streamed like dropped components. }
procedure BuildSessionInDesigner(aModule: TvgVulkanDataModule; const aDesigner: IDesigner);

{ Adds a linker on the module's ScreenDevice through the designer. }
procedure AddLinkerInDesigner(aModule: TvgVulkanDataModule; const aDesigner: IDesigner);

{ Creates the module's Scene through the designer and connects it. }
procedure BuildSceneInDesigner(aModule: TvgVulkanDataModule; const aDesigner: IDesigner);

{ Creates the module's ToolManager through the designer and connects it. }
procedure BuildToolManagerInDesigner(aModule: TvgVulkanDataModule; const aDesigner: IDesigner);

{ Lays out every component on the module in Build's columns: Instance,
  devices; linkers; renderer, scene, tool manager; then anything else.  The
  positions are stored (DesignInfo) and the open designer's icons moved.
  False when some icons could not be moved on screen - they move when the
  module is closed and reopened. }
function  ArrangeSessionInDesigner(aModule: TvgVulkanDataModule; const aDesigner: IDesigner): Boolean;

{ Asks for a scene file (aAsk, or no SceneFileName yet), enables the session
  when it can and loads the file, so the scene shows in the designer. }
procedure LoadSceneInDesigner(aModule: TvgVulkanDataModule; const aDesigner: IDesigner; aAsk: Boolean);

{ Open dialog for a scene file; aFileName in and out. }
function  PickSceneFile(var aFileName: string): Boolean;

{ Marks the module and the window's form as modified. }
procedure NotifySessionModified(aModule: TvgVulkanDataModule; const aDesigner: IDesigner);

procedure Register;

implementation

resourcestring
  vgDMWizardName    = 'Vulkan Session Data Module';
  vgDMWizardComment = 'A data module holding a Vulkan session (Instance, Physical Device, ' +
                      'Screen Render Device and Linker) to connect to a TvgWindowVCL.';
  vgDMAbout         = 'Vulkan Session Data Module'#13'built by Datavis';

const
  cVerbEdit      = 0;
  cVerbBuild     = 1;
  cVerbAddLinker = 2;
  cVerbAddScene  = 3;
  cVerbLoadScene = 4;
  cVerbAddTools  = 5;
  cVerbArrange   = 6;
  cVerbToggle    = 7;
  cVerbAbout     = 8;
  cVerbCount     = 9;

  cUnitSource =
    'unit %0:s;'                                                   + sLineBreak +
                                                                     sLineBreak +
    'interface'                                                    + sLineBreak +
                                                                     sLineBreak +
    'uses'                                                         + sLineBreak +
    '  System.SysUtils, System.Classes,'                           + sLineBreak +
    '  Vulkan_Components, Vulkan_WindowVCL, Vulkan_DataModule;'    + sLineBreak +
                                                                     sLineBreak +
    'type'                                                         + sLineBreak +
    '  T%1:s = class(T%2:s)'                                       + sLineBreak +
    '  private'                                                    + sLineBreak +
    '    { Private declarations }'                                 + sLineBreak +
    '  public'                                                     + sLineBreak +
    '    { Public declarations }'                                  + sLineBreak +
    '  end;'                                                       + sLineBreak +
                                                                     sLineBreak +
    'var'                                                          + sLineBreak +
    '  %1:s: T%1:s;'                                               + sLineBreak +
                                                                     sLineBreak +
    'implementation'                                               + sLineBreak +
                                                                     sLineBreak +
    '{%%CLASSGROUP ''Vcl.Controls.TControl''}'                     + sLineBreak +
                                                                     sLineBreak +
    '{$R *.dfm}'                                                   + sLineBreak +
                                                                     sLineBreak +
    'end.'                                                         + sLineBreak;

var
  DropNotification : IDesignNotification;

procedure TvgModuleDropNotification.ItemInserted(const ADesigner: IDesigner; AItem: TPersistent);
begin
  If (AItem is TComponent) and (TComponent(AItem).Owner is TvgVulkanDataModule) then
    TvgVulkanDataModule(TComponent(AItem).Owner).AdoptComponents;
end;

procedure TvgModuleDropNotification.ItemDeleted(const ADesigner: IDesigner; AItem: TPersistent);
begin
end;

procedure TvgModuleDropNotification.ItemsModified(const ADesigner: IDesigner);
begin
end;

procedure TvgModuleDropNotification.SelectionChanged(const ADesigner: IDesigner; const ASelection: IDesignerSelections);
begin
end;

procedure TvgModuleDropNotification.DesignerOpened(const ADesigner: IDesigner; AResurrecting: Boolean);
begin
end;

procedure TvgModuleDropNotification.DesignerClosed(const ADesigner: IDesigner; ADestroying: Boolean);
begin
end;

procedure Register;
begin
  DropNotification := TvgModuleDropNotification.Create;
  RegisterDesignNotification(DropNotification);

 // RegisterComponents('Vulkan Graphics', []);

  RegisterComponentEditor(TvgScene, TvgSceneEditor);

  RegisterPropertyEditor(TypeInfo(string), TvgVulkanDataModule, 'SceneLoaderType', TvgSceneLoaderTypeProperty);
  RegisterPropertyEditor(TypeInfo(string), TvgVulkanDataModule, 'SceneFileName',   TvgSceneFileNameProperty);
  RegisterPropertyEditor(TypeInfo(string), TvgVulkanDataModule, 'RendererType',    TvgRendererTypeProperty);

  //links across forms and data modules, adding the uses clause as needed
  RegisterPropertyEditor(TypeInfo(TvgLinker),  nil,                 '',       TvgCrossModuleProperty);
  RegisterPropertyEditor(TypeInfo(TComponent), TvgVulkanDataModule, 'Window', TvgWindowRefProperty);

  RegisterCustomModule(TvgVulkanDataModule, TvgVulkanDataModuleCustomModule);

  RegisterPropertyEditor(TypeInfo(Boolean), TvgBaseComponent, 'Active', TvgSessionActiveProperty);
//  RegisterPropertyEditor(TypeInfo(Boolean), TvgWindowVCL,     'Active', TvgSessionActiveProperty);

  RegisterPackageWizard(TvgVulkanDataModuleWizard.Create);
end;

procedure NotifySessionModified(aModule: TvgVulkanDataModule; const aDesigner: IDesigner);
  Var D : IDesigner;
begin
  If assigned(aDesigner) then
    aDesigner.Modified;

  //Window.VulkanLink lives on the window's own form
  If assigned(aModule) and assigned(aModule.Window) and
     Supports(FindRootDesigner(aModule.Window), IDesigner, D) and (D <> aDesigner) then
    D.Modified;
end;

{ Where Build / Add place the parts on the module: three columns, each read
  top to bottom, one part per row:

      Instance          Linker 1          Renderer
      Physical Device   Linker 2          Scene
      Screen Device     ...               Tool Manager

  A column is wide enough for the IDE's component captions (names such as
  vgScreenRenderDevice1), and the rows far enough apart to pick each icon. }
const
  //left edge of each column's icons: session chain, linkers, scene side,
  //then anything else
  cLayoutColumnX : array[0..3] of Integer = (75, 200, 360, 520);
  cLayoutTop     = 32;
  cLayoutRow     = 80;    //row pitch
  cLayoutCell    = 120;   //icons nearer than this across are in the same column

{ True when a component of aModule already sits in the cell at aLeft,aTop:
  a part kept from an earlier build, or one the user placed there. }
function CellTaken(aModule: TvgVulkanDataModule; aLeft, aTop: Integer): Boolean;
  Var I    : Integer;
      X, Y : Integer;
begin
  Result := False;
  For I := 0 to aModule.ComponentCount - 1 do
  Begin
    //never placed by the designer (made in code): not on the module's surface
    If aModule.Components[I].DesignInfo = 0 then continue;

    //a non-visual component's designer position: Left in Lo, Top in Hi
    X := SmallInt(LongRec(aModule.Components[I].DesignInfo).Lo);
    Y := SmallInt(LongRec(aModule.Components[I].DesignInfo).Hi);
    If (Abs(X - aLeft) < cLayoutCell div 2) and (Abs(Y - aTop) < cLayoutRow div 2) then
      Exit(True);
  End;
end;

{ Arrange.  The designer shows each non-visual component as a small child
  window of class TContainer, placed at its DesignInfo when the module is
  opened; there is no designer call to move one.  So the new position goes
  into DesignInfo (what the .dfm stores) and the icon's window is moved to
  match, found by where it stands now. }

function DesignPos(aComp: TComponent): TPoint;
begin
  Result.X := SmallInt(LongRec(aComp.DesignInfo).Lo);
  Result.Y := SmallInt(LongRec(aComp.DesignInfo).Hi);
end;

procedure SetDesignPos(aComp: TComponent; aX, aY: Integer);
begin
  aComp.DesignInfo := Longint((Cardinal(Word(aY)) shl 16) or Word(aX));
end;

{ The form the IDE edits aModule on, or nil. }
function DesignerSurface(aModule: TvgVulkanDataModule): TCustomForm;
  Var I : Integer;
      F : TCustomForm;
      D : IDesigner;
begin
  Result := nil;
  For I := 0 to Screen.CustomFormCount - 1 do
  Begin
    F := Screen.CustomForms[I];
    If assigned(F.Designer) and Supports(F.Designer, IDesigner, D) and (D.Root = aModule) then
      Exit(F);
  End;
end;

function CollectWindow(aWnd: HWND; aList: LPARAM): BOOL; stdcall;
begin
  TList<HWND>(aList).Add(aWnd);
  Result := True;
end;

function IsIconWindow(aWnd: HWND): Boolean;
  Var Buf : array[0..63] of Char;
begin
  Result := (GetClassName(aWnd, Buf, Length(Buf)) > 0) and (string(Buf) = 'TContainer');
end;

{ A window's bounds in its parent's client coordinates. }
function WindowBounds(aWnd: HWND): TRect;
begin
  GetWindowRect(aWnd, Result);
  MapWindowPoints(0, GetParent(aWnd), Result, 2);
end;

{ The caption window the designer shows under an icon (Show component
  captions): a sibling just below it, centred on it.  0 when there is none. }
function CaptionWindow(aIcon: HWND; aWindows: TList<HWND>): HWND;
  Var Icon, R : TRect;
      Mid     : Integer;
      W       : HWND;
      Gap     : Integer;
begin
  Result := 0;
  Icon   := WindowBounds(aIcon);
  Mid    := (Icon.Left + Icon.Right) div 2;
  Gap    := MaxInt;
  For W in aWindows do
  Begin
    If (W = aIcon) or (GetParent(W) <> GetParent(aIcon)) or IsIconWindow(W) or
       not IsWindowVisible(W) then continue;

    R := WindowBounds(W);
    If (R.Top >= Icon.Bottom - 4) and (R.Top <= Icon.Bottom + 24) and
       (R.Left <= Mid) and (R.Right >= Mid) and (Abs(R.Top - Icon.Bottom) < Gap) then
    Begin
      Result := W;
      Gap    := Abs(R.Top - Icon.Bottom);
    End;
  End;
end;

{ Moves a designer window by aDX, aDY: through its VCL control when it is
  one, so the control's own Left/Top stay right. }
procedure MoveWindowBy(aWnd: HWND; aDX, aDY: Integer);
  Var Ctl : TWinControl;
      R   : TRect;
begin
  If (aWnd = 0) or ((aDX = 0) and (aDY = 0)) then exit;

  Ctl := FindControl(aWnd);
  If assigned(Ctl) then
    Ctl.SetBounds(Ctl.Left + aDX, Ctl.Top + aDY, Ctl.Width, Ctl.Height)
  else
  Begin
    R := WindowBounds(aWnd);
    SetWindowPos(aWnd, 0, R.Left + aDX, R.Top + aDY, 0, 0,
                 SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE);
  End;
end;

{ Every window on aModule's designer surface; empty when it is not open. }
procedure SurfaceWindows(aModule: TvgVulkanDataModule; aList: TList<HWND>);
  Var Surface : TCustomForm;
begin
  aList.Clear;
  Surface := DesignerSurface(aModule);
  If assigned(Surface) and Surface.HandleAllocated then
    EnumChildWindows(Surface.Handle, @CollectWindow, LPARAM(aList));
end;

{ Puts a component the designer has just created at aX,aY.  The designer
  places a new icon where it likes, so its DesignInfo is set and its icon -
  the one icon window that was not there before (aBefore) - and caption
  moved there. }
procedure PlaceNewComponent(aModule: TvgVulkanDataModule; aComp: TComponent;
                            aX, aY: Integer; aBefore: TList<HWND>);
  Var After : TList<HWND>;
      W     : HWND;
      Icon  : HWND;
      Cap   : HWND;
      P     : TPoint;
begin
  If not assigned(aComp) then exit;
  SetDesignPos(aComp, aX, aY);

  After := TList<HWND>.Create;
  Try
    SurfaceWindows(aModule, After);

    Icon := 0;
    For W in After do
      If IsIconWindow(W) and (aBefore.IndexOf(W) = -1) then
      Begin
        Icon := W;
        Break;
      End;
    If Icon = 0 then exit;    //not shown yet: DesignInfo places it

    Cap := CaptionWindow(Icon, After);
    P   := WindowBounds(Icon).TopLeft;
    MoveWindowBy(Icon, aX - P.X, aY - P.Y);
    MoveWindowBy(Cap,  aX - P.X, aY - P.Y);
  Finally
    After.Free;
  End;
end;

{ Where Build / Add put each part (see the layout above), on the designer. }
function DesignerFactory(aModule: TvgVulkanDataModule; const aDesigner: IDesigner): TvgSessionComponentFactory;
  Var D : IDesigner;
begin
  D := aDesigner;
  Result :=
    function(aClass: TComponentClass; aIndex: Integer): TComponent
      Var Col, Row : Integer;
          X, Y     : Integer;
          Before   : TList<HWND>;
    begin
      Case aIndex of
        cRendererSlot    : Begin Col := 2; Row := 0; End;
        cSceneSlot       : Begin Col := 2; Row := 1; End;
        cToolManagerSlot : Begin Col := 2; Row := 2; End;
      else
        If aIndex < 3 then
        Begin
          Col := 0;              //instance, physical device, screen device
          Row := aIndex;
        End else
        Begin
          Col := 1;              //linkers, in the order they are added
          Row := aIndex - 3;
        End;
      End;

      X := cLayoutColumnX[Col];
      Y := cLayoutTop  + Row * cLayoutRow;

      //never on top of a part that is already there: next free row down
      While CellTaken(aModule, X, Y) do
        Inc(Y, cLayoutRow);

      Before := TList<HWND>.Create;
      Try
        SurfaceWindows(aModule, Before);
        Result := D.CreateComponent(aClass, aModule, X, Y, 0, 0);
        PlaceNewComponent(aModule, Result, X, Y, Before);
      Finally
        Before.Free;
      End;
    end;
end;

function ArrangeSessionInDesigner(aModule: TvgVulkanDataModule; const aDesigner: IDesigner): Boolean;
  Var Cols      : array[0..3] of TList<TComponent>;
      Comps     : TList<TComponent>;
      Targets   : TList<TPoint>;
      AllWnds   : TList<HWND>;
      Icons     : TList<HWND>;
      IconOf    : TDictionary<TComponent, HWND>;
      CaptionOf : TDictionary<TComponent, HWND>;
      Surface   : TCustomForm;
      C         : TComponent;
      L         : TvgLinker;
      Old, P    : TPoint;
      I, Row    : Integer;
      Best, Cap : HWND;
      DX, DY    : Integer;

  Procedure Put(aCol: Integer; aComp: TComponent);
    Var K : Integer;
  Begin
    //only the module's own parts: a window or linker on a form stays put
    If not assigned(aComp) or (aComp.Owner <> aModule) then exit;
    For K := 0 to 3 do
      If Cols[K].IndexOf(aComp) <> -1 then exit;
    Cols[aCol].Add(aComp);
  End;

begin
  Result := True;
  If not assigned(aModule) then exit;

  For I := 0 to 3 do
    Cols[I] := TList<TComponent>.Create;
  Comps   := TList<TComponent>.Create;
  Targets := TList<TPoint>.Create;
  AllWnds   := TList<HWND>.Create;
  Icons     := TList<HWND>.Create;
  IconOf    := TDictionary<TComponent, HWND>.Create;
  CaptionOf := TDictionary<TComponent, HWND>.Create;
  Try
    //the module's own references first, in session order, then the rest of
    //each kind, then anything else (scene loader, shader builder ...)
    Put(0, aModule.Instance);
    Put(0, aModule.PhysicalDevice);
    Put(0, aModule.ScreenDevice);
    Put(1, aModule.Linker);
    For L in aModule.SessionLinkers do
      Put(1, L);
    Put(2, aModule.Renderer);
    Put(2, aModule.Scene);
    Put(2, aModule.ToolManager);

    For I := 0 to aModule.ComponentCount - 1 do
    Begin
      C := aModule.Components[I];
      If (C is TvgInstance) or (C is TvgPhysicalDevice) or (C is TvgLogicalDevice) then
        Put(0, C)
      else
      If C is TvgLinker then
        Put(1, C)
      else
      If (C is TvgBaseRenderEngine) or (C is TvgBaseScene) or (C is TvgBaseToolManager) then
        Put(2, C);
    End;

    Put(3, aModule.SceneLoader);
    Put(3, aModule.ShaderBuilder);
    For I := 0 to aModule.ComponentCount - 1 do
      If not (aModule.Components[I] is TControl) then
        Put(3, aModule.Components[I]);

    For I := 0 to 3 do
      For Row := 0 to Cols[I].Count - 1 do
      Begin
        Comps.Add(Cols[I][Row]);
        Targets.Add(Point(cLayoutColumnX[I], cLayoutTop + Row * cLayoutRow));
      End;

    //match every icon (and the caption under it) to its component by where
    //it is now, before any moves, so an icon moved onto another's old spot
    //cannot be taken for it
    Surface := DesignerSurface(aModule);
    If assigned(Surface) and Surface.HandleAllocated then
    Begin
      EnumChildWindows(Surface.Handle, @CollectWindow, LPARAM(AllWnds));
      For Best in AllWnds do
        If IsIconWindow(Best) then
          Icons.Add(Best);

      For C in Comps do
      Begin
        Old  := DesignPos(C);
        Best := 0;
        For I := 0 to Icons.Count - 1 do
        Begin
          P := WindowBounds(Icons[I]).TopLeft;
          If (Abs(P.X - Old.X) <= 2) and (Abs(P.Y - Old.Y) <= 2) then
          Begin
            Best := Icons[I];
            Icons.Delete(I);
            Break;
          End;
        End;

        If Best <> 0 then
        Begin
          IconOf.Add(C, Best);
          Cap := CaptionWindow(Best, AllWnds);
          If Cap <> 0 then
            CaptionOf.Add(C, Cap);
        End;
      End;
    End;

    For I := 0 to Comps.Count - 1 do
    Begin
      C   := Comps[I];
      SetDesignPos(C, Targets[I].X, Targets[I].Y);

      If IconOf.TryGetValue(C, Best) then
      Begin
        //the caption keeps its place under the icon
        P  := WindowBounds(Best).TopLeft;
        DX := Targets[I].X - P.X;
        DY := Targets[I].Y - P.Y;
        MoveWindowBy(Best, DX, DY);
        If CaptionOf.TryGetValue(C, Cap) then
          MoveWindowBy(Cap, DX, DY);
      End else
        Result := False;    //stored, shown once the module is reopened
    End;

    //whatever the designer paints itself (captions, selection) follows
    If assigned(Surface) and Surface.HandleAllocated then
      RedrawWindow(Surface.Handle, nil, 0, RDW_INVALIDATE or RDW_ERASE or RDW_ALLCHILDREN);
  Finally
    CaptionOf.Free;
    IconOf.Free;
    Icons.Free;
    AllWnds.Free;
    Targets.Free;
    Comps.Free;
    For I := 0 to 3 do
      Cols[I].Free;
  End;

  NotifySessionModified(aModule, aDesigner);
end;

procedure BuildSessionInDesigner(aModule: TvgVulkanDataModule; const aDesigner: IDesigner);
begin
  If not assigned(aModule) then exit;

  If assigned(aDesigner) then
    aModule.BuildSession(DesignerFactory(aModule, aDesigner))
  else
    aModule.BuildSession;

  NotifySessionModified(aModule, aDesigner);
end;

procedure AddLinkerInDesigner(aModule: TvgVulkanDataModule; const aDesigner: IDesigner);
  Var L : TvgLinker;
begin
  If not assigned(aModule) then exit;

  If not assigned(aModule.ScreenDevice) then
  Begin
    CustomAssert(False, 'Build the session (or set ScreenDevice) before adding a linker.', aModule);
    exit;
  End;

  If assigned(aDesigner) then
    L := aModule.AddLinker(nil, DesignerFactory(aModule, aDesigner))
  else
    L := aModule.AddLinker(nil);

  If not assigned(L) then exit;

  NotifySessionModified(aModule, aDesigner);

  If assigned(aDesigner) then
    aDesigner.SelectComponent(L);   //ready for its window in the Object Inspector
end;

procedure BuildSceneInDesigner(aModule: TvgVulkanDataModule; const aDesigner: IDesigner);
begin
  If not assigned(aModule) then exit;

  If assigned(aDesigner) then
    aModule.BuildScene(DesignerFactory(aModule, aDesigner))
  else
    aModule.BuildScene;

  NotifySessionModified(aModule, aDesigner);
end;

procedure BuildToolManagerInDesigner(aModule: TvgVulkanDataModule; const aDesigner: IDesigner);
begin
  If not assigned(aModule) then exit;

  If assigned(aDesigner) then
    aModule.BuildToolManager(DesignerFactory(aModule, aDesigner))
  else
    aModule.BuildToolManager;

  NotifySessionModified(aModule, aDesigner);
end;

function PickSceneFile(var aFileName: string): Boolean;
  Var D : TOpenDialog;
begin
  D := TOpenDialog.Create(nil);
  Try
    D.Title   := 'Load Scene';
    D.Filter  := SceneLoaderDialogFilter;
    D.Options := [ofFileMustExist, ofHideReadOnly, ofEnableSizing];

    If aFileName <> '' then
    Begin
      D.InitialDir := ExtractFilePath(aFileName);
      D.FileName   := ExtractFileName(aFileName);
    End;

    Result := D.Execute;
    If Result then
      aFileName := D.FileName;
  Finally
    D.Free;
  End;
end;

{ What a scene load got past (its loader's Warnings), if anything. }
procedure ShowSceneLoadWarnings(const aWarnings: TArray<string>);
begin
  If Length(aWarnings) > 0 then
    MessageDlg('The scene loaded, with warnings:' + sLineBreak + sLineBreak +
               String.Join(sLineBreak, aWarnings), mtWarning, [mbOK], 0);
end;

procedure LoadSceneInDesigner(aModule: TvgVulkanDataModule; const aDesigner: IDesigner; aAsk: Boolean);
  Var FileName  : string;
      WasActive : Boolean;
begin
  If not assigned(aModule) then exit;

  FileName := aModule.SceneFileName;
  If aAsk or (FileName = '') then
  Begin
    If not PickSceneFile(FileName) then exit;

    If FileName <> aModule.SceneFileName then
    Begin
      aModule.SceneFileName := FileName;
      If assigned(aDesigner) then
        aDesigner.Modified;
    End;
  End;

  If not assigned(aModule.Scene) then
    BuildSceneInDesigner(aModule, aDesigner);

  //show it: bring the session up when it can be; otherwise just load the
  //data, which draws once the session is enabled
  WasActive := aModule.SessionActive;
  If not WasActive and aModule.CanEnableSession then
    aModule.EnableSession;     //loads it already with LoadSceneOnEnable

  If WasActive or not aModule.SessionActive or not aModule.LoadSceneOnEnable then
    aModule.LoadScene;

  ShowSceneLoadWarnings(aModule.SceneLoadWarnings);
end;

{ TvgSceneLoaderTypeProperty }

function TvgSceneLoaderTypeProperty.GetAttributes: TPropertyAttributes;
begin
  Result := [paValueList, paSortList, paRevertable, paMultiSelect];
end;

procedure TvgSceneLoaderTypeProperty.GetValues(Proc: TGetStrProc);
  Var Info : TvgSceneLoaderInfo;
begin
  For Info in SceneLoaders do
    Proc(Info.Name);
end;

{ TvgRendererTypeProperty }

function TvgRendererTypeProperty.GetAttributes: TPropertyAttributes;
begin
  Result := [paValueList, paSortList, paRevertable, paMultiSelect];
end;

procedure TvgRendererTypeProperty.GetValues(Proc: TGetStrProc);
  Var Info : TvgRenderEngineInfo;
begin
  For Info in vgRenderEngines do
    Proc(Info.Name);
end;

{ TvgCrossModuleProperty }

{ The root of every module open in the IDE (forms and data modules). }
procedure OpenModuleRoots(aList: TList<TComponent>);
  Var Services : IOTAModuleServices;
      Module   : IOTAModule;
      FormEd   : IOTAFormEditor;
      NTA      : INTAComponent;
      I, J     : Integer;
begin
  If not Supports(BorlandIDEServices, IOTAModuleServices, Services) then exit;

  For I := 0 to Services.ModuleCount - 1 do
  Begin
    Module := Services.Modules[I];
    For J := 0 to Module.GetModuleFileCount - 1 do
      If Supports(Module.GetModuleFileEditor(J), IOTAFormEditor, FormEd) and
         Supports(FormEd.GetRootComponent, INTAComponent, NTA) and
         assigned(NTA.GetComponent) and (aList.IndexOf(NTA.GetComponent) = -1) then
        aList.Add(NTA.GetComponent);
  End;
end;

function TvgCrossModuleProperty.Accepts(aComp: TComponent): Boolean;
begin
  Result := aComp is GetTypeData(GetPropType)^.ClassType;
end;

procedure TvgCrossModuleProperty.GetValues(Proc: TGetStrProc);
  Var Names : TStringList;
      Roots : TList<TComponent>;
      Root  : TComponent;
      I     : Integer;
      N     : string;
begin
  Names := TStringList.Create;
  Roots := TList<TComponent>.Create;
  Try
    Names.Sorted     := True;
    Names.Duplicates := dupIgnore;

    //this module and the ones it already uses, as the Object Inspector lists them
    Designer.GetComponentNames(GetTypeData(GetPropType), Names.Append);
    For I := Names.Count - 1 downto 0 do
      If not Accepts(Designer.GetComponent(Names[I])) then
        Names.Delete(I);

    //every other open module, linked or not
    OpenModuleRoots(Roots);
    For Root in Roots do
    Begin
      If (Root = Designer.Root) or (Root.Name = '') then continue;
      For I := 0 to Root.ComponentCount - 1 do
        If (Root.Components[I].Name <> '') and Accepts(Root.Components[I]) then
        Begin
          N := Root.Name + '.' + Root.Components[I].Name;
          Names.Add(N);
        End;
    End;

    For N in Names do
      Proc(N);
  Finally
    Roots.Free;
    Names.Free;
  End;
end;

procedure TvgCrossModuleProperty.SetValue(const Value: string);
  Var Comp  : TComponent;
      Roots : TList<TComponent>;
      Root  : TComponent;
      P     : Integer;
begin
  If Value = '' then
  Begin
    inherited;
    exit;
  End;

  Comp := Designer.GetComponent(Value);

  //Module.Component on a module this one does not use yet
  If not assigned(Comp) then
  Begin
    P := Pos('.', Value);
    If P > 0 then
    Begin
      Roots := TList<TComponent>.Create;
      Try
        OpenModuleRoots(Roots);
        For Root in Roots do
          If SameText(Root.Name, Copy(Value, 1, P - 1)) then
          Begin
            Comp := Root.FindComponent(Copy(Value, P + 1, MaxInt));
            Break;
          End;
      Finally
        Roots.Free;
      End;
    End;
  End;

  If not assigned(Comp) or not Accepts(Comp) then
    raise EDesignPropertyError.CreateFmt('%s is not a valid value for %s', [Value, GetName]);

  //adds the other module's unit to this one's uses clause
  If not Designer.IsComponentLinkable(Comp) then
    Designer.MakeComponentLinkable(Comp);

  SetOrdValue(IntPtr(Comp));
end;

{ TvgWindowRefProperty }

function TvgWindowRefProperty.Accepts(aComp: TComponent): Boolean;
begin
  Result := Supports(aComp, IvgVulkanWindow);
end;

{ TvgSceneFileNameProperty }

function TvgSceneFileNameProperty.GetAttributes: TPropertyAttributes;
begin
  Result := [paDialog, paRevertable, paMultiSelect];
end;

procedure TvgSceneFileNameProperty.Edit;
  Var FileName : string;
begin
  FileName := GetValue;
  If PickSceneFile(FileName) then
    SetValue(FileName);
end;

{ TvgSceneEditor }

function TvgSceneEditor.GetVerbCount: Integer;
begin
  Result := 2;
end;

function TvgSceneEditor.GetVerb(Index: Integer): string;
begin
  Case Index of
    0 : Result := '&Load Scene File...';
    1 : Result := '&Clear Scene';
  else
    Result := '';
  End;
end;

procedure TvgSceneEditor.ExecuteVerb(Index: Integer);
  Var Scene    : TvgScene;
      M        : TvgVulkanDataModule;
      FileName : string;
      Warnings : TArray<string>;
begin
  Scene := Component as TvgScene;

  //the module's own scene: use its loader settings and remember the file
  M := nil;
  If (Scene.Owner is TvgVulkanDataModule) and (TvgVulkanDataModule(Scene.Owner).Scene = Scene) then
    M := TvgVulkanDataModule(Scene.Owner);

  Try
    Case Index of
      0 : If assigned(M) then
            LoadSceneInDesigner(M, Designer, True)
          else
          Begin
            FileName := '';
            If PickSceneFile(FileName) then
            Begin
              vgLoadSceneFile(Scene, FileName, Warnings);   //loader chosen by extension
              ShowSceneLoadWarnings(Warnings);
            End;
          End;

      1 : Scene.ClearScene;
    End;
  Except
    On E: Exception do
      MessageDlg('Scene:' + sLineBreak + E.Message, mtError, [mbOK], 0);
  End;
end;

{ TvgSessionActiveProperty }

procedure TvgSessionActiveProperty.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer; InNameRect: Boolean; const ItemRect: TRect; var Handled: Boolean);
begin
  Handled := False;
  If (paReadOnly in GetAttributes) or InNameRect then exit;

  If PtInRect(CBRect(ItemRect), Point(X, Y)) then
  Begin
    //True starts the whole session (SetValue), not just this component
    If GetOrdValue = 0 then
      SetValue('True')
    else
      SetValue('False');
    Handled := True;
  End;
end;

procedure TvgSessionActiveProperty.SetValue(const Value: string);
  Var I    : Integer;
      C    : TPersistent;
      Inst : TvgInstance;
begin
  //False (or not a Boolean): the component's own setter, as before
  If GetEnumValue(GetPropType, Value) <> 1 then
  Begin
    inherited;
    exit;
  End;

  For I := 0 to PropCount - 1 do
  Begin
    C    := GetComponent(I);
    Inst := nil;
    If C is TComponent then
      Inst := vgSessionInstance(TComponent(C));

    //a session that presents to windows starts as a whole - devices, every
    //linker and window.  Anything else (an instance on its own, a renderer)
    //just switches itself on.
    //the instance of a session data module: start it as the module does,
    //so LoadSceneOnEnable loads the scene too
    If assigned(Inst) and (Inst.Owner is TvgVulkanDataModule) and
       (TvgVulkanDataModule(Inst.Owner).Instance = Inst) then
      TvgVulkanDataModule(Inst.Owner).EnableSession
    else
    If assigned(Inst) and (Length(vgSessionLinkers(Inst)) > 0) then
      vgEnableSession(Inst)       //raises with the reason: shown by the Object Inspector
    else
      SetOrdProp(C, GetPropInfo, 1);
  End;

  Modified;
end;

{ TvgVulkanDataModuleCustomModule }

function TvgVulkanDataModuleCustomModule.GetVerbCount: Integer;
begin
  Result := inherited GetVerbCount + cVerbCount;
end;

function TvgVulkanDataModuleCustomModule.GetVerb(Index: Integer): string;
  Var M : TvgVulkanDataModule;
begin
  M := Root as TvgVulkanDataModule;

  Case Index - inherited GetVerbCount of
    cVerbEdit   : Result := '&Edit Vulkan Session...';
    cVerbBuild  : Result := '&Build Vulkan Session';
    cVerbAddLinker : Result := 'Add &Linker (another window)';
    cVerbAddScene  : Result := 'Add &Scene';
    cVerbLoadScene : Result := 'Load Scene &File...';
    cVerbAddTools  : Result := 'Add &Tool Manager';
    cVerbArrange   : Result := '&Arrange Session Icons';
    cVerbToggle : If M.SessionActive then
                    Result := '&Disable Vulkan Session'
                  else
                    Result := 'E&nable Vulkan Session';
    cVerbAbout  : Result := '&About Vulkan Session...';
  else
    Result := inherited GetVerb(Index);
  End;
end;

procedure TvgVulkanDataModuleCustomModule.ExecuteVerb(Index: Integer);
  Var M : TvgVulkanDataModule;
      D : IDesigner;
begin
  M := Root as TvgVulkanDataModule;
  D := Designer;

  Case Index - inherited GetVerbCount of
    cVerbEdit :
      Try
        RunVulkanSessionEditor(M, D,
          procedure
          begin
            BuildSessionInDesigner(M, D);
          end,
          procedure
          begin
            AddLinkerInDesigner(M, D);
          end,
          procedure
          begin
            LoadSceneInDesigner(M, D, True);
          end);
      Except
        On E: Exception do
          MessageDlg(E.Message, mtError, [mbOK], 0);
      End;

    cVerbBuild :
      Try
        BuildSessionInDesigner(M, D);
      Except
        On E: Exception do
          MessageDlg('Unable to build the session:' + sLineBreak + E.Message, mtError, [mbOK], 0);
      End;

    cVerbAddLinker :
      Try
        AddLinkerInDesigner(M, D);
      Except
        On E: Exception do
          MessageDlg(E.Message, mtError, [mbOK], 0);
      End;

    cVerbAddScene :
      Try
        BuildSceneInDesigner(M, D);
      Except
        On E: Exception do
          MessageDlg(E.Message, mtError, [mbOK], 0);
      End;

    cVerbLoadScene :
      Try
        LoadSceneInDesigner(M, D, True);
      Except
        On E: Exception do
          MessageDlg('Load scene:' + sLineBreak + E.Message, mtError, [mbOK], 0);
      End;

    cVerbAddTools :
      Try
        BuildToolManagerInDesigner(M, D);
      Except
        On E: Exception do
          MessageDlg(E.Message, mtError, [mbOK], 0);
      End;

    cVerbArrange :
      Try
        If not ArrangeSessionInDesigner(M, D) then
          MessageDlg('The session icons have new positions, but some could not be moved on screen.' + sLineBreak +
                     'Save, then close and reopen the data module to see them.', mtInformation, [mbOK], 0);
      Except
        On E: Exception do
          MessageDlg('Arrange session icons:' + sLineBreak + E.Message, mtError, [mbOK], 0);
      End;

    cVerbToggle :
      Try
        If M.SessionActive then
          M.DisableSession
        else
          M.EnableSession;
      Except
        On E: Exception do
          MessageDlg('Vulkan session:' + sLineBreak + E.Message, mtError, [mbOK], 0);
      End;

    cVerbAbout :
      MessageDlg(vgDMAbout, mtInformation, [mbOK], 0);
  else
    inherited ExecuteVerb(Index);
  End;
end;

{ TvgVulkanDataModuleWizard }

procedure TvgVulkanDataModuleWizard.Execute;
begin
  (BorlandIDEServices as IOTAModuleServices).CreateModule(TvgVulkanDataModuleCreator.Create);
end;

function TvgVulkanDataModuleWizard.GetAuthor: string;
begin
  Result := 'Datavis';
end;

function TvgVulkanDataModuleWizard.GetComment: string;
begin
  Result := vgDMWizardComment;
end;

function TvgVulkanDataModuleWizard.GetDesigner: string;
begin
  Result := dVCL;
end;

function TvgVulkanDataModuleWizard.GetGalleryCategory: IOTAGalleryCategory;
begin
  Result := (BorlandIDEServices as IOTAGalleryCategoryManager).FindCategory(sCategoryDelphiNewFiles);
end;

function TvgVulkanDataModuleWizard.GetGlyph: TvgWizardGlyph;
begin
  Result := 0;   //default icon
end;

function TvgVulkanDataModuleWizard.GetIDString: string;
begin
  Result := 'Datavis.VulkanSessionDataModuleWizard';
end;

function TvgVulkanDataModuleWizard.GetName: string;
begin
  Result := vgDMWizardName;
end;

function TvgVulkanDataModuleWizard.GetPage: string;
begin
  Result := 'Vulkan Graphics';
end;

function TvgVulkanDataModuleWizard.GetPersonality: string;
begin
  Result := sDelphiPersonality;
end;

function TvgVulkanDataModuleWizard.GetState: TWizardState;
begin
  Result := [wsEnabled];
end;

{ TvgVulkanDataModuleCreator }

function TvgVulkanDataModuleCreator.GetAncestorName: string;
begin
  //class name without the leading T
  Result := Copy(TvgVulkanDataModule.ClassName, 2, MaxInt);
end;

function TvgVulkanDataModuleCreator.GetCreatorType: string;
begin
  Result := sForm;
end;

function TvgVulkanDataModuleCreator.GetExisting: Boolean;
begin
  Result := False;
end;

function TvgVulkanDataModuleCreator.GetFileSystem: string;
begin
  Result := '';
end;

function TvgVulkanDataModuleCreator.GetFormName: string;
begin
  Result := '';   //let the IDE pick a unique name
end;

function TvgVulkanDataModuleCreator.GetImplFileName: string;
begin
  Result := '';
end;

function TvgVulkanDataModuleCreator.GetIntfFileName: string;
begin
  Result := '';
end;

function TvgVulkanDataModuleCreator.GetMainForm: Boolean;
begin
  Result := False;
end;

function TvgVulkanDataModuleCreator.GetOwner: IOTAModule;
  Var Services : IOTAModuleServices;
      Group    : IOTAProjectGroup;
begin
  Result := nil;
  If not Supports(BorlandIDEServices, IOTAModuleServices, Services) then exit;

  Group := Services.MainProjectGroup;
  If assigned(Group) then
    Result := Group.ActiveProject;
end;

function TvgVulkanDataModuleCreator.GetShowForm: Boolean;
begin
  Result := True;
end;

function TvgVulkanDataModuleCreator.GetShowSource: Boolean;
begin
  Result := True;
end;

function TvgVulkanDataModuleCreator.GetUnnamed: Boolean;
begin
  Result := True;
end;

procedure TvgVulkanDataModuleCreator.FormCreated(const FormEditor: IOTAFormEditor);
begin
  //components are added with "Build Vulkan Session" on the module's menu
end;

function TvgVulkanDataModuleCreator.NewFormFile(const FormIdent, AncestorIdent: string): IOTAFile;
begin
  Result := nil;   //the IDE streams the ancestor
end;

function TvgVulkanDataModuleCreator.NewImplSource(const ModuleIdent, FormIdent, AncestorIdent: string): IOTAFile;
begin
  Result := TvgSourceFile.Create(Format(cUnitSource, [ModuleIdent, FormIdent, AncestorIdent]));
end;

function TvgVulkanDataModuleCreator.NewIntfSource(const ModuleIdent, FormIdent, AncestorIdent: string): IOTAFile;
begin
  Result := nil;
end;

{ TvgSourceFile }

constructor TvgSourceFile.Create(const aSource: string);
begin
  inherited Create;
  fSource := aSource;
end;

function TvgSourceFile.GetAge: TDateTime;
begin
  Result := -1;
end;

function TvgSourceFile.GetSource: string;
begin
  Result := fSource;
end;

initialization

finalization
  If assigned(DropNotification) then
  Begin
    UnregisterDesignNotification(DropNotification);
    DropNotification := nil;
  End;

end.
