unit VulkanTestMF;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vulkan,
  Vulkan_Components,
  Vulkan_WindowVCL,
  Data.DB, Datasnap.DBClient, Datasnap.Provider,
  Data.Win.ADODB,  Vcl.StdCtrls, Vcl.ComCtrls,
  Vcl.Buttons, VulkanTestDM, Vcl.ExtCtrls,
  Vulkan_DataModule;

type
  TForm8 = class(TForm)
    StatusBar1: TStatusBar;
    Panel1: TPanel;
    Button1: TButton;
    SceneOpenDlg: TOpenDialog;
    Button2: TButton;
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
  private
    { Private declarations }

    fVCLWindow :  TvgWindowVCL;
    fVulkanDM  :  TvgVulkanDataModule;

  public
    { Public declarations }
  end;

var
  Form8: TForm8;

implementation

{$R *.dfm}

procedure TForm8.Button1Click(Sender: TObject);
begin
  fVCLWindow        := TvgWindowVCL.Create(self);
  fVCLWindow.Parent := self;
  fVCLWindow.Align  := alClient;

  fVulkanDM  :=  TvgVulkanDataModule.Create(self);

  fVulkanDM.BuildSession;

  fVulkanDM.BuildScene;
  fVulkanDM.BuildRenderer;
  fVulkanDM.BuildToolManager;



  fVulkanDM.Window := fVCLWindow;


  fVulkanDM.EnableSession;





end;

procedure TForm8.Button2Click(Sender: TObject);
begin
  If  SceneOpenDlg.execute then
  Begin

    fVulkanDM.ClearScene;
    fVulkanDM.LoadScene(SceneOpenDlg.FileName)   ;

  End;
end;

end.
