unit SimpletestDM;

interface

uses
  System.SysUtils, System.Classes,
  Vulkan_Components, Vulkan_WindowVCL, Vulkan_DataModule,
  Vulkan_Components_Scene_Renderer;

type
  TvgVulkanDataModule1 = class(TvgVulkanDataModule)
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  vgVulkanDataModule1: TvgVulkanDataModule1;

implementation

{%CLASSGROUP 'Vcl.Controls.TControl'}

{$R *.dfm}

end.
