unit RenderEngineEditFM;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.Buttons, Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vulkan_Components,
  GraphicPipeEditFM;

type
  TRenderEngineFM = class(TForm)
    TabControl1: TTabControl;
    GPDrop: TComboBox;
    BitBtn1: TBitBtn;
    procedure BitBtn1Click(Sender: TObject);

  private
    { Private declarations }
    fRenderEngine : TvgRenderEngine;

 //   function GetPipe: TvgRenderEngine_Abstract;
//    procedure SetPipe(const Value: TvgRenderEngine_Abstract);

  public
    { Public declarations }
//    Property RenderEngine : TvgRenderEngine_Abstract Read GetPipe write SetPipe;
  end;

  Procedure RunRenderEngineEditor(aRenderEngine:TvgRenderEngine);

var
  RenderEngineFM: TRenderEngineFM = nil;

implementation

{$R *.dfm}
  Procedure RunRenderEngineEditor(aRenderEngine:TvgRenderEngine);
  Begin
    If not assigned(aRenderEngine) then exit;

    RenderEngineFM := TRenderEngineFM.Create(Application.MainForm);
  //  RenderEngineFM.RenderEngine := aRenderEngine;

    If RenderEngineFM.ShowModal=mrOK then
    Begin

    end;

    FreeAndNil(RenderEngineFM);
  End;


{ TRenderEngineFM }

procedure TRenderEngineFM.BitBtn1Click(Sender: TObject);
  Var I:Integer;
begin
  If GPDrop.ItemIndex=-1 then exit;
  I:= GPDrop.ItemIndex;

  If assigned(fRenderEngine.GraphicPipes.Items[I].GraphicPipe) then
     RunGraphicPipelineEditor(fRenderEngine.GraphicPipes.Items[I].GraphicPipe);

end;
(*
function TRenderEngineFM.GetPipe: TvgRenderEngine_Abstract;
begin
  Result := fRenderEngine;
end;

procedure TRenderEngineFM.SetPipe(const Value: TvgRenderEngine_Abstract);
  Var I:Integer;
begin
  fRenderEngine:=Value;
  If not assigned(fRenderEngine) then exit;

  GPDrop.Items.Clear;
  If  fRenderEngine.GraphicPipes.Count>0 then
  Begin
     For I:=0 to fRenderEngine.GraphicPipes.Count-1 do
     Begin
       If assigned(fRenderEngine.GraphicPipes.Items[I].GraphicPipe) then
          GPDrop.Items.Add(fRenderEngine.GraphicPipes.Items[I].GraphicPipe.Name)
       else
          GPDrop.Items.Add('<NO Name>');
     End;
  End;

end;
 *)

end.
