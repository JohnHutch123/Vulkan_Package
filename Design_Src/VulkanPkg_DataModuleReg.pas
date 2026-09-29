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
    * Active property editor on every session component (instance, devices,
      linkers, TvgWindowVCL): setting Active to True at design time starts the
      whole session the component is connected to - every device, linker and
      window under its instance - the way setting a dataset's Active opens its
      connection.  If it can't start, the reason is shown and nothing is left
      half enabled.  Setting it False shuts that component down as before.
    * File > New > Other > Delphi Files > "Vulkan Session Data Module" creates
      a new unit whose data module descends from TvgVulkanDataModule.
    * TvgScreenRenderDevice goes on the palette so it can sit on the module.

  Extra windows: drop another TvgLinker (or use Add Linker), set its
  ScreenDevice, and set the second TvgWindowVCL's VulkanLink to it - all
  from the Object Inspector's drop downs, across forms.  The editor and the
  Active test cover every linker connected under the instance.

  Design time only: in the VCL design package (VulkanPkg_VCLD280). }

unit VulkanPkg_DataModuleReg;

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Dialogs,
  Vcl.Forms,
  DesignIntf,
  DesignEditors,
  DMForm,
  ToolsAPI,
  Vulkan_Components,
  Vulkan_WindowVCL,
  Vulkan_DataModule,
  VulkanDataModuleEditFM;

type
  { Active on a session component: True tests the whole session. }
  TvgSessionActiveProperty = class(TBoolProperty)
  public
    procedure SetValue(const Value: string); override;
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
    function  GetGlyph: Cardinal;
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
  cVerbToggle    = 3;
  cVerbAbout     = 4;
  cVerbCount     = 5;

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

procedure Register;
begin
  RegisterComponents('Vulkan Graphics', [TvgScreenRenderDevice]);

  RegisterCustomModule(TvgVulkanDataModule, TvgVulkanDataModuleCustomModule);

  RegisterPropertyEditor(TypeInfo(Boolean), TvgBaseComponent, 'Active', TvgSessionActiveProperty);
  RegisterPropertyEditor(TypeInfo(Boolean), TvgWindowVCL,     'Active', TvgSessionActiveProperty);

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

{ Instance, physical device and screen device left to right; the linkers
  in a column after them. }
function DesignerFactory(aModule: TvgVulkanDataModule; const aDesigner: IDesigner): TvgSessionComponentFactory;
  Var D : IDesigner;
begin
  D := aDesigner;
  Result :=
    function(aClass: TComponentClass; aIndex: Integer): TComponent
    begin
      If aIndex < 3 then
        Result := D.CreateComponent(aClass, aModule, 24 + aIndex * 112, 24, 0, 0)
      else
        Result := D.CreateComponent(aClass, aModule, 24 + 3 * 112, 24 + (aIndex - 3) * 72, 0, 0);
    end;
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
    raise EvgVulkanSessionError.Create('Build the session (or set ScreenDevice) before adding a linker.');

  If assigned(aDesigner) then
    L := aModule.AddLinker(nil, DesignerFactory(aModule, aDesigner))
  else
    L := aModule.AddLinker(nil);

  NotifySessionModified(aModule, aDesigner);

  If assigned(aDesigner) then
    aDesigner.SelectComponent(L);   //ready for its window in the Object Inspector
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
      RunVulkanSessionEditor(M, D,
        procedure
        begin
          BuildSessionInDesigner(M, D);
        end,
        procedure
        begin
          AddLinkerInDesigner(M, D);
        end);

    cVerbBuild :
      BuildSessionInDesigner(M, D);

    cVerbAddLinker :
      Try
        AddLinkerInDesigner(M, D);
      Except
        On E: Exception do
          MessageDlg(E.Message, mtError, [mbOK], 0);
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

function TvgVulkanDataModuleWizard.GetGlyph: Cardinal;
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

end.
