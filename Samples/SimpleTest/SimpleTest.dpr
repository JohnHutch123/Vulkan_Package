program SimpleTest;

uses
  Vcl.Forms,
  SimpletestMF in 'SimpletestMF.pas' {Form8},
  Vulkan in 'D:\Vulkan\src\Vulkan.pas',
  Vulkan_Components_Scene_Renderer in '..\..\RunTime_Src\Vulkan_Components_Scene_Renderer.pas',
  Vulkan_Components_Lookups in '..\..\RunTime_Src\Vulkan_Components_Lookups.pas',
  Vulkan_Components_DataStore in '..\..\RunTime_Src\Vulkan_Components_DataStore.pas',
  Vulkan_Components_Compute in '..\..\RunTime_Src\Vulkan_Components_Compute.pas',
  Vulkan_Components_Camera in '..\..\RunTime_Src\Vulkan_Components_Camera.pas',
  Vulkan_Components in '..\..\RunTime_Src\Vulkan_Components.pas',
  SimpletestDM in 'SimpletestDM.pas' {vgVulkanDataModule1: TvgVulkanDataModule};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm8, Form8);
  Application.CreateForm(TvgVulkanDataModule1, vgVulkanDataModule1);
  Application.Run;
end.
