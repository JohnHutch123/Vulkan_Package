program VulcanTest_Components;

{$INCLUDE VulkanPackage.inc}

uses

  {$IFDEF FASTMM5}
  FastMM5,
  {$ENDIF}
  Vcl.Forms,
  ComponentTestMF in 'ComponentTestMF.pas' {Form1};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
