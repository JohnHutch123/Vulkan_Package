object TestVulkan: TTestVulkan
  Left = 0
  Top = 0
  Caption = 'TestVulkan'
  ClientHeight = 805
  ClientWidth = 1114
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
  object StatusBar1: TStatusBar
    Left = 0
    Top = 770
    Width = 1114
    Height = 35
    Panels = <
      item
        Text = 'test'
        Width = 600
      end>
  end
  object Panel1: TPanel
    Left = 0
    Top = 0
    Width = 345
    Height = 770
    Align = alLeft
    TabOrder = 1
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
      Left = 207
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
      Top = 138
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
    object BitBtn2: TBitBtn
      Left = 208
      Top = 251
      Width = 97
      Height = 25
      Caption = 'Expand Window'
      TabOrder = 6
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
      TabOrder = 7
    end
    object ValidationCB: TCheckBox
      Left = 16
      Top = 301
      Width = 97
      Height = 17
      Caption = 'Validation ON'
      Checked = True
      State = cbChecked
      TabOrder = 8
    end
    object Button6: TButton
      Left = 208
      Top = 200
      Width = 105
      Height = 25
      Caption = 'Trigger Draw'
      TabOrder = 9
      OnClick = Button6Click
    end
    object Button7: TButton
      Left = 208
      Top = 102
      Width = 105
      Height = 25
      Caption = 'Load Scene'
      TabOrder = 10
      OnClick = Button7Click
    end
    object LoadFileBtn: TButton
      Left = 208
      Top = 351
      Width = 105
      Height = 25
      Caption = 'Load File...'
      TabOrder = 11
      OnClick = LoadFileBtnClick
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
      ItemIndex = 2
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
    object ThreadC: TEdit
      Left = 128
      Top = 228
      Width = 57
      Height = 21
      TabOrder = 18
      Text = '1'
    end
    object SceneResetCB: TCheckBox
      Left = 216
      Top = 228
      Width = 97
      Height = 17
      Caption = 'Scene Reset'
      Checked = True
      State = cbChecked
      TabOrder = 19
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
      TabOrder = 20
    end
    object RenderPathRB: TRadioGroup
      Left = 16
      Top = 183
      Width = 89
      Height = 57
      Hint = 
        'Dynamic: vkCmdBeginRendering.  Standard: a classic VkRenderPass.' +
        '  Set before Build Instance.'
      Caption = 'Render Path'
      ItemIndex = 0
      Items.Strings = (
        'Dynamic'
        'Standard')
      ParentShowHint = False
      ShowHint = True
      TabOrder = 21
    end
    object RotateCB: TCheckBox
      Left = 120
      Top = 152
      Width = 57
      Height = 17
      Caption = 'Rotate'
      Checked = True
      State = cbChecked
      TabOrder = 22
    end
    object Button10: TButton
      Left = 208
      Top = 320
      Width = 105
      Height = 25
      Caption = 'Clear Scene'
      TabOrder = 23
      OnClick = Button10Click
    end
    object BitBtn3: TBitBtn
      Left = 30
      Top = 528
      Width = 75
      Height = 25
      Caption = 'Test Data Store'
      TabOrder = 24
      OnClick = BitBtn3Click
    end
    object TestRead: TRadioGroup
      Left = 16
      Top = 423
      Width = 129
      Height = 83
      Caption = 'Test Read'
      ItemIndex = 2
      Items.Strings = (
        'Simple Triangle'
        'Data Triangle'
        'Index Triangle')
      TabOrder = 25
    end
    object SkyRB: TRadioGroup
      Left = 160
      Top = 423
      Width = 129
      Height = 99
      Hint = 'The scene'#39's sky (Vulkan_SkyBox).  Auto follows the clock.'
      Caption = 'Sky'
      ItemIndex = 0
      Items.Strings = (
        'Off'
        'Auto (clock)'
        'Day'
        'Night')
      ParentShowHint = False
      ShowHint = True
      TabOrder = 26
      OnClick = SkyRBClick
    end
    object SkyUpRB: TRadioGroup
      Left = 160
      Top = 528
      Width = 129
      Height = 81
      Hint = 
        'Which axis is up in the sky.  World is the package'#39's axis conven' +
        'tion.'
      Caption = 'Sky Up'
      ItemIndex = 0
      Items.Strings = (
        'World'
        'Y up'
        'Z up')
      ParentShowHint = False
      ShowHint = True
      TabOrder = 27
      OnClick = SkyRBClick
    end
    object NavRB: TRadioGroup
      Left = 16
      Top = 555
      Width = 129
      Height = 68
      Hint =
        'Fly/Walk: click the 3D view, then W A S D / arrows to move, Q E' +
        ' down/up (fly), Shift run, Ctrl slow; left drag looks, wheel set' +
        's speed.  Walk follows the loaded surface.'
      Caption = 'Navigation'
      ItemIndex = 0
      Items.Strings = (
        'Orbit'
        'Fly (first person)'
        'Walk (follow surface)')
      ParentShowHint = False
      ShowHint = True
      TabOrder = 29
      OnClick = NavRBClick
    end
    object FPBox: TGroupBox
      Left = 8
      Top = 626
      Width = 330
      Height = 50
      Hint = 
        'Fly/Walk settings, in scene units.  Speed 0 is automatic (the wh' +
        'eel scales it); eye height and step height are used when walking.'
      Caption = 'First person'
      ParentShowHint = False
      ShowHint = True
      TabOrder = 30
      object SpeedLbl: TLabel
        Left = 8
        Top = 22
        Width = 32
        Height = 15
        Caption = 'Speed'
      end
      object EyeLbl: TLabel
        Left = 92
        Top = 22
        Width = 18
        Height = 15
        Caption = 'Eye'
      end
      object StepLbl: TLabel
        Left = 160
        Top = 22
        Width = 23
        Height = 15
        Caption = 'Step'
      end
      object SpeedEd: TEdit
        Left = 44
        Top = 19
        Width = 42
        Height = 23
        Hint = 'Units per second; 0 = automatic'
        TabOrder = 0
        Text = '0'
        OnChange = FPSettingsChange
      end
      object EyeEd: TEdit
        Left = 114
        Top = 19
        Width = 40
        Height = 23
        Hint = 'Eye height above the surface (walk)'
        TabOrder = 1
        Text = '1.7'
        OnChange = FPSettingsChange
      end
      object StepEd: TEdit
        Left = 186
        Top = 19
        Width = 40
        Height = 23
        Hint = 'Highest step climbed (walk)'
        TabOrder = 2
        Text = '0.4'
        OnChange = FPSettingsChange
      end
      object FloatCB: TCheckBox
        Left = 234
        Top = 22
        Width = 92
        Height = 17
        Hint = 'Walk on at the same height past the edge of the surface'
        Caption = 'Float at edges'
        TabOrder = 3
        OnClick = FPSettingsChange
      end
    end
    object MessagesTxt: TMemo
      Left = 1
      Top = 679
      Width = 343
      Height = 90
      Align = alBottom
      ScrollBars = ssBoth
      TabOrder = 28
      ExplicitLeft = 0
      ExplicitTop = 626
      ExplicitWidth = 1114
    end
  end
  object OpenDialog1: TOpenDialog
    Left = 336
    Top = 160
  end
  object SkyTimer: TTimer
    Interval = 60000
    OnTimer = SkyTimerTimer
    Left = 392
    Top = 160
  end
end
