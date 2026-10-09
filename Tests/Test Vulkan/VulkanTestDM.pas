unit VulkanTestDM;

interface

uses
  System.SysUtils, System.Classes,
  Vulkan_Components, Vulkan_WindowVCL, Vulkan_DataModule,
  Vulkan_Components_Scene_Renderer,
  Vulkan_Renderer_Single;

type
  TvgVulkanDataModule1 = class(TvgVulkanDataModule)
    vgInstance1: TvgInstance;
    vgPhysicalDevice1: TvgPhysicalDevice;
    vgScreenDevice1: TvgScreenRenderDevice;
    vgLinker1: TvgLinker;
    vgRenderer1: TvgRenderEngine_Single;
    vgScene1: TvgScene;
    vgToolManager1: TvgToolManager;
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
