object vgSessionEditorFM: TvgSessionEditorFM
  Left = 0
  Top = 0
  Caption = 'Vulkan Session Editor'
  ClientHeight = 560
  ClientWidth = 1000
  Color = clBtnFace
  Constraints.MinHeight = 400
  Constraints.MinWidth = 1000
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnShow = FormShow
  TextHeight = 15
  object Splitter1: TSplitter
    Left = 260
    Top = 41
    Height = 478
    ExplicitLeft = 256
    ExplicitTop = 48
    ExplicitHeight = 100
  end
  object pnlTop: TPanel
    Left = 0
    Top = 0
    Width = 1000
    Height = 41
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object lblStatus: TLabel
      Left = 574
      Top = 12
      Width = 95
      Height = 15
      Caption = 'Session: disabled'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object btnBuild: TButton
      Left = 8
      Top = 8
      Width = 81
      Height = 25
      Hint = 'Create any missing Instance, Physical Device, Screen Device and Linker and connect them'
      Caption = '&Build'
      ParentShowHint = False
      ShowHint = True
      TabOrder = 0
      OnClick = btnBuildClick
    end
    object btnAddLinker: TButton
      Left = 95
      Top = 8
      Width = 105
      Height = 25
      Hint = 'Add another Linker on the Screen Device - one per window'
      Caption = 'Add &Linker'
      ParentShowHint = False
      ShowHint = True
      TabOrder = 4
      OnClick = btnAddLinkerClick
    end
    object btnLoadScene: TButton
      Left = 206
      Top = 8
      Width = 105
      Height = 25
      Hint = 'Pick a scene file and load it into the session'#39's Scene with a registered scene loader'
      Caption = 'Load &Scene...'
      ParentShowHint = False
      ShowHint = True
      TabOrder = 5
      OnClick = btnLoadSceneClick
    end
    object btnEnable: TButton
      Left = 317
      Top = 8
      Width = 81
      Height = 25
      Hint = 'Start the Vulkan session'
      Caption = '&Enable'
      ParentShowHint = False
      ShowHint = True
      TabOrder = 1
      OnClick = btnEnableClick
    end
    object btnDisable: TButton
      Left = 404
      Top = 8
      Width = 81
      Height = 25
      Hint = 'Shut the Vulkan session down'
      Caption = '&Disable'
      ParentShowHint = False
      ShowHint = True
      TabOrder = 2
      OnClick = btnDisableClick
    end
    object btnRefresh: TButton
      Left = 491
      Top = 8
      Width = 75
      Height = 25
      Hint = 'Re-read the session components and their properties'
      Caption = '&Refresh'
      ParentShowHint = False
      ShowHint = True
      TabOrder = 3
      OnClick = btnRefreshClick
    end
  end
  object pnlBottom: TPanel
    Left = 0
    Top = 519
    Width = 1000
    Height = 41
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 3
    DesignSize = (
      1000
      41)
    object btnClose: TButton
      Left = 917
      Top = 8
      Width = 75
      Height = 25
      Anchors = [akTop, akRight]
      Cancel = True
      Caption = 'Close'
      ModalResult = 1
      TabOrder = 0
    end
  end
  object tvObjects: TTreeView
    Left = 0
    Top = 41
    Width = 260
    Height = 478
    Align = alLeft
    HideSelection = False
    Indent = 19
    ReadOnly = True
    TabOrder = 1
    OnChange = tvObjectsChange
  end
  object pnlRight: TPanel
    Left = 263
    Top = 41
    Width = 737
    Height = 478
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 2
    object lvProps: TListView
      Left = 0
      Top = 0
      Width = 737
      Height = 358
      Align = alClient
      Columns = <
        item
          Caption = 'Property'
          Width = 170
        end
        item
          Caption = 'Value'
          Width = 220
        end
        item
          Caption = 'Type'
          Width = 140
        end>
      HideSelection = False
      ReadOnly = True
      RowSelect = True
      TabOrder = 0
      ViewStyle = vsReport
      OnSelectItem = lvPropsSelectItem
    end
    object pnlEdit: TPanel
      Left = 0
      Top = 358
      Width = 737
      Height = 120
      Align = alBottom
      BevelOuter = bvNone
      TabOrder = 1
      DesignSize = (
        737
        120)
      object lblPropName: TLabel
        Left = 8
        Top = 6
        Width = 3
        Height = 15
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = [fsBold]
        ParentFont = False
      end
      object lblHint: TLabel
        Left = 8
        Top = 100
        Width = 721
        Height = 15
        Anchors = [akLeft, akRight, akBottom]
        AutoSize = False
        Caption = 'Select a property to edit it.'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGrayText
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = []
        ParentFont = False
      end
      object edValue: TEdit
        Left = 8
        Top = 28
        Width = 640
        Height = 23
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 0
        Visible = False
        OnKeyPress = edValueKeyPress
      end
      object cbValue: TComboBox
        Left = 8
        Top = 28
        Width = 640
        Height = 23
        Style = csDropDownList
        Anchors = [akLeft, akTop, akRight]
        DropDownCount = 24
        TabOrder = 1
        Visible = False
        OnChange = cbValueChange
      end
      object clbValue: TCheckListBox
        Left = 8
        Top = 28
        Width = 721
        Height = 68
        Anchors = [akLeft, akTop, akRight, akBottom]
        Columns = 2
        ItemHeight = 17
        TabOrder = 2
        Visible = False
        OnClickCheck = clbValueClickCheck
      end
      object btnApply: TButton
        Left = 654
        Top = 27
        Width = 75
        Height = 25
        Anchors = [akTop, akRight]
        Caption = '&Apply'
        TabOrder = 3
        Visible = False
        OnClick = btnApplyClick
      end
    end
  end
end
