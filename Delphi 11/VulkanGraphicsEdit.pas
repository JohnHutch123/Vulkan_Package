unit VulkanGraphicsEdit;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls;

type
  TVGEditor = class(TForm)
    Panel1: TPanel;
    Splitter1: TSplitter;
  private
    { Private declarations }

  protected

  public
    { Public declarations }
  end;

Procedure RunVGEditor_Form(aForm:TForm);
Procedure RunVGEditor_DataModule(aDataModule:TDataModule);


var
  VGEditor: TVGEditor=nil;

implementation

{$R *.dfm}
Procedure RunVGEditor_Form(aForm:TForm);
Begin

End;
Procedure RunVGEditor_DataModule(aDataModule:TDataModule);
Begin

End;

end.
