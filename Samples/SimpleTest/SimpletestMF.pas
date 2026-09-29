unit SimpletestMF;

interface

uses
  Vulkan,
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Buttons,
  Vcl.ExtCtrls,
  Generics.Collections,
  Generics.Defaults,
  System.IOUtils,
  PasVulkan.Math,{PasVulkan.Application,}
  PasVulkan.Math.double,{PasVulkan.Application,}

  Vulkan_Components,
  Vulkan_Components_Lookups,
  Vulkan_Components_Descriptors,
  Vulkan_Renderer_Single,
  Vulkan_Components_Scene_Renderer,
  Vulkan_Components_DataStore,
  Vulkan_Components_ShaderCompiler,
  Vulkan_WindowVCL;


type
  TForm8 = class(TForm)
    Button1: TButton;
    procedure Button1Click(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    { Private declarations }

    fInstance : TvgInstance;
    fPhysicalDevice   : TvgPhysicalDevice;
    fScreenDevice     : TvgScreenRenderDevice;
    fLinker  : TvgLinker;
    fVCLWin   : TvgWindowVCL ;
    fGP       : TvgGraphicPipeline;
    fRenderer   : TvgRenderEngine;
    fScene      : TvgScene;
    fToolManager:TvgToolManager;

  protected
    Procedure CleanUp;


  public
    { Public declarations }
  end;

var
  Form8: TForm8;

implementation

{$R *.dfm}

procedure TForm8.Button1Click(Sender: TObject);
begin
  //  WType.Enabled:=False;
    Assert(not assigned(fInstance), 'Instance already created');

    fInstance := TvgInstance.Create(self);

    fInstance.MemAllocation := VG_VULKAN_MANAGE;
 //   fInstance.Validation    := ValidationCB.Checked;
    fInstance.APIVersion    := VG_API_VERSION_1_3;

    fInstance.DescriptorIndexing  := True;

end;

procedure TForm8.CleanUp;
begin
  If assigned(fInstance) then
    fInstance.Active:=False;


  If assigned(fInstance) then
    FreeAndNil(fInstance);

end;

procedure TForm8.FormDestroy(Sender: TObject);
begin
   cleanup;

end;

end.
