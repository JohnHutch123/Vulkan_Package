program VulcanTest;

uses
  Vcl.Forms,
  VulkanTestMF in 'VulkanTestMF.pas' {Form8},
  Vulkan_Components in '..\RunTime_Src\Vulkan_Components.pas',
  Vulkan_Components_Scene_Renderer in '..\RunTime_Src\Vulkan_Components_Scene_Renderer.pas',
  Vulkan_DataModule in '..\RunTime_Src\Vulkan_DataModule.pas',
  Vulkan_WindowVCL in '..\RunTime_Src\Vulkan_WindowVCL.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm8, Form8);

  Application.Run;
end.
