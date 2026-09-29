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

{ Design-time editor for a TvgVulkanDataModule session.

  The tree lists the module and every session component (Instance,
  PhysicalDevice, ScreenDevice, Linker, Window) with their published
  sub-objects and collection items.  The list shows the published properties
  of the selected object; the panel under it edits the selected property:

      numbers / strings         edit box        (Enter or Apply)
      enumerations / Boolean    drop down list  (applies on change)
      sets                      check list      (applies on click)
      component references      drop down of the compatible components in
                                every open module, as the Object Inspector

  Events are left to the Object Inspector.  Active is not shown: the session
  is switched on and off as a whole with Enable / Disable.  While the session
  is running the properties are read only - most session properties can only
  change while Vulkan is shut down. }

unit VulkanDataModuleEditFM;

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Variants,
  System.Classes,
  System.TypInfo,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.CheckLst,
  DesignIntf,
  Vulkan_Components,
  Vulkan_DataModule;

type
  TvgSessionEditorFM = class(TForm)
    pnlTop: TPanel;
    lblStatus: TLabel;
    btnBuild: TButton;
    btnEnable: TButton;
    btnDisable: TButton;
    btnRefresh: TButton;
    pnlBottom: TPanel;
    btnClose: TButton;
    tvObjects: TTreeView;
    Splitter1: TSplitter;
    pnlRight: TPanel;
    lvProps: TListView;
    pnlEdit: TPanel;
    lblPropName: TLabel;
    lblHint: TLabel;
    edValue: TEdit;
    cbValue: TComboBox;
    clbValue: TCheckListBox;
    btnApply: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure tvObjectsChange(Sender: TObject; Node: TTreeNode);
    procedure lvPropsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure btnApplyClick(Sender: TObject);
    procedure cbValueChange(Sender: TObject);
    procedure clbValueClickCheck(Sender: TObject);
    procedure edValueKeyPress(Sender: TObject; var Key: Char);
    procedure btnBuildClick(Sender: TObject);
    procedure btnEnableClick(Sender: TObject);
    procedure btnDisableClick(Sender: TObject);
    procedure btnRefreshClick(Sender: TObject);
  private
    fModule      : TvgVulkanDataModule;
    fDesigner    : IDesigner;
    fOnBuild     : TProc;

    fObject      : TPersistent;   //object whose properties are listed
    fProp        : PPropInfo;     //property being edited
    fRefNames    : TStringList;   //component names offered for a reference
    fUpdating    : Boolean;

    procedure AddRefName(const S: string);

    procedure BuildTree(aSelect: TPersistent = nil);
    procedure AddObjectNode(aParent: TTreeNode; const aCaption: string; aObj: TPersistent; aDepth: Integer);
    function  FindNode(aObj: TPersistent): TTreeNode;

    procedure ShowProperties(aObj: TPersistent);
    procedure ShowEditor;
    procedure HideEditors;
    procedure ApplyValue;
    procedure UpdateStatus;
    procedure NotifyModified(aObj: TPersistent);

    function  ObjectCaption(aObj: TPersistent): string;
    function  PropValueText(aObj: TPersistent; aProp: PPropInfo): string;
    function  IsChildObject(aObj: TPersistent; aProp: PPropInfo; out aChild: TPersistent): Boolean;
    function  IsEditableProp(aObj: TPersistent; aProp: PPropInfo): Boolean;
    function  ComponentName(aComp: TComponent): string;
  public
    property Module   : TvgVulkanDataModule read fModule;
    property Designer : IDesigner read fDesigner;
  end;

{ aBuild creates the missing session components; the designer passes one that
  creates them through IDesigner so they are named and streamed. }
procedure RunVulkanSessionEditor(aModule: TvgVulkanDataModule; const aDesigner: IDesigner; const aBuild: TProc);

implementation

{$R *.dfm}

const
  cMaxDepth = 6;   //sub-object nesting shown in the tree

procedure RunVulkanSessionEditor(aModule: TvgVulkanDataModule; const aDesigner: IDesigner; const aBuild: TProc);
  Var F : TvgSessionEditorFM;
begin
  If not assigned(aModule) then exit;

  F := TvgSessionEditorFM.Create(Application);
  Try
    F.fModule   := aModule;
    F.fDesigner := aDesigner;
    F.fOnBuild  := aBuild;
    F.Caption   := Format('Vulkan Session Editor - %s', [aModule.Name]);
    F.ShowModal;
  Finally
    F.Free;
  End;
