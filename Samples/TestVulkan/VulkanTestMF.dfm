object TestVulkan: TTestVulkan
  Left = 0
  Top = 0
  Caption = 'TestVulkan'
  ClientHeight = 634
  ClientWidth = 823
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OnClose = FormClose
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnShow = FormShow
  TextHeight = 13
  object Label1: TLabel
    Left = 344
    Top = 37
    Width = 97
    Height = 13
    Caption = 'Support File Folder :'
  end
  object Button1: TButton
    Left = 208
    Top = 8
    Width = 105
    Height = 25
    Caption = 'Build Instance'
    TabOrder = 0
    OnClick = Button1Click
  end
  object Button2: TButton
    Left = 208
    Top = 392
    Width = 105
    Height = 25
    Caption = 'Delete Instance'
    TabOrder = 1
    OnClick = Button2Click
  end
  object Button3: TButton
    Left = 208
    Top = 40
    Width = 105
    Height = 25
    Caption = 'Add Layers'
    TabOrder = 2
    OnClick = Button3Click
  end
  object Button4: TButton
    Left = 208
    Top = 141
    Width = 105
    Height = 25
    Caption = 'Enable Instance'
    TabOrder = 3
    OnClick = Button4Click
  end
  object Button5: TButton
    Left = 208
    Top = 71
    Width = 105
    Height = 25
    Caption = 'Add Extensions'
    TabOrder = 4
    OnClick = Button5Click
  end
  object BitBtn1: TBitBtn
    Left = 208
    Top = 289
    Width = 105
    Height = 25
    Caption = 'Disable Instance'
    TabOrder = 5
    OnClick = BitBtn1Click
  end
  object StatusBar1: TStatusBar
    Left = 0
    Top = 599
    Width = 823
    Height = 35
    Panels = <
      item
        Text = 'test'
        Width = 50
      end>
  end
  object BitBtn2: TBitBtn
    Left = 208
    Top = 251
    Width = 97
    Height = 25
    Caption = 'Expand Window'
    TabOrder = 7
    OnClick = BitBtn2Click
  end
  object WType: TRadioGroup
    Left = 8
    Top = 8
    Width = 81
    Height = 57
    Caption = 'Window Type'
    ItemIndex = 0
    Items.Strings = (
      'VCL'
      'SDL2')
    TabOrder = 8
  end
  object ValidationCB: TCheckBox
    Left = 16
    Top = 301
    Width = 97
    Height = 17
    Caption = 'Validation ON'
    Checked = True
    State = cbChecked
    TabOrder = 9
  end
  object Button6: TButton
    Left = 208
    Top = 200
    Width = 105
    Height = 25
    Caption = 'Trigger Draw'
    TabOrder = 10
    OnClick = Button6Click
  end
  object Button7: TButton
    Left = 208
    Top = 102
    Width = 105
    Height = 25
    Caption = 'Load Scene'
    TabOrder = 11
    OnClick = Button7Click
  end
  object Button8: TButton
    Left = 208
    Top = 169
    Width = 105
    Height = 25
    Caption = 'Enable Window'
    TabOrder = 12
    OnClick = Button8Click
  end
  object DeviceSel: TRadioGroup
    Left = 104
    Top = 8
    Width = 81
    Height = 58
    Caption = 'Device'
    ItemIndex = 1
    Items.Strings = (
      'GPU 0'
      'GPU 1')
    TabOrder = 13
  end
  object TestRB: TRadioGroup
    Left = 8
    Top = 71
    Width = 177
    Height = 106
    Caption = 'Tests'
    ItemIndex = 1
    Items.Strings = (
      'Simple Triangle'
      'Data Triangle'
      'Index Triangle with Depth'
      'Texture Rectangle'
      '100 Text Rect')
    TabOrder = 14
  end
  object DBCB: TCheckBox
    Left = 16
    Top = 255
    Width = 97
    Height = 17
    Caption = 'Depth Buffer ON'
    Checked = True
    State = cbChecked
    TabOrder = 15
  end
  object MSAACB: TCheckBox
    Left = 16
    Top = 278
    Width = 97
    Height = 17
    Caption = 'MSAA ON'
    Checked = True
    State = cbChecked
    TabOrder = 16
    OnClick = MSAACBClick
  end
  object SelectionCB: TCheckBox
    Left = 16
    Top = 324
    Width = 121
    Height = 17
    Caption = 'Selection'
    TabOrder = 17
  end
  object RendRB: TRadioGroup
    Left = 8
    Top = 191
    Width = 105
    Height = 58
    Caption = 'Renderer'
    ItemIndex = 0
    Items.Strings = (
      'Simple'
      'Comm Thread')
    TabOrder = 18
  end
  object ThreadC: TEdit
    Left = 128
    Top = 228
    Width = 57
    Height = 21
    TabOrder = 19
    Text = '1'
  end
  object MessagesTxt: TMemo
    Left = 0
    Top = 455
    Width = 823
    Height = 144
    Align = alBottom
    ScrollBars = ssBoth
    TabOrder = 20
  end
  object SceneResetCB: TCheckBox
    Left = 216
    Top = 228
    Width = 97
    Height = 17
    Caption = 'Scene Reset'
    Checked = True
    State = cbChecked
    TabOrder = 21
  end
  object RenderTargetRB: TRadioGroup
    Left = 16
    Top = 360
    Width = 89
    Height = 57
    Caption = 'Render Target'
    ItemIndex = 1
    Items.Strings = (
      'Screen'
      'Off Screen')
    TabOrder = 22
  end
  object RotateCB: TCheckBox
    Left = 120
    Top = 152
    Width = 57
    Height = 17
    Caption = 'Rotate'
    Checked = True
    State = cbChecked
    TabOrder = 23
  end
  object Button10: TButton
    Left = 208
    Top = 320
    Width = 105
    Height = 25
    Caption = 'Clear Scene'
    TabOrder = 24
    OnClick = Button10Click
  end
  object BitBtn3: TBitBtn
    Left = 368
    Top = 392
    Width = 75
    Height = 25
    Caption = 'Test Data Store'
    TabOrder = 25
    OnClick = BitBtn3Click
  end
  object TestRead: TRadioGroup
    Left = 368
    Top = 278
    Width = 129
    Height = 83
    Caption = 'Test Read'
    ItemIndex = 2
    Items.Strings = (
      'Simple Triangle'
      'Data Triangle'
      'Index Triangle')
    TabOrder = 26
  end
  object Button9: TButton
    Left = 344
    Top = 92
    Width = 75
    Height = 25
    Caption = 'Select Folder'
    TabOrder = 27
    OnClick = Button9Click
  end
  object SupportFolderEDT: TEdit
    Left = 344
    Top = 65
    Width = 281
    Height = 21
    TabOrder = 28
  end
  object BitBtn4: TBitBtn
    Left = 208
    Top = 351
    Width = 105
    Height = 25
    Caption = 'get Shader Template'
    TabOrder = 29
  end
  object OpenDialog1: TOpenDialog
    Left = 256
    Top = 400
  end
  object DataFolderDlg: TFileOpenDialog
    FavoriteLinks = <>
    FileTypes = <>
    Options = [fdoPickFolders, fdoPathMustExist]
    Left = 488
    Top = 128
  end
end
