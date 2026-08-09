unit GraphicPipeEditFM;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Buttons,
  Vcl.ComCtrls,
  Vulkan_Components;

type
  TPipeEditorFM = class(TForm)
    TabControl1: TTabControl;
    SHTemplate: TMemo;
    SHType: TRadioGroup;
    BuildBTN: TBitBtn;
    Panel1: TPanel;
    SD1: TSaveDialog;
    BitBtn1: TBitBtn;
    procedure BuildBTNClick(Sender: TObject);
    procedure SHTypeClick(Sender: TObject);
  private
    { Private declarations }
    fGraphicPipe : TvgGraphicPipeline;
    procedure SetGraphicPipe(const Value: TvgGraphicPipeline);
    function GetGraphicPipe: TvgGraphicPipeline;
  public
    { Public declarations }
    Property GraphicPipe : TvgGraphicPipeline Read GetGraphicPipe write SetGraphicPipe;
  end;

  Procedure RunGraphicPipelineEditor(aPipe: TvgGraphicPipeline);

var
  PipeEditorFM: TPipeEditorFM=Nil;

implementation

{$R *.dfm}

Procedure RunGraphicPipelineEditor(aPipe: TvgGraphicPipeline);
Begin
  If not assigned(aPipe) then exit;

  PipeEditorFM:= TPipeEditorFM.Create(Application.MainForm);
  PipeEditorFM.GraphicPipe:=aPipe;

  If PipeEditorFM.ShowModal=mrOK then
  Begin


  End;

  FreeAndNil(PipeEditorFM);
End;

{ TForm1 }

procedure TPipeEditorFM.BuildBTNClick(Sender: TObject);
  Var S:String;
begin
  If not assigned(fGraphicPipe) then exit;
  Case  SHType.ItemIndex of
     0: S:=fGraphicPipe.BuildVertexShader ;
     1: S:=fGraphicPipe.BuildGeometryShader;
     2: S:=fGraphicPipe.BuildFragmentShader;
  End;

  If S<>'' then
     SHTemplate.Lines.Add(S)
  else
     SHTemplate.lines.Clear;
end;

function TPipeEditorFM.GetGraphicPipe: TvgGraphicPipeline;
begin
  Result := fGraphicPipe;
end;

procedure TPipeEditorFM.SetGraphicPipe(const Value: TvgGraphicPipeline);
begin
  If fGraphicPipe=Value then exit;
  fGraphicPipe:=Value;
  If not assigned(fGraphicPipe) then exit;



end;

procedure TPipeEditorFM.SHTypeClick(Sender: TObject);
begin
  SHTemplate.Lines.Clear;
end;

end.
