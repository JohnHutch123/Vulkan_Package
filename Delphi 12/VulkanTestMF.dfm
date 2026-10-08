object Form8: TForm8
  Left = 0
  Top = 0
  Caption = 'Form8'
  ClientHeight = 548
  ClientWidth = 923
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  TextHeight = 13
  object StatusBar1: TStatusBar
    Left = 0
    Top = 513
    Width = 923
    Height = 35
    Panels = <
      item
        Text = 'test'
        Width = 50
      end>
  end
  object Panel1: TPanel
    Left = 0
    Top = 0
    Width = 145
    Height = 513
    Align = alLeft
    TabOrder = 1
    object Button1: TButton
      Left = 16
      Top = 24
      Width = 105
      Height = 25
      Caption = 'Build Data Module'
      TabOrder = 0
      OnClick = Button1Click
    end
    object Button2: TButton
      Left = 16
      Top = 80
      Width = 105
      Height = 25
      Caption = 'Open Scene'
      TabOrder = 1
      OnClick = Button2Click
    end
  end
  object SceneOpenDlg: TOpenDialog
    Filter = 'GLTF ( *.gltf)|*.gltf|All Files (*.*|*.*'
    Options = [ofHideReadOnly, ofPathMustExist, ofFileMustExist, ofEnableSizing]
    Left = 200
    Top = 88
  end
end
