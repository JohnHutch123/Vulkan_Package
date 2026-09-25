object PipeEditorFM: TPipeEditorFM
  Left = 0
  Top = 0
  Caption = 'Grahicpipeline Editor'
  ClientHeight = 407
  ClientWidth = 566
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  PixelsPerInch = 96
  TextHeight = 13
  object TabControl1: TTabControl
    Left = 0
    Top = 65
    Width = 566
    Height = 342
    Align = alClient
    TabOrder = 0
    Tabs.Strings = (
      'Shaders')
    TabIndex = 0
    object SHTemplate: TMemo
      Left = 136
      Top = 24
      Width = 426
      Height = 314
      Align = alRight
      Lines.Strings = (
        '')
      ScrollBars = ssBoth
      TabOrder = 0
    end
    object SHType: TRadioGroup
      Left = 16
      Top = 40
      Width = 97
      Height = 81
      Caption = 'Type'
      ItemIndex = 0
      Items.Strings = (
        'Vertex'
        'Geometry'
        'Fragment')
      TabOrder = 1
      OnClick = SHTypeClick
    end
    object BuildBTN: TBitBtn
      Left = 16
      Top = 144
      Width = 97
      Height = 33
      Caption = 'Build Template'
      TabOrder = 2
      OnClick = BuildBTNClick
    end
  end
  object Panel1: TPanel
    Left = 0
    Top = 0
    Width = 566
    Height = 65
    Align = alTop
    TabOrder = 1
    object BitBtn1: TBitBtn
      Left = 416
      Top = 16
      Width = 97
      Height = 33
      Kind = bkOK
      NumGlyphs = 2
      TabOrder = 0
    end
  end
  object SD1: TSaveDialog
    Left = 24
    Top = 257
  end
end
