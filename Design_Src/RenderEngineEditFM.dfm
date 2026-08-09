object RenderEngineFM: TRenderEngineFM
  Left = 0
  Top = 0
  Caption = 'Renderer Editor'
  ClientHeight = 371
  ClientWidth = 528
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
    Left = 272
    Top = 0
    Width = 256
    Height = 371
    Align = alRight
    TabOrder = 0
    Tabs.Strings = (
      'Graphicpipelines'
      'Renderer'
      '')
    TabIndex = 0
  end
  object GPDrop: TComboBox
    Left = 32
    Top = 120
    Width = 217
    Height = 21
    TabOrder = 1
    Text = '(select)'
  end
  object BitBtn1: TBitBtn
    Left = 32
    Top = 147
    Width = 75
    Height = 25
    Caption = 'Edit'
    TabOrder = 2
    OnClick = BitBtn1Click
  end
end