end;

function vgPropName(aProp: PPropInfo): string;
begin
  Result := string(aProp^.Name);
end;

function vgPropType(aProp: PPropInfo): PTypeInfo;
begin
  Result := aProp^.PropType^;
end;

{ TvgSessionEditorFM }

procedure TvgSessionEditorFM.FormCreate(Sender: TObject);
begin
  fRefNames := TStringList.Create;
  fRefNames.Sorted     := True;
  fRefNames.Duplicates := dupIgnore;
end;

procedure TvgSessionEditorFM.FormDestroy(Sender: TObject);
begin
  FreeAndNil(fRefNames);
end;

procedure TvgSessionEditorFM.FormShow(Sender: TObject);
begin
  BuildTree(fModule);
  UpdateStatus;
end;

function TvgSessionEditorFM.ComponentName(aComp: TComponent): string;
begin
  If not assigned(aComp) then
    Exit('');

  //Designer names components on other modules as 'Form1.Window1'
  If assigned(fDesigner) then
    Result := fDesigner.GetComponentName(aComp)
  else
    Result := aComp.Name;

  If Result = '' then
    Result := aComp.Name;
end;

function TvgSessionEditorFM.ObjectCaption(aObj: TPersistent): string;
begin
  If aObj is TComponent then
    Result := Format('%s: %s', [TComponent(aObj).Name, aObj.ClassName])
  else
  If aObj is TCollectionItem then
    Result := Format('[%d] %s', [TCollectionItem(aObj).Index, TCollectionItem(aObj).DisplayName])
  else
    Result := aObj.ClassName;
end;

