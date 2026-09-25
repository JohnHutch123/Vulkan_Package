object Form8: TForm8
  Left = 0
  Top = 0
  Caption = 'Form8'
  ClientHeight = 332
  ClientWidth = 847
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OnShow = FormShow
  PixelsPerInch = 96
  TextHeight = 13
  object Button1: TButton
    Left = 192
    Top = 8
    Width = 105
    Height = 25
    Caption = 'Build Instance'
    TabOrder = 0
    OnClick = Button1Click
  end
  object Button2: TButton
    Left = 192
    Top = 266
    Width = 105
    Height = 25
    Caption = 'Delete Instance'
    TabOrder = 1
    OnClick = Button2Click
  end
  object Button3: TButton
    Left = 192
    Top = 40
    Width = 105
    Height = 25
    Caption = 'Add Layers'
    TabOrder = 2
    OnClick = Button3Click
  end
  object Button4: TButton
    Left = 192
    Top = 159
    Width = 105
    Height = 25
    Caption = 'Activate Instance'
    TabOrder = 3
    OnClick = Button4Click
  end
  object Button5: TButton
    Left = 192
    Top = 71
    Width = 105
    Height = 25
    Caption = 'Add Extensions'
    TabOrder = 4
    OnClick = Button5Click
  end
  object BitBtn1: TBitBtn
    Left = 192
    Top = 112
    Width = 105
    Height = 25
    Caption = 'Test Read/Write'
    TabOrder = 5
    OnClick = BitBtn1Click
  end
  object StatusBar1: TStatusBar
    Left = 0
    Top = 297
    Width = 847
    Height = 35
    Panels = <
      item
        Text = 'test'
        Width = 50
      end>
  end
  object BitBtn2: TBitBtn
    Left = 192
    Top = 190
    Width = 105
    Height = 25
    Caption = 'Expand Window'
    TabOrder = 7
    OnClick = BitBtn2Click
  end
  object Edit1: TEdit
    Left = 32
    Top = 24
    Width = 121
    Height = 21
    TabOrder = 8
    Text = 'Edit1'
  end
  object BitBtn3: TBitBtn
    Left = 192
    Top = 221
    Width = 105
    Height = 25
    Caption = 'DeActivate Instance'
    TabOrder = 9
    OnClick = BitBtn3Click
  end
end
