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
    * TvgScreenRenderDevice goes on the palette so it can sit on the module.

  Scenes: Add Scene creates a TvgScene connected to the primary linker and
  renderer; Load Scene... picks a file and loads it with a registered scene
  loader (by SceneLoaderType, or by extension).  SceneLoaderType drops down
  the registered loaders; SceneFileName has a file-open button.  Any
  TvgScene also gets "Load Scene File..." / "Clear Scene" on its menu.
  Loaders register themselves in Vulkan_SceneLoaders (the glTF loader is in
  the PRO package).

  Extra windows: drop another TvgLinker (or use Add Linker), set its
  ScreenDevice, and set the second TvgWindowVCL's VulkanLink to it - all
  from the Object Inspector's drop downs, across forms.  The editor and the
  Active test cover every linker connected under the instance.

  Design time only: in the VCL design package (VulkanPkg_VCLDxxx, e.g.
  VulkanPkg_VCLD290 for Delphi 12). }

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

  { Active on a session component: True tests the whole session. }
  TvgSessionActiveProperty = class(TBoolProperty)
  public
    procedure SetValue(const Value: string); override;
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

  RegisterComponents('Vulkan Graphics', [TvgScreenRenderDevice, TvgScene, TvgToolManager]);

  RegisterComponentEditor(TvgScene, TvgSceneEditor);

  RegisterPropertyEditor(TypeInfo(string), TvgVulkanDataModule, 'SceneLoaderType', TvgSceneLoaderTypeProperty);
  RegisterPropertyEditor(TypeInfo(string), TvgVulkanDataModule, 'SceneFileName',   TvgSceneFileNameProperty);
  RegisterPropertyEditor(TypeInfo(string), TvgVulkanDataModule, 'RendererType',    TvgRendererTypeProperty);

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
  cLayoutLeft   = 32;
  cLayoutTop    = 32;
  cLayoutColumn = 200;   //column pitch
  cLayoutRow    = 80;    //row pitch

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
    If (Abs(X - aLeft) < cLayoutColumn div 2) and (Abs(Y - aTop) < cLayoutRow div 2) then
      Exit(True);
  End;
end;

function DesignerFactory(aModule: TvgVulkanDataModule; const aDesigner: IDesigner): TvgSessionComponentFactory;
  Var D : IDesigner;
begin
  D := aDesigner;
  Result :=
    function(aClass: TComponentClass; aIndex: Integer): TComponent
      Var Col, Row : Integer;
          X, Y     : Integer;
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

      X := cLayoutLeft + Col * cLayoutColumn;
      Y := cLayoutTop  + Row * cLayoutRow;

      //never on top of a part that is already there: next free row down
      While CellTaken(aModule, X, Y) do
        Inc(Y, cLayoutRow);

      Result := D.CreateComponent(aClass, aModule, X, Y, 0, 0);
    end;
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

function CollectContainer(aWnd: HWND; aList: LPARAM): BOOL; stdcall;
  Var Buf : array[0..63] of Char;
begin
  If (GetClassName(aWnd, Buf, Length(Buf)) > 0) and (string(Buf) = 'TContainer') then
    TList<HWND>(aList).Add(aWnd);
  Result := True;
end;

{ An icon window's top left, in its parent's client coordinates. }
function WindowPos(aWnd: HWND): TPoint;
  Var R : TRect;
begin
  GetWindowRect(aWnd, R);
  Result := R.TopLeft;
  ScreenToClient(GetParent(aWnd), Result);
end;

function ArrangeSessionInDesigner(aModule: TvgVulkanDataModule; const aDesigner: IDesigner): Boolean;
  Var Cols      : array[0..3] of TList<TComponent>;
      Comps     : TList<TComponent>;
      Targets   : TList<TPoint>;
      Icons     : TList<HWND>;
      IconOf    : TDictionary<TComponent, HWND>;
      Surface   : TCustomForm;
      C         : TComponent;
      L         : TvgLinker;
      Old, P    : TPoint;
      I, Row    : Integer;
      Best      : HWND;
      Ctl       : TWinControl;

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
  Icons   := TList<HWND>.Create;
  IconOf  := TDictionary<TComponent, HWND>.Create;
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
        Targets.Add(Point(cLayoutLeft + I * cLayoutColumn, cLayoutTop + Row * cLayoutRow));
      End;

    //match every icon to its component by where it is now, before any moves,
    //so an icon moved onto another's old spot cannot be taken for it
    Surface := DesignerSurface(aModule);
    If assigned(Surface) and Surface.HandleAllocated then
    Begin
      EnumChildWindows(Surface.Handle, @CollectContainer, LPARAM(Icons));

      For C in Comps do
      Begin
        Old  := DesignPos(C);
        Best := 0;
        For I := 0 to Icons.Count - 1 do
        Begin
          P := WindowPos(Icons[I]);
          If (Abs(P.X - Old.X) <= 2) and (Abs(P.Y - Old.Y) <= 2) then
          Begin
            Best := Icons[I];
            Icons.Delete(I);
            Break;
          End;
        End;
        If Best <> 0 then
          IconOf.Add(C, Best);
      End;
    End;

    For I := 0 to Comps.Count - 1 do
    Begin
      C := Comps[I];
      SetDesignPos(C, Targets[I].X, Targets[I].Y);

      If IconOf.TryGetValue(C, Best) then
      Begin
        Ctl := FindControl(Best);
        If assigned(Ctl) then
          Ctl.SetBounds(Targets[I].X, Targets[I].Y, Ctl.Width, Ctl.Height)
        else
          SetWindowPos(Best, 0, Targets[I].X, Targets[I].Y, 0, 0,
                       SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE);
      End else
        Result := False;    //stored, shown once the module is reopened
    End;

    If assigned(Surface) then
      Surface.Invalidate;
  Finally
    IconOf.Free;
    Icons.Free;
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
              vgLoadSceneFile(Scene, FileName);   //loader chosen by extension
          End;

      1 : Scene.ClearScene;
    End;
  Except
    On E: Exception do
      MessageDlg('Scene:' + sLineBreak + E.Message, mtError, [mbOK], 0);
  End;
end;

{ TvgSessionActiveProperty }

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