{ A sub-object shown as its own node rather than edited as a value: owned
  persistents (TvgFeatures, queue families ...), collections and
  sub-components (the linker's surface and swap chain). }
function TvgSessionEditorFM.IsChildObject(aObj: TPersistent; aProp: PPropInfo; out aChild: TPersistent): Boolean;
  Var O : TObject;
begin
  Result := False;
  aChild := nil;

  If vgPropType(aProp)^.Kind <> tkClass then exit;
  If not assigned(aProp^.GetProc) then exit;

  O := GetObjectProp(aObj, aProp);
  If not (O is TPersistent) then exit;
  If O is TStrings then exit;      //edited as text

  If O is TComponent then
    Result := csSubComponent in TComponent(O).ComponentStyle
  else
    Result := True;

  If Result then
    aChild := TPersistent(O);
end;

function TvgSessionEditorFM.IsEditableProp(aObj: TPersistent; aProp: PPropInfo): Boolean;
  Var Child : TPersistent;
begin
  Result := assigned(aProp^.SetProc) and assigned(aProp^.GetProc);
  If not Result then exit;

  //renaming goes through the designer's checks: leave it to the Object Inspector
  If (aObj is TComponent) and SameText(vgPropName(aProp), 'Name') then
    Exit(False);

  Case vgPropType(aProp)^.Kind of
    tkInteger, tkChar, tkWChar, tkInt64, tkFloat,
    tkString, tkLString, tkUString, tkWString,
    tkEnumeration, tkSet : Result := True;

    tkClass : Result := not IsChildObject(aObj, aProp, Child);
  else
    Result := False;
  End;
end;

function TvgSessionEditorFM.PropValueText(aObj: TPersistent; aProp: PPropInfo): string;
  Var TD    : PTypeData;
      O     : TObject;
      Child : TPersistent;
begin
  Result := '';
  If not assigned(aProp^.GetProc) then
    Exit('(write only)');

  Try
    TD := GetTypeData(vgPropType(aProp));

    Case vgPropType(aProp)^.Kind of
      tkInteger :
        If TD^.OrdType = otULong then
          Result := UIntToStr(Cardinal(GetOrdProp(aObj, aProp)))
        else
          Result := IntToStr(GetOrdProp(aObj, aProp));

      tkChar, tkWChar :
        Result := Char(GetOrdProp(aObj, aProp));

      tkInt64 :
        Result := IntToStr(GetInt64Prop(aObj, aProp));

      tkFloat :
        Result := FloatToStr(GetFloatProp(aObj, aProp));

      tkString, tkLString, tkUString, tkWString :
        Result := GetStrProp(aObj, aProp);

      tkEnumeration :
        Result := GetEnumName(vgPropType(aProp), GetOrdProp(aObj, aProp));

      tkSet :
        Result := GetSetProp(aObj, aProp, True);

      tkClass :
        Begin
          O := GetObjectProp(aObj, aProp);
          If not assigned(O) then
            Result := '(none)'
          else
          If IsChildObject(aObj, aProp, Child) then
          Begin
            If Child is TCollection then
              Result := Format('(%d items)', [TCollection(Child).Count])
            else
              Result := '(' + Child.ClassName + ')';
          End
          else
          If O is TStrings then
            Result := TStrings(O).CommaText
          else
          If O is TComponent then
            Result := ComponentName(TComponent(O))
          else
            Result := '(' + O.ClassName + ')';
        End;

      tkInterface : Result := '(interface)';
    else
      Result := '(' + GetEnumName(TypeInfo(TTypeKind), Ord(vgPropType(aProp)^.Kind)) + ')';
    End;
  Except
    On E: Exception do
      Result := '(' + E.Message + ')';
  End;
end;

procedure TvgSessionEditorFM.AddObjectNode(aParent: TTreeNode; const aCaption: string; aObj: TPersistent; aDepth: Integer);
  Var Node      : TTreeNode;
      PropList  : PPropList;
      Count, I  : Integer;
      Child     : TPersistent;
begin
  If not assigned(aObj) then exit;

  Node := tvObjects.Items.AddChildObject(aParent, aCaption, aObj);

  If aDepth >= cMaxDepth then exit;

  If aObj is TCollection then
  Begin
    For I := 0 to TCollection(aObj).Count - 1 do
      AddObjectNode(Node, ObjectCaption(TCollection(aObj).Items[I]), TCollection(aObj).Items[I], aDepth + 1);
  End;

  Count := GetPropList(aObj, PropList);
  If Count = 0 then exit;
  Try
    For I := 0 to Count - 1 do
      If IsChildObject(aObj, PropList^[I], Child) then
        AddObjectNode(Node, vgPropName(PropList^[I]) + ': ' + Child.ClassName, Child, aDepth + 1);
  Finally
    FreeMem(PropList);
  End;
end;

function TvgSessionEditorFM.FindNode(aObj: TPersistent): TTreeNode;
  Var I : Integer;
begin
  Result := nil;
  If not assigned(aObj) then exit;

  For I := 0 to tvObjects.Items.Count - 1 do
    If tvObjects.Items[I].Data = Pointer(aObj) then
      Exit(tvObjects.Items[I]);
end;

procedure TvgSessionEditorFM.BuildTree(aSelect: TPersistent = nil);
  Var Node : TTreeNode;
begin
  tvObjects.Items.BeginUpdate;
  Try
    tvObjects.Items.Clear;
    fObject := nil;
    fProp   := nil;

    AddObjectNode(nil, 'Session: ' + fModule.Name, fModule, cMaxDepth);  //references only, no children

    If assigned(fModule.Instance) then
      AddObjectNode(nil, ObjectCaption(fModule.Instance), fModule.Instance, 0);

    If assigned(fModule.PhysicalDevice) then
      AddObjectNode(nil, ObjectCaption(fModule.PhysicalDevice), fModule.PhysicalDevice, 0);

    If assigned(fModule.ScreenDevice) then
      AddObjectNode(nil, ObjectCaption(fModule.ScreenDevice), fModule.ScreenDevice, 0);

    If assigned(fModule.Linker) then
      AddObjectNode(nil, ObjectCaption(fModule.Linker), fModule.Linker, 0);

    If assigned(fModule.Window) then
      AddObjectNode(nil, ComponentName(fModule.Window) + ': ' + fModule.Window.ClassName, fModule.Window, 0);
  Finally
    tvObjects.Items.EndUpdate;
  End;

  Node := FindNode(aSelect);
  If not assigned(Node) and (tvObjects.Items.Count > 0) then
    Node := tvObjects.Items[0];

  If assigned(Node) then
  Begin
    tvObjects.Selected := Node;
    Node.MakeVisible;
  End;

  ShowProperties(fObject);
end;

procedure TvgSessionEditorFM.tvObjectsChange(Sender: TObject; Node: TTreeNode);
begin
  If fUpdating then exit;

  If assigned(Node) then
    fObject := TPersistent(Node.Data)
  else
    fObject := nil;

  ShowProperties(fObject);
end;

procedure TvgSessionEditorFM.ShowProperties(aObj: TPersistent);
  Var PropList : PPropList;
      Count, I : Integer;
      Item     : TListItem;
      OldName  : string;
      Sel      : TListItem;
begin
  If assigned(fProp) then
    OldName := vgPropName(fProp)
  else
    OldName := '';

  fProp := nil;
  Sel   := nil;

  lvProps.Items.BeginUpdate;
  Try
    lvProps.Items.Clear;
    If not assigned(aObj) then exit;

    Count := GetPropList(aObj, PropList);
    If Count = 0 then exit;
    Try
      For I := 0 to Count - 1 do
      Begin
        //events belong to the Object Inspector; Active is the session's job
        If vgPropType(PropList^[I])^.Kind = tkMethod then continue;
        If SameText(vgPropName(PropList^[I]), 'Active') then continue;
        If SameText(vgPropName(PropList^[I]), 'SessionActive') then continue;

        Item         := lvProps.Items.Add;
        Item.Caption := vgPropName(PropList^[I]);
        Item.SubItems.Add(PropValueText(aObj, PropList^[I]));
        Item.SubItems.Add(string(vgPropType(PropList^[I])^.Name));
        Item.Data    := PropList^[I];

        If SameText(Item.Caption, OldName) then
          Sel := Item;
      End;
    Finally
      FreeMem(PropList);
    End;
  Finally
    lvProps.Items.EndUpdate;
  End;

  If assigned(Sel) then
  Begin
    lvProps.Selected := Sel;
    Sel.MakeVisible(False);
  End;

  ShowEditor;
end;

procedure TvgSessionEditorFM.lvPropsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  If fUpdating then exit;

  If Selected and assigned(Item) then
    fProp := PPropInfo(Item.Data)
  else
    fProp := nil;

  ShowEditor;
end;

procedure TvgSessionEditorFM.AddRefName(const S: string);
begin
  fRefNames.Add(S);
end;

procedure TvgSessionEditorFM.HideEditors;
begin
  edValue.Visible  := False;
  cbValue.Visible  := False;
  clbValue.Visible := False;
  btnApply.Visible := False;
end;

procedure TvgSessionEditorFM.ShowEditor;
  Var TD, CTD : PTypeData;
      CompType: PTypeInfo;
      I       : Integer;
      Current : string;
      Running : Boolean;
      Comp    : TComponent;
begin
  fUpdating := True;
  Try
    HideEditors;
    cbValue.Items.Clear;
    clbValue.Items.Clear;

    If not assigned(fObject) or not assigned(fProp) then
    Begin
      lblPropName.Caption := '';
      lblHint.Caption     := 'Select a property to edit it.';
      exit;
    End;

    lblPropName.Caption := Format('%s  (%s)', [vgPropName(fProp), string(vgPropType(fProp)^.Name)]);

    If not IsEditableProp(fObject, fProp) then
    Begin
      lblHint.Caption := 'Read only here - sub-objects are expanded in the tree; rename components in the Object Inspector.';
      exit;
    End;

    Running := fModule.SessionActive;
    If Running then
      lblHint.Caption := 'The session is running.  Disable it to edit properties.'
    else
      lblHint.Caption := '';

    Current := PropValueText(fObject, fProp);
    TD      := GetTypeData(vgPropType(fProp));

    Case vgPropType(fProp)^.Kind of
      tkEnumeration :
        Begin
          For I := TD^.MinValue to TD^.MaxValue do
            cbValue.Items.Add(GetEnumName(vgPropType(fProp), I));
          cbValue.ItemIndex := cbValue.Items.IndexOf(Current);
          cbValue.Visible   := True;
          cbValue.Enabled   := not Running;
        End;

      tkSet :
        Begin
          CompType := TD^.CompType^;
          CTD      := GetTypeData(CompType);
          For I := CTD^.MinValue to CTD^.MaxValue do
            clbValue.Checked[clbValue.Items.Add(GetEnumName(CompType, I))] :=
              Pos(',' + GetEnumName(CompType, I) + ',',
                  ',' + StringReplace(Copy(Current, 2, Length(Current) - 2), ' ', '', [rfReplaceAll]) + ',') > 0;
          clbValue.Visible := True;
          clbValue.Enabled := not Running;
        End;

      tkClass :
        Begin
          If GetTypeData(vgPropType(fProp))^.ClassType.InheritsFrom(TStrings) then
          Begin
            edValue.Text     := Current;
            edValue.Visible  := True;
            edValue.Enabled  := not Running;
            btnApply.Visible := True;
            btnApply.Enabled := not Running;
            lblHint.Caption  := lblHint.Caption + ' Comma separated lines.';
            exit;
          End;

          //component reference: offer what the Object Inspector would
          fRefNames.Clear;
          If assigned(fDesigner) then
            fDesigner.GetComponentNames(GetTypeData(vgPropType(fProp)), AddRefName)
          else
            For I := 0 to fModule.ComponentCount - 1 do
            Begin
              Comp := fModule.Components[I];
              If Comp.InheritsFrom(GetTypeData(vgPropType(fProp))^.ClassType) then
                fRefNames.Add(Comp.Name);
            End;

          cbValue.Items.Add('(none)');
          cbValue.Items.AddStrings(fRefNames);
          cbValue.ItemIndex := cbValue.Items.IndexOf(Current);
          cbValue.Visible   := True;
          cbValue.Enabled   := not Running;
        End;
    else
      Begin
        edValue.Text     := Current;
        edValue.Visible  := True;
        edValue.Enabled  := not Running;
        btnApply.Visible := True;
        btnApply.Enabled := not Running;
      End;
    End;
  Finally
    fUpdating := False;
  End;
end;

procedure TvgSessionEditorFM.ApplyValue;
  Var TD       : PTypeData;
      S        : string;
      I        : Integer;
      V        : Int64;
      Comp     : TComponent;
      OldObj   : TObject;
      IsRef    : Boolean;
      Selected : TPersistent;
begin
  If fUpdating then exit;
  If not assigned(fObject) or not assigned(fProp) then exit;
  If not IsEditableProp(fObject, fProp) then exit;

  If fModule.SessionActive then
  Begin
    MessageDlg('Disable the session before editing its properties.', mtWarning, [mbOK], 0);
    ShowEditor;
    exit;
  End;

  TD    := GetTypeData(vgPropType(fProp));
  IsRef := False;

  Try
    Case vgPropType(fProp)^.Kind of
      tkInteger :
        Begin
          V := StrToInt64(Trim(edValue.Text));
          If TD^.OrdType = otULong then
          Begin
            If (V < 0) or (V > High(Cardinal)) then
              raise EConvertError.CreateFmt('%d is out of range', [V]);
            SetOrdProp(fObject, fProp, NativeInt(Cardinal(V)));
          End else
          Begin
            If (V < TD^.MinValue) or (V > TD^.MaxValue) then
              raise EConvertError.CreateFmt('%d is out of range (%d..%d)', [V, TD^.MinValue, TD^.MaxValue]);
            SetOrdProp(fObject, fProp, NativeInt(V));
          End;
        End;

      tkChar, tkWChar :
        Begin
          S := edValue.Text;
          If S = '' then
            raise EConvertError.Create('A character is required');
          SetOrdProp(fObject, fProp, Ord(S[1]));
        End;

      tkInt64 :
        SetInt64Prop(fObject, fProp, StrToInt64(Trim(edValue.Text)));

      tkFloat :
        SetFloatProp(fObject, fProp, StrToFloat(Trim(edValue.Text)));

      tkString, tkLString, tkUString, tkWString :
        SetStrProp(fObject, fProp, edValue.Text);

      tkEnumeration :
        Begin
          If cbValue.ItemIndex < 0 then exit;
          SetOrdProp(fObject, fProp, GetEnumValue(vgPropType(fProp), cbValue.Items[cbValue.ItemIndex]));
        End;

      tkSet :
        Begin
          S := '';
          For I := 0 to clbValue.Items.Count - 1 do
            If clbValue.Checked[I] then
            Begin
              If S <> '' then S := S + ',';
              S := S + clbValue.Items[I];
            End;
          SetSetProp(fObject, fProp, '[' + S + ']');
        End;

      tkClass :
        If TD^.ClassType.InheritsFrom(TStrings) then
          TStrings(GetObjectProp(fObject, fProp)).CommaText := edValue.Text
        else
        Begin
          If cbValue.ItemIndex < 0 then exit;
          IsRef := True;

          If cbValue.ItemIndex = 0 then
            Comp := nil
          else
          If assigned(fDesigner) then
            Comp := fDesigner.GetComponent(cbValue.Items[cbValue.ItemIndex])
          else
            Comp := fModule.FindComponent(cbValue.Items[cbValue.ItemIndex]);

          OldObj := GetObjectProp(fObject, fProp);
          If OldObj = Comp then exit;

          SetObjectProp(fObject, fProp, Comp);
        End;
    End;
  Except
    On E: Exception do
    Begin
      MessageDlg(Format('Unable to set %s:' + sLineBreak + '%s', [vgPropName(fProp), E.Message]), mtError, [mbOK], 0);
      ShowProperties(fObject);
      exit;
    End;
  End;

  NotifyModified(fObject);

  If IsRef then
  Begin
    //a new reference can add or remove whole branches (e.g. Module.Instance)
    Selected := fObject;
    BuildTree(Selected);
  End else
    ShowProperties(fObject);

  UpdateStatus;
end;

procedure TvgSessionEditorFM.NotifyModified(aObj: TPersistent);
  Var Root   : TPersistent;
      D      : IDesigner;
begin
  If assigned(fDesigner) then
    fDesigner.Modified;

  //the window is usually on another form: mark that one modified too
  Root := aObj;
  While (Root is TCollectionItem) and assigned(TCollectionItem(Root).Collection) do
    Root := TCollectionItem(Root).Collection.Owner;

  If (Root is TComponent) and (TComponent(Root).Owner <> fModule) and
     Supports(FindRootDesigner(Root), IDesigner, D) and (D <> fDesigner) then
    D.Modified;

  If assigned(fModule.Window) and Supports(FindRootDesigner(fModule.Window), IDesigner, D) and
     (D <> fDesigner) then
    D.Modified;
end;

procedure TvgSessionEditorFM.UpdateStatus;
  Var Running : Boolean;
      Problem : string;
begin
  Running := fModule.SessionActive;
  Problem := fModule.SessionProblem;

  If Running then
  Begin
    lblStatus.Caption    := 'Session: ENABLED';
    lblStatus.Font.Color := clGreen;
  End else
  If Problem <> '' then
  Begin
    lblStatus.Caption    := 'Session: disabled - ' + Problem;
    lblStatus.Font.Color := clMaroon;
  End else
  Begin
    lblStatus.Caption    := 'Session: disabled';
    lblStatus.Font.Color := clWindowText;
  End;

  btnBuild.Enabled   := not Running and assigned(fOnBuild);
  btnEnable.Enabled  := not Running and (Problem = '');
  btnDisable.Enabled := Running;
end;

procedure TvgSessionEditorFM.btnApplyClick(Sender: TObject);
begin
  ApplyValue;
end;

procedure TvgSessionEditorFM.cbValueChange(Sender: TObject);
begin
  ApplyValue;
end;

procedure TvgSessionEditorFM.clbValueClickCheck(Sender: TObject);
begin
  ApplyValue;
end;

procedure TvgSessionEditorFM.edValueKeyPress(Sender: TObject; var Key: Char);
begin
  If Key = #13 then
  Begin
    Key := #0;
    ApplyValue;
  End;
end;

procedure TvgSessionEditorFM.btnBuildClick(Sender: TObject);
begin
  If not assigned(fOnBuild) then exit;
  Try
    fOnBuild();
  Except
    On E: Exception do
      MessageDlg('Unable to build the session:' + sLineBreak + E.Message, mtError, [mbOK], 0);
  End;
  BuildTree(fObject);
  UpdateStatus;
end;

procedure TvgSessionEditorFM.btnEnableClick(Sender: TObject);
begin
  Screen.Cursor := crHourGlass;
  Try
    Try
      fModule.EnableSession;
    Except
      On E: Exception do
        MessageDlg('Unable to enable the Vulkan session:' + sLineBreak + E.Message, mtError, [mbOK], 0);
    End;
  Finally
    Screen.Cursor := crDefault;
  End;

  //enabling fills in run time values (physical devices, formats ...)
  BuildTree(fObject);
  UpdateStatus;
end;

procedure TvgSessionEditorFM.btnDisableClick(Sender: TObject);
begin
  Try
    fModule.DisableSession;
  Except
    On E: Exception do
      MessageDlg('Unable to disable the Vulkan session:' + sLineBreak + E.Message, mtError, [mbOK], 0);
  End;

  BuildTree(fObject);
  UpdateStatus;
end;

procedure TvgSessionEditorFM.btnRefreshClick(Sender: TObject);
begin
  BuildTree(fObject);
  UpdateStatus;
end;

end.
