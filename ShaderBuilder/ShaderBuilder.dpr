program ShaderBuilder;

uses
  Vcl.Forms,
  ShaderBuilder_MainForm in 'ShaderBuilder_MainForm.pas' {Form8};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm8, Form8);
  Application.Run;
end.
